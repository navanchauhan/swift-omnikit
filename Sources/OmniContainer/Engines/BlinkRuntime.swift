import Foundation
import OmniVFS
import OmniExecution
import CBlinkEmulator
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Executes x86-64 ELF binaries via the embedded blink emulator library.
///
/// Uses a vendored static build of blink (https://github.com/jart/blink) linked
/// directly into the process, eliminating the need for an external `blink` binary.
/// On hosts with `fork()`, execution stays child-process isolated. Apple mobile
/// platforms fall back to an in-process runtime because app sandboxes cannot use
/// the fork-based model.
///
public final class BlinkRuntime: LinuxGuestRuntime, Sendable {
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

        // 1. Plan the guest VFS. Read-only images stay cached; host binds stay lazy.
        let vfsPlan = BlinkVFSPlanner.buildLaunchPlan(namespace: namespace)

        // 2. Build the guest binary path
        let guestBinaryPath = binaryPath.hasPrefix("/") ? binaryPath : "/\(binaryPath)"

        // 3. Build argv: program name + user args
        let fullArgs = [guestBinaryPath] + args

        // 4. Build envp as "KEY=VALUE" strings
        var mergedEnv = env
        mergedEnv["HOME", default: "/tmp/iagentsmith-home"] = "/tmp/iagentsmith-home"
        mergedEnv["USER", default: "codex"] = "codex"
        let defaultUser = mergedEnv["USER", default: "codex"]
        mergedEnv["LOGNAME", default: defaultUser] = defaultUser
        mergedEnv["SHELL", default: "/bin/sh"] = "/bin/sh"
        mergedEnv["TMPDIR", default: "/tmp"] = "/tmp"
        mergedEnv["TERM", default: "xterm-256color"] = "xterm-256color"
        mergedEnv["PATH", default: "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        if !workingDir.isEmpty {
            mergedEnv["PWD"] = normalizeGuestWorkingDir(workingDir)
        }
        var envStringsMut: [String] = mergedEnv.map { "\($0.key)=\($0.value)" }
        if !networkEnabled {
            envStringsMut.append("BLINK_DISABLE_NETWORKING=1")
        }
        let envStrings = BlinkGuestNodeRuntime.mergedEnvironmentStrings(envStringsMut)

