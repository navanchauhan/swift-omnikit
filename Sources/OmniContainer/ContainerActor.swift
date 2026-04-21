import Foundation
import OmniVFS
import OmniExecution

/// Core container actor. Manages lifecycle, namespace assembly, and VFS operations.
public actor ContainerActor {
    public let id: ContainerID
    public private(set) var state: ContainerState = .created
    private var namespace: VFSNamespace
    public let config: ContainerSpec
    private let overlay: MemFS
    private let blinkRuntime: BlinkRuntime
    private let wasmEngine: WasmEngine

    public init(id: ContainerID = ContainerID(), config: ContainerSpec, rootFS: any VFS) {
        self.id = id
        self.config = config
        self.overlay = MemFS(maxBytes: config.memoryLimitMB * 1024 * 1024)
        self.namespace = VFSNamespace()

        // Bind root: CowFS(base: rootFS, overlay: overlay)
        let cow = CowFS(base: rootFS, overlay: self.overlay)
        self.namespace.bind(src: cow, srcPath: ".", dstPath: ".", mode: .replace)

        // Bind /tmp as MemFS
        let tmpFS = MemFS()
        self.namespace.bind(src: tmpFS, srcPath: ".", dstPath: "tmp", mode: .replace)

        // Initialize execution engines
        var networkEnabled = false
        for cap in config.capabilities {
            if case .network = cap { networkEnabled = true }
        }
        self.blinkRuntime = BlinkRuntime(networkEnabled: networkEnabled)
        self.wasmEngine = WasmEngine()

        if networkEnabled {
            let hostResolv = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8)
            let guestResolv = BlinkGuestNetworking.resolvConf(hostContents: hostResolv)
            try? self.overlay.mkdir("etc")
            try? self.overlay.writeFile("etc/resolv.conf", data: Array(guestResolv.utf8))
        }

        // Install capabilities
        for cap in config.capabilities {
            switch cap {
            case .workspace(let hostPath):
                let diskFS = DiskFS(root: hostPath)
                self.namespace.bind(src: diskFS, srcPath: ".", dstPath: "workspace", mode: .replace)
            case .persistentVolume(let name, let hostPath):
                let diskFS = DiskFS(root: hostPath)
                self.namespace.bind(src: diskFS, srcPath: ".", dstPath: "mnt/\(name)", mode: .replace)
            case .tmpfs, .network, .debugMount:
                break // tmpfs already provided; network and debugMount handled at exec time
            }
        }
    }

    /// Transition to running state.
    public func start() throws {
        guard state == .created else {
            throw ContainerError.invalidStateTransition(from: state, to: .running)
        }
        state = .running
    }

    /// Stop the container.
    public func stop() {
        guard case .running = state else { return }
        state = .stopped(exitCode: 0)
    }

    /// Destroy the container, releasing resources.
    public func destroy() {
        state = .destroyed
    }

    /// Return a copy of the namespace (value type).
    public func cloneNamespace() -> VFSNamespace {
        namespace
    }

    // MARK: - VFS Operations (delegated from ContainerExecutionEnvironment)

    public func readFile(path: String) throws -> String {
        let (fs, resolved) = try namespace.resolveFS(path)
        let file = try fs.open(resolved)
        defer { try? file.close() }
        let data = try file.readAll()
        return String(decoding: data, as: UTF8.self)
    }

    public func writeFile(path: String, content: String) throws {
        let data = Array(content.utf8)
        let (fs, resolved) = try namespace.resolveFS(path)
        guard let mutableFS = fs as? any VFSMutableFS else {
            throw VFSError.notSupported("Filesystem at \(path) is not writable")
        }
        // Try writeFile, fall back to createFile
        do {
            try mutableFS.writeFile(resolved, data: data)
        } catch VFSError.notFound {
            try mutableFS.createFile(resolved, data: data)
        }
    }

    public func fileExists(path: String) -> Bool {
        do {
            let (fs, resolved) = try namespace.resolveFS(path)
            if let statFS = fs as? any VFSStatFS {
                _ = try statFS.stat(resolved)
                return true
            }
            let file = try fs.open(resolved)
            try? file.close()
            return true
        } catch {
            return false
        }
    }

    public func listDirectory(path: String, depth: Int) throws -> [DirEntry] {
        let (fs, resolved) = try namespace.resolveFS(path)
        guard let rdFS = fs as? any VFSReadDirFS else {
            throw VFSError.notSupported("readDir not supported")
        }
        let entries = try rdFS.readDir(resolved)
        return entries.map { DirEntry(name: $0.name, isDir: $0.isDir, size: $0.size.map { Int($0) }) }
    }

    // MARK: - Execution

    /// Execute a command inside the container using the appropriate engine.
    public func exec(
        command: String,
        args: [String] = [],
        env: [String: String]? = nil,
        workingDir: String? = nil,
        timeoutMs: Int = 30000
    ) async throws -> ExecResult {
        guard case .running = state else { throw ContainerError.notRunning }

        // Build merged environment
        let mergedEnv = (env ?? [:]).merging(config.env) { new, _ in new }
        let resolvedWorkDir = workingDir ?? config.workingDir

        // Clone namespace for this exec session
        let session = ExecSession(
            namespace: namespace,
            env: mergedEnv,
            workingDir: resolvedWorkDir
        )

        if let wasmInvocation = directWasmInvocation(
            command: command,
            args: args,
            workingDir: session.workingDir,
            namespace: session.namespace
        ) {
            return try await wasmEngine.execute(
                binaryPath: wasmInvocation.binaryPath,
                args: wasmInvocation.args,
                env: session.env,
                workingDir: session.workingDir,
                namespace: session.namespace,
                timeoutMs: timeoutMs
            )
        }

        // Shell commands go through Blink's /bin/sh.
        return try await blinkRuntime.executeShell(
            command: ([command] + args).joined(separator: " "),
            env: session.env,
            workingDir: session.workingDir,
            namespace: session.namespace,
            timeoutMs: timeoutMs
        )
    }

    public func startInteractiveShell(
        command: String? = nil,
        env: [String: String]? = nil,
        workingDir: String? = nil,
        size: TerminalSize
    ) async throws -> any InteractiveExecutionSession {
        guard case .running = state else { throw ContainerError.notRunning }

        let mergedEnv = (env ?? [:]).merging(config.env) { new, _ in new }
        let resolvedWorkDir = workingDir ?? config.workingDir
        let session = ExecSession(
            namespace: namespace,
            env: mergedEnv,
            workingDir: resolvedWorkDir
        )

        return try await blinkRuntime.startInteractiveShell(
            command: command,
            env: session.env,
            workingDir: session.workingDir,
            namespace: session.namespace,
            size: size
        )
    }

    private struct DirectExecutionInvocation: Sendable {
        let binaryPath: String
        let args: [String]
    }

    private func directWasmInvocation(
        command: String,
        args: [String],
        workingDir: String,
        namespace: VFSNamespace
    ) -> DirectExecutionInvocation? {
        let argv: [String]
        if args.isEmpty {
            guard let parsed = tokenizeDirectInvocation(command) else {
                return nil
            }
            argv = parsed
        } else {
            guard let parsedCommand = tokenizeDirectInvocation(command), parsedCommand.count == 1 else {
                return nil
            }
            argv = parsedCommand + args
        }

        guard let executable = argv.first else {
            return nil
        }

        let binaryPath = resolveGuestExecutablePath(executable, relativeTo: workingDir)
        guard probeBinaryHeader(at: binaryPath, namespace: namespace).map(wasmEngine.canExecute) == true else {
            return nil
        }

        return DirectExecutionInvocation(
            binaryPath: binaryPath,
            args: Array(argv.dropFirst())
        )
    }

    private func tokenizeDirectInvocation(_ command: String) -> [String]? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        var tokens: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaping = false

        for scalar in trimmed.unicodeScalars {
            if escaping {
                current.unicodeScalars.append(scalar)
                escaping = false
                continue
            }

            switch scalar {
            case "\\":
                if inSingleQuote {
                    current.unicodeScalars.append(scalar)
                } else {
                    escaping = true
                }
            case "'":
                if inDoubleQuote {
                    current.unicodeScalars.append(scalar)
                } else {
                    inSingleQuote.toggle()
                }
            case "\"":
                if inSingleQuote {
                    current.unicodeScalars.append(scalar)
                } else {
                    inDoubleQuote.toggle()
                }
            case " ", "\t", "\n", "\r":
                if inSingleQuote || inDoubleQuote {
                    current.unicodeScalars.append(scalar)
                } else if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            case "|", "&", ";", "<", ">", "(", ")", "{", "}", "[", "]", "$", "`", "*", "?", "~":
                if inSingleQuote || inDoubleQuote {
                    current.unicodeScalars.append(scalar)
                } else {
                    return nil
                }
            default:
                current.unicodeScalars.append(scalar)
            }
        }

        guard !escaping, !inSingleQuote, !inDoubleQuote else {
            return nil
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens.isEmpty ? nil : tokens
    }

    private func resolveGuestExecutablePath(_ executable: String, relativeTo workingDir: String) -> String {
        let normalizedWorkingDir = PathUtils.resolvePath(workingDir, relativeTo: "/")
        let resolvedPath = PathUtils.resolvePath(executable, relativeTo: normalizedWorkingDir)
        return resolvedPath == "." ? "/" : resolvedPath
    }

    private func probeBinaryHeader(at binaryPath: String, namespace: VFSNamespace, maxBytes: Int = 8) -> [UInt8]? {
        let namespacePath = PathUtils.stripLeadingSlash(binaryPath)
        guard let (fs, resolvedPath) = try? namespace.resolveFS(namespacePath) else {
            return nil
        }

        guard let file = try? fs.open(resolvedPath) else {
            return nil
        }
        defer { try? file.close() }

        var buffer = Array(repeating: UInt8(0), count: maxBytes)
        guard let bytesRead = try? file.read(into: &buffer, count: maxBytes), bytesRead > 0 else {
            return nil
        }
        return Array(buffer.prefix(bytesRead))
    }
}
