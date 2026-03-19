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

        // Shell commands go through blink's /bin/sh
        return try await blinkRuntime.executeShell(
            command: ([command] + args).joined(separator: " "),
            env: session.env,
            workingDir: session.workingDir,
            namespace: session.namespace,
            timeoutMs: timeoutMs
        )
    }
}