        // 5. Call blink via the C shim with in-memory VFS.
        let result: ExecResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(
                label: "omnikit.blink.exec.\(UUID().uuidString)"
            ).async {
                do {
                    let execResult = try Self.runBlinkMemVFS(
                        programPath: guestBinaryPath,
                        argv: fullArgs,
                        envp: envStrings,
                        flatVFS: vfsPlan.flatVFS,
                        hostMounts: vfsPlan.hostMounts,
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
        let guestWorkingDir = normalizeGuestWorkingDir(workingDir)
        let wrappedCommand: String
        if guestWorkingDir == "/" {
            wrappedCommand = command
        } else {
            wrappedCommand = "cd \(shellQuote(guestWorkingDir)) && \(command)"
        }
        return try await execute(
            binaryPath: "/bin/sh",
            args: ["-c", wrappedCommand],
            env: env,
            workingDir: workingDir,
            namespace: namespace,
            timeoutMs: timeoutMs
        )
    }

    public func startInteractiveShell(
        command: String? = nil,
        env: [String: String],
        workingDir: String,
        namespace: VFSNamespace,
        size: TerminalSize
    ) async throws -> any InteractiveExecutionSession {
        let vfsPlan = BlinkVFSPlanner.buildLaunchPlan(namespace: namespace)
        let guestWorkingDir = normalizeGuestWorkingDir(workingDir)
        let guestBinaryPath = "/bin/sh"
        let argv: [String]
        if let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let wrappedCommand: String
            if guestWorkingDir == "/" {
                wrappedCommand = command
            } else {
                wrappedCommand = "cd \(shellQuote(guestWorkingDir)) && \(command)"
            }
            argv = [guestBinaryPath, "-c", wrappedCommand]
        } else {
            argv = [guestBinaryPath]
        }

        var mergedEnv = env
        mergedEnv["HOME", default: "/tmp/iagentsmith-home"] = "/tmp/iagentsmith-home"
        mergedEnv["USER", default: "codex"] = "codex"
        let defaultUser = mergedEnv["USER", default: "codex"]
        mergedEnv["LOGNAME", default: defaultUser] = defaultUser
        mergedEnv["SHELL", default: "/bin/sh"] = "/bin/sh"
        mergedEnv["TMPDIR", default: "/tmp"] = "/tmp"
        mergedEnv["TERM", default: "xterm-256color"] = "xterm-256color"
        mergedEnv["PATH", default: "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        mergedEnv["PWD"] = guestWorkingDir
        var envStringsMut: [String] = mergedEnv.map { "\($0.key)=\($0.value)" }
        if !networkEnabled {
            envStringsMut.append("BLINK_DISABLE_NETWORKING=1")
        }
        let envStrings = BlinkGuestNodeRuntime.mergedEnvironmentStrings(envStringsMut)

        return try Self.startBlinkPTYMemVFS(
            programPath: guestBinaryPath,
            argv: argv,
            envp: envStrings,
            flatVFS: vfsPlan.flatVFS,
            hostMounts: vfsPlan.hostMounts,
            size: size
        )
    }

    // MARK: - Private

    private struct BlinkExecResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        let timedOut: Bool
    }

    private func normalizeGuestWorkingDir(_ workingDir: String) -> String {
        guard !workingDir.isEmpty else {
            return "/"
        }
        return workingDir.hasPrefix("/") ? workingDir : "/\(workingDir)"
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// Build a C flatvfs_t from a FlatVFS and call blink_run_captured_memvfs.
    private static func runBlinkMemVFS(
        programPath: String,
        argv: [String],
        envp: [String],
        flatVFS: FlatVFS,
        hostMounts: [BlinkHostMount],
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

        let cHostMounts = buildCHostMounts(hostMounts)
        defer { freeCHostMounts(cHostMounts.mounts, count: cHostMounts.count) }

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
        config.host_mounts = cHostMounts.mounts.map { UnsafePointer($0) }
        config.host_mount_count = Int32(cHostMounts.count)

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

    private static func startBlinkPTYMemVFS(
        programPath: String,
        argv: [String],
        envp: [String],
        flatVFS: FlatVFS,
        hostMounts: [BlinkHostMount],
        size: TerminalSize
    ) throws -> BlinkInteractiveExecutionSession {
        let cProgramPath = programPath.withCString { strdup($0)! }
        defer { free(cProgramPath) }

        var cArgv: [UnsafePointer<CChar>?] = argv.map { UnsafePointer(strdup($0)) }
        cArgv.append(nil)
        defer {
            for pointer in cArgv where pointer != nil {
                free(UnsafeMutablePointer(mutating: pointer!))
            }
        }

        var cEnvp: [UnsafePointer<CChar>?] = envp.map { UnsafePointer(strdup($0)) }
        cEnvp.append(nil)
        defer {
            for pointer in cEnvp where pointer != nil {
                free(UnsafeMutablePointer(mutating: pointer!))
            }
        }

        let cHostMounts = buildCHostMounts(hostMounts)
        defer { freeCHostMounts(cHostMounts.mounts, count: cHostMounts.count) }

        let cEntries = buildCFlatVFS(flatVFS)
        defer { freeCFlatVFS(cEntries.entries, count: cEntries.count) }

        var config = blink_run_config_t()
        config.program_path = UnsafePointer(cProgramPath)
        config.argv = cArgv.withUnsafeBufferPointer { buffer in
            UnsafePointer(buffer.baseAddress!.withMemoryRebound(
                to: UnsafePointer<CChar>?.self,
                capacity: buffer.count
            ) { $0 })
        }
        config.argc = Int32(argv.count)
        config.envp = cEnvp.withUnsafeBufferPointer { buffer in
            UnsafePointer(buffer.baseAddress!.withMemoryRebound(
                to: UnsafePointer<CChar>?.self,
                capacity: buffer.count
            ) { $0 })
        }
        config.envc = Int32(envp.count)
        config.vfs_prefix = nil
        config.host_mounts = cHostMounts.mounts.map { UnsafePointer($0) }
        config.host_mount_count = Int32(cHostMounts.count)

        var flatvfs = flatvfs_t()
        flatvfs.entries = UnsafePointer(cEntries.entries)
        flatvfs.entry_count = Int32(cEntries.count)

        var masterFD: Int32 = -1
        var sessionPointer: UnsafeMutablePointer<blink_pty_session_t>?
        let rc = blink_pty_session_start_memvfs(
            &config,
            &flatvfs,
            Int32(size.rows),
            Int32(size.columns),
            &sessionPointer,
            &masterFD
        )
        guard rc == 0, let sessionPointer, masterFD >= 0 else {
            throw ContainerError.executionFailed(
                "blink_pty_session_start_memvfs failed: \(String(cString: strerror(errno)))"
            )
        }

        return BlinkInteractiveExecutionSession(
            sessionPointer: sessionPointer,
            masterFD: masterFD
        )
    }

    // MARK: - C FlatVFS conversion

    private struct CFlatVFSResult {
        let entries: UnsafeMutablePointer<flatvfs_entry_t>
        let count: Int
    }

    private struct CHostMountsResult {
        let mounts: UnsafeMutablePointer<blink_host_mount_t>?
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

    private static func buildCHostMounts(_ hostMounts: [BlinkHostMount]) -> CHostMountsResult {
        guard !hostMounts.isEmpty else {
            return CHostMountsResult(mounts: nil, count: 0)
        }

        let mounts = UnsafeMutablePointer<blink_host_mount_t>.allocate(capacity: hostMounts.count)
        for (index, hostMount) in hostMounts.enumerated() {
            var cMount = blink_host_mount_t()
            cMount.host_path = UnsafePointer(strdup(hostMount.hostPath))
            cMount.guest_path = UnsafePointer(strdup(hostMount.guestPath))
            mounts[index] = cMount
        }
        return CHostMountsResult(mounts: mounts, count: hostMounts.count)
    }

    private static func freeCHostMounts(
        _ mounts: UnsafeMutablePointer<blink_host_mount_t>?,
        count: Int
    ) {
        guard let mounts else {
            return
        }

        for index in 0..<count {
            let mount = mounts[index]
            free(UnsafeMutablePointer(mutating: mount.host_path))
            free(UnsafeMutablePointer(mutating: mount.guest_path))
        }
        mounts.deallocate()
    }
}

private final class BlinkInteractiveExecutionSession: InteractiveExecutionSession, @unchecked Sendable {
    private let lock = NSLock()
    private var sessionPointer: UnsafeMutablePointer<blink_pty_session_t>?
    private var masterFD: Int32
    private var eventHandler: (@Sendable (InteractiveSessionEvent) -> Void)?
    private var pendingEvents: [InteractiveSessionEvent] = []
    private var running = true

    init(sessionPointer: UnsafeMutablePointer<blink_pty_session_t>, masterFD: Int32) {
        self.sessionPointer = sessionPointer
        self.masterFD = masterFD
        startReadLoop()
        startWaitLoop()
    }

    deinit {
        closeMasterFDIfNeeded()
    }

    func setEventHandler(_ handler: (@Sendable (InteractiveSessionEvent) -> Void)?) async {
        let bufferedEvents = withLock { () -> [InteractiveSessionEvent] in
            eventHandler = handler
            let buffered = pendingEvents
            pendingEvents.removeAll(keepingCapacity: false)
            return buffered
        }

        guard let handler else {
            return
        }
        bufferedEvents.forEach(handler)
    }

    func write(_ data: Data) async throws {
        let fd = withLockedMasterFD()
        guard fd >= 0 else {
            throw InteractiveSessionUnsupportedError()
        }
        try Self.writeAll(data: data, to: fd)
    }

    func resize(_ size: TerminalSize) async throws {
        if let pointer = withLockedSessionPointer() {
            if blink_pty_session_resize(pointer, Int32(size.rows), Int32(size.columns)) != 0 {
                throw ContainerError.executionFailed(
                    "Failed to resize PTY session: \(String(cString: strerror(errno)))"
                )
            }
        }
        let fd = withLockedMasterFD()
        guard fd >= 0 else {
            throw InteractiveSessionUnsupportedError()
        }
        var windowSize = winsize(
            ws_row: UInt16(max(size.rows, 1)),
            ws_col: UInt16(max(size.columns, 1)),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        if ioctl(fd, TIOCSWINSZ, &windowSize) == -1 && errno != ENOTTY {
            throw ContainerError.executionFailed(
                "Failed to resize PTY: \(String(cString: strerror(errno)))"
            )
        }
    }

    func terminate() async {
        if let pointer = withLockedSessionPointer() {
            _ = blink_pty_session_terminate(pointer)
        }
    }

    func isRunning() async -> Bool {
        withLock { running }
    }

    private func startReadLoop() {
        let queue = DispatchQueue(label: "omnikit.blink.pty.read.\(UUID().uuidString)")
        queue.async { [self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let fd = withLockedMasterFD()
                guard fd >= 0 else { break }
                let count = read(fd, &buffer, buffer.count)
                if count > 0 {
                    emit(.output(Data(buffer.prefix(Int(count)))))
                    continue
                }
                if count == 0 {
                    break
                }
                if errno == EINTR {
                    continue
                }
                if errno == EIO || errno == EBADF {
                    break
                }
                break
            }
        }
    }

    private func startWaitLoop() {
        let queue = DispatchQueue(label: "omnikit.blink.pty.wait.\(UUID().uuidString)")
        queue.async { [self] in
            let pointer = withLockedSessionPointer()
            guard let pointer else { return }

            var exitCode: Int32 = -1
            let rc = blink_pty_session_wait(pointer, &exitCode)
            if rc != 0 {
                exitCode = -1
            }

            markExited(with: exitCode)
            let consumedPointer = consumeSessionPointer()
            closeMasterFDIfNeeded()
            if let consumedPointer {
                blink_pty_session_destroy(consumedPointer)
            }
        }
    }

    private func emit(_ event: InteractiveSessionEvent) {
        let handler = withLock { () -> (@Sendable (InteractiveSessionEvent) -> Void)? in
            let currentHandler = eventHandler
            if currentHandler == nil {
                pendingEvents.append(event)
            }
            return currentHandler
        }

        handler?(event)
    }

    private func markExited(with exitCode: Int32) {
        withLock {
            running = false
        }
        emit(.exit(exitCode))
    }

    private func withLockedSessionPointer() -> UnsafeMutablePointer<blink_pty_session_t>? {
        lock.lock()
        let pointer = sessionPointer
        lock.unlock()
        return pointer
    }

    private func consumeSessionPointer() -> UnsafeMutablePointer<blink_pty_session_t>? {
        lock.lock()
        let pointer = sessionPointer
        sessionPointer = nil
        lock.unlock()
        return pointer
    }

    private func withLockedMasterFD() -> Int32 {
        lock.lock()
        let fd = masterFD
        lock.unlock()
        return fd
    }

    private func closeMasterFDIfNeeded() {
        let fd = withLock { () -> Int32 in
            let currentFD = masterFD
            masterFD = -1
            return currentFD
        }
        if fd >= 0 {
            _ = close(fd)
        }
    }

    private static func writeAll(data: Data, to fd: Int32) throws {
        var remaining = data[...]
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { rawBuffer in
                platformWrite(fd, rawBuffer.baseAddress, rawBuffer.count)
            }
            if written > 0 {
                remaining = remaining.dropFirst(Int(written))
                continue
            }
            if written == -1 && errno == EINTR {
                continue
            }
            throw ContainerError.executionFailed(
                "Failed to write to PTY: \(String(cString: strerror(errno)))"
            )
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private func platformWrite(_ fd: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int {
    #if canImport(Darwin)
    return Darwin.write(fd, buffer, count)
    #else
    return Glibc.write(fd, buffer, count)
    #endif
}
