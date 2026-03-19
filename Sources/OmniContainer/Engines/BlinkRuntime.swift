import Foundation
import OmniVFS
import OmniExecution

/// Executes x86-64 ELF binaries via blink emulator using overlay filesystem.
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

        // blink CLI: blink [-C OVERLAY] PROG [ARGS...]
        // The -C flag specifies the chroot/overlay directory.
        // The binary path is a guest path within the overlay.
        let guestBinaryPath = binaryPath.hasPrefix("/") ? binaryPath : "/\(binaryPath)"

        // Build arguments: -C overlay_path PROG [ARGS...]
        var blinkArgs: [String] = []
        blinkArgs.append("-C")
        blinkArgs.append(tempDir.path)
        blinkArgs.append(guestBinaryPath)
        blinkArgs.append(contentsOf: args)
        process.arguments = blinkArgs

        // Environment: pass through user env, add BLINK_PREFIX
        var processEnv = env
        processEnv["BLINK_PREFIX"] = tempDir.path
        if !networkEnabled {
            processEnv["BLINK_DISABLE_NETWORKING"] = "1"
        }
        process.environment = processEnv

        // Set current directory to the overlay root (blink manages paths internally)
        process.currentDirectoryURL = tempDir

        // 4. Capture stdout/stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // 5. Execute on dedicated queue (not cooperative thread pool)
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
        // For overlay approach, changes are in the temp dir.
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
        // Check common locations — /opt/homebrew/bin/blink is most likely on macOS ARM
        let candidates = [
            "/opt/homebrew/bin/blink",
            "/usr/local/bin/blink",
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
