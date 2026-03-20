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
///
/// The VFS namespace is materialized into a flat in-memory representation (FlatVFS)
/// on the Swift side — zero disk I/O from the parent process. The forked child
/// writes the flat VFS to a temp directory for blink's VFS layer to consume.
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

        // 1. Build flat in-memory VFS from namespace (no disk I/O)
        let flatVFS = FlatVFS.from(namespace: namespace)

        // 2. Build the guest binary path
        let guestBinaryPath = binaryPath.hasPrefix("/") ? binaryPath : "/\(binaryPath)"

        // 3. Build argv: program name + user args
        let fullArgs = [guestBinaryPath] + args

        // 4. Build envp as "KEY=VALUE" strings
        var envStringsMut: [String] = env.map { "\($0.key)=\($0.value)" }
        if !networkEnabled {
            envStringsMut.append("BLINK_DISABLE_NETWORKING=1")
        }
        let envStrings = envStringsMut

        // 5. Call blink via the C shim with in-memory VFS (fork-isolated)
        let result: ExecResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(
                label: "omnikit.blink.exec.\(UUID().uuidString)"
            ).async {
                do {
                    let execResult = try Self.runBlinkMemVFS(
                        programPath: guestBinaryPath,
                        argv: fullArgs,
                        envp: envStrings,
                        flatVFS: flatVFS,
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

    /// Build a C flatvfs_t from a FlatVFS and call blink_run_captured_memvfs.
    private static func runBlinkMemVFS(
        programPath: String,
        argv: [String],
        envp: [String],
        flatVFS: FlatVFS,
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

        var config = blink_run_config_t()
        config.program_path = UnsafePointer(cProgramPath)
        config.argv = cArgv.withUnsafeBufferPointer { buf in
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
        config.vfs_prefix = nil

        // Build C flatvfs_t from FlatVFS
        let cEntries = buildCFlatVFS(flatVFS)
        defer { freeCFlatVFS(cEntries.entries, count: cEntries.count) }

        var flatvfs = flatvfs_t()
        flatvfs.entries = UnsafePointer(cEntries.entries)
        flatvfs.entry_count = Int32(cEntries.count)

        var result = blink_run_result_t()
        let rc = blink_run_captured_memvfs(&config, &result, Int32(timeoutMs), &flatvfs)

        if rc != 0 {
            blink_result_free(&result)
            throw ContainerError.executionFailed(
                "blink_run_captured_memvfs failed: \(String(cString: strerror(errno)))"
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

    // MARK: - C FlatVFS conversion

    private struct CFlatVFSResult {
        let entries: UnsafeMutablePointer<flatvfs_entry_t>
        let count: Int
    }

    /// Convert a FlatVFS to an array of C flatvfs_entry_t structs.
    private static func buildCFlatVFS(_ flat: FlatVFS) -> CFlatVFSResult {
        let count = flat.entries.count
        let entries = UnsafeMutablePointer<flatvfs_entry_t>.allocate(capacity: count)

        for (i, entry) in flat.entries.enumerated() {
            var cEntry = flatvfs_entry_t()
            cEntry.path = UnsafePointer(strdup(entry.path))
            cEntry.type = entry.type.rawValue
            cEntry.mode = entry.mode

            if entry.type == .file && !entry.data.isEmpty {
                let dataBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: entry.data.count)
                entry.data.withUnsafeBufferPointer { buf in
                    dataBuf.initialize(from: buf.baseAddress!, count: buf.count)
                }
                cEntry.data = UnsafePointer(dataBuf)
                cEntry.data_size = entry.data.count
            } else {
                cEntry.data = nil
                cEntry.data_size = 0
            }

            if entry.type == .symlink && !entry.symlinkTarget.isEmpty {
                cEntry.symlink_target = UnsafePointer(strdup(entry.symlinkTarget))
            } else {
                cEntry.symlink_target = nil
            }

            entries[i] = cEntry
        }

        return CFlatVFSResult(entries: entries, count: count)
    }

    /// Free memory allocated by buildCFlatVFS.
    private static func freeCFlatVFS(_ entries: UnsafeMutablePointer<flatvfs_entry_t>, count: Int) {
        for i in 0..<count {
            let e = entries[i]
            free(UnsafeMutablePointer(mutating: e.path))
            if let data = e.data {
                UnsafeMutablePointer(mutating: data).deallocate()
            }
            if let target = e.symlink_target {
                free(UnsafeMutablePointer(mutating: target))
            }
        }
        entries.deallocate()
    }
}
