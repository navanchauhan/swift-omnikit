import Foundation
import OmniVFS
import OmniExecution
import CBlinkEmulator

/// Executes x86-64 ELF binaries via the embedded blink emulator library.
///
/// Uses a vendored static build of blink (https://github.com/jart/blink) linked
/// directly into the process, eliminating the need for an external `blink` binary.
/// Execution is fork-isolated: each run spawns a child process that loads the ELF
/// binary into blink's x86-64 VM, captures stdout/stderr via pipes, and returns
/// the exit code to the parent.
public final class BlinkRuntime: ContainerRuntime, Sendable {

    /// Whether networking is allowed.
    private let networkEnabled: Bool

    public init(blinkPath: String? = nil, networkEnabled: Bool = false) {
        // blinkPath is ignored — we use the embedded library.
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

        // 2. Build the guest binary path within the overlay
        let guestBinaryPath = binaryPath.hasPrefix("/") ? binaryPath : "/\(binaryPath)"

        // 3. Build the full path to the binary on the host (within the materialized rootfs)
        let hostBinaryPath = tempDir.path + guestBinaryPath

        // 4. Build argv: program name + user args
        let fullArgs = [guestBinaryPath] + args

        // 5. Build envp as "KEY=VALUE" strings
        var envStringsMut: [String] = env.map { "\($0.key)=\($0.value)" }
        if !networkEnabled {
            envStringsMut.append("BLINK_DISABLE_NETWORKING=1")
        }
        let envStrings = envStringsMut

        // 6. Call blink via the C shim (fork-isolated)
        let result: ExecResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(
                label: "omnikit.blink.exec.\(UUID().uuidString)"
            ).async {
                do {
                    let execResult = try Self.runBlink(
                        programPath: hostBinaryPath,
                        argv: fullArgs,
                        envp: envStrings,
                        vfsPrefix: tempDir.path,
                        timeoutMs: timeoutMs
                    )

                    let elapsed = DispatchTime.now().uptimeNanoseconds
                        - startTime.uptimeNanoseconds
                    let durationMs = Int(elapsed / 1_000_000)

                    let result = ExecResult(
                        stdout: execResult.stdout,
                        stderr: execResult.stderr,
                        exitCode: execResult.exitCode,
                        timedOut: execResult.timedOut,
                        durationMs: durationMs
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

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

    // MARK: - Private

    private struct BlinkExecResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        let timedOut: Bool
    }

    /// Call into CBlinkEmulator to run an ELF binary.
    private static func runBlink(
        programPath: String,
        argv: [String],
        envp: [String],
        vfsPrefix: String,
        timeoutMs: Int
    ) throws -> BlinkExecResult {
        // Convert Swift strings to C strings for the config.
        let cProgramPath = programPath.withCString { strdup($0)! }
        defer { free(cProgramPath) }

        // Build argv as C array.
        var cArgv: [UnsafePointer<CChar>?] = argv.map { str in
            UnsafePointer(strdup(str))
        }
        cArgv.append(nil)
        defer {
            for ptr in cArgv where ptr != nil {
                free(UnsafeMutablePointer(mutating: ptr!))
            }
        }

        // Build envp as C array.
        var cEnvp: [UnsafePointer<CChar>?] = envp.map { str in
            UnsafePointer(strdup(str))
        }
        cEnvp.append(nil)
        defer {
            for ptr in cEnvp where ptr != nil {
                free(UnsafeMutablePointer(mutating: ptr!))
            }
        }

        let cVfsPrefix = vfsPrefix.withCString { strdup($0)! }
        defer { free(cVfsPrefix) }

        var config = blink_run_config_t()
        config.program_path = UnsafePointer(cProgramPath)
        config.argv = cArgv.withUnsafeBufferPointer { buf in
            // Safe: the buffer lives for the duration of this function.
            UnsafePointer(buf.baseAddress!.withMemoryRebound(
                to: UnsafePointer<CChar>?.self, capacity: buf.count
            ) { $0 })
        }
        config.argc = Int32(argv.count)
        config.envp = cEnvp.withUnsafeBufferPointer { buf in
            UnsafePointer(buf.baseAddress!.withMemoryRebound(
                to: UnsafePointer<CChar>?.self, capacity: buf.count
            ) { $0 })
        }
        config.envc = Int32(envp.count)
        config.vfs_prefix = UnsafePointer(cVfsPrefix)

        var result = blink_run_result_t()
        let rc = blink_run(&config, &result, Int32(timeoutMs))

        if rc != 0 {
            blink_result_free(&result)
            throw ContainerError.executionFailed(
                "blink_run failed: \(String(cString: strerror(errno)))"
            )
        }

        let stdout = result.stdout_buf.map { String(cString: $0) } ?? ""
        let stderr = result.stderr_buf.map { String(cString: $0) } ?? ""
        let exitCode = Int32(result.exit_code)
        let timedOut = result.timed_out != 0

        blink_result_free(&result)

        return BlinkExecResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            timedOut: timedOut
        )
    }
}
