import Foundation
import OmniVFS
import OmniExecution

/// Executes x86-64 ELF binaries via blink emulator using BLINK_OVERLAYS
/// for filesystem virtualization.
public final class BlinkRuntime: ContainerRuntime, Sendable {

    /// Path to the blink binary. If nil, attempts to find in PATH.
    private let blinkPath: String?
    /// Whether networking is allowed.
    private let networkEnabled: Bool

    public init(blinkPath: String? = nil, networkEnabled: Bool = false) {
        self.blinkPath = blinkPath
        self.networkEnabled = networkEnabled
    }

    public func canExecute(_ data: [UInt8]) -> Bool {
        let format = BinaryProbe.detect(data)
        return format == .elf || format == .script
    }

    public func execute(
        binaryPath: String,
        args: [String],
        env: [String: String],
        workingDir: String,
        namespace: VFSNamespace,
        timeoutMs: Int
    ) async throws -> ExecResult {
        let startTime = DispatchTime.now()

        // 1. Materialize VFS namespace to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnikit-blink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try BlinkVFSSync.materialize(namespace: namespace, to: tempDir.path)

        // 2. Resolve blink binary
        let resolvedBlink = try findBlink()

        // 3. Set up Process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedBlink)

        // blink runs the ELF binary with the overlay as root
        let guestBinaryPath = binaryPath.hasPrefix("/") ? binaryPath : "/\(binaryPath)"
        process.arguments = [guestBinaryPath] + args

        // Environment
        var processEnv = env
        processEnv["BLINK_OVERLAYS"] = tempDir.path
        if !networkEnabled {
            processEnv["BLINK_DISABLE_NETWORKING"] = "1"
        }
        process.environment = processEnv

        let cwdRelative = workingDir.hasPrefix("/")
            ? String(workingDir.dropFirst())
            : workingDir
        let cwdURL = tempDir.appendingPathComponent(cwdRelative)
        // Create workdir if it doesn't exist on the materialized tree
        try? FileManager.default.createDirectory(
            at: cwdURL, withIntermediateDirectories: true
        )
        process.currentDirectoryURL = cwdURL

        // 4. Capture stdout/stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // 5. Execute on dedicated queue (not cooperative thread pool)
        let networkAllowed = networkEnabled
        _ = networkAllowed // silence unused-variable warning; kept for future use
        let result: ExecResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(
                label: "omnikit.blink.exec.\(UUID().uuidString)"
            ).async {
                do {
                    try process.run()

                    // Timeout handling
                    let timeoutItem = DispatchWorkItem {
                        process.terminate()
                    }
                    DispatchQueue.global().asyncAfter(
                        deadline: .now() + .milliseconds(timeoutMs),
                        execute: timeoutItem
                    )

                    process.waitUntilExit()
                    timeoutItem.cancel()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let elapsed = DispatchTime.now().uptimeNanoseconds
                        - startTime.uptimeNanoseconds
                    let durationMs = Int(elapsed / 1_000_000)
                    let timedOut = process.terminationReason == .uncaughtSignal

                    let result = ExecResult(
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? "",
                        exitCode: process.terminationStatus,
                        timedOut: timedOut,
                        durationMs: durationMs
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // 6. Sync changes back to VFS
        // For BLINK_OVERLAYS approach, changes are in the temp dir.
        // Diffing back to CowFS overlay is a future enhancement.

        return result
    }

    /// Execute a shell command string through blink's /bin/sh.
    public func executeShell(
        command: String,
        env: [String: String],
        workingDir: String,
        namespace: VFSNamespace,
        timeoutMs: Int
    ) async throws -> ExecResult {
        return try await execute(
            binaryPath: "/bin/sh",
            args: ["-lc", command],
            env: env,
            workingDir: workingDir,
            namespace: namespace,
            timeoutMs: timeoutMs
        )
    }

    private func findBlink() throws -> String {
        if let path = blinkPath, FileManager.default.fileExists(atPath: path) {
            return path
        }
        // Check common locations
        let candidates = [
            "/usr/local/bin/blink",
            "/opt/homebrew/bin/blink",
            "/usr/bin/blink",
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        // Try PATH via which
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["blink"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = Pipe()
        try whichProcess.run()
        whichProcess.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            return path
        }
        throw ContainerError.engineNotAvailable(
            "blink not found. Install with: brew install blink "
            + "or download from https://github.com/jart/blink"
        )
    }
}
