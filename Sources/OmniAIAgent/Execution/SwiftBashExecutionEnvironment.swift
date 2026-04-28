import BashCommandKit
import BashInterpreter
import Foundation
import OmniExecution

public protocol CommandConsoleSession: Sendable {
    /// Run one command to completion. This is command-at-a-time execution, not a PTY.
    func run(_ command: String, timeoutMs: Int) async throws -> ExecResult
    func workingDirectory() async -> String
    func reset() async
}

public final class SwiftBashExecutionEnvironment: ExecutionEnvironment, @unchecked Sendable {
    private let local: LocalExecutionEnvironment
    private let workingDir: String
    private let config: SwiftBashBackendConfig
    private let shellLock = NSLock()
    private var persistentShell: Shell?
    private var persistentWorkingDirectory: String?

    public init(
        workingDir: String? = nil,
        config: SwiftBashBackendConfig = SwiftBashBackendConfig()
    ) {
        self.workingDir = workingDir ?? FileManager.default.currentDirectoryPath
        self.config = config
        self.local = LocalExecutionEnvironment(workingDir: self.workingDir)
    }

    public func readFile(path: String, offset: Int?, limit: Int?) async throws -> String {
        try await local.readFile(path: path, offset: offset, limit: limit)
    }

    public func writeFile(path: String, content: String) async throws {
        try await local.writeFile(path: path, content: content)
    }

    public func fileExists(path: String) async -> Bool {
        await local.fileExists(path: path)
    }

    public func listDirectory(path: String, depth: Int) async throws -> [DirEntry] {
        try await local.listDirectory(path: path, depth: depth)
    }

    public func execCommand(
        command: String,
        timeoutMs: Int,
        workingDir: String?,
        envVars: [String: String]?
    ) async throws -> ExecResult {
        let resolvedWorkingDir = resolvePath(workingDir ?? self.workingDir)
        let shell: Shell
        if config.persistentSession {
            shell = shellLock.withLock {
                if let persistentShell {
                    return persistentShell
                }
                let shell = makeShell(workingDirectory: resolvedWorkingDir, envVars: envVars)
                persistentShell = shell
                persistentWorkingDirectory = resolvedWorkingDir
                return shell
            }
        } else {
            shell = makeShell(workingDirectory: resolvedWorkingDir, envVars: envVars)
        }

        let result = try await Self.runCommand(command, timeoutMs: timeoutMs, shell: shell)
        if config.persistentSession {
            shellLock.withLock {
                if result.timedOut {
                    persistentShell = nil
                    persistentWorkingDirectory = nil
                } else {
                    persistentWorkingDirectory = shell.environment.workingDirectory
                }
            }
        }
        return result
    }

    public func startCommandConsole(
        workingDir: String?,
        envVars: [String: String]?
    ) async throws -> any CommandConsoleSession {
        let resolvedWorkingDir = resolvePath(workingDir ?? self.workingDir)
        let shell = makeShell(workingDirectory: resolvedWorkingDir, envVars: envVars)
        return SwiftBashCommandConsoleSession(
            initialWorkingDirectory: resolvedWorkingDir,
            shell: shell,
            makeShell: { [config, baseWorkingDir = self.workingDir] workingDirectory, envVars in
                SwiftBashExecutionEnvironment.makeShell(
                    workingDirectory: workingDirectory,
                    envVars: envVars,
                    baseWorkingDir: baseWorkingDir,
                    config: config
                )
            },
            envVars: envVars
        )
    }

    fileprivate static func runCommand(
        _ command: String,
        timeoutMs: Int,
        shell: Shell
    ) async throws -> ExecResult {
        let startTime = Date()
        let runTask = Task {
            try await shell.runCapturing(command)
        }
        let outcome = try await withCheckedThrowingContinuation { continuation in
            let box = SwiftBashCommandContinuationBox(continuation)
            Task {
                do {
                    let captured = try await runTask.value
                    box.resume(.success(.completed(captured)))
                } catch is CancellationError {
                    box.resume(.success(.timedOut))
                } catch {
                    box.resume(.failure(error))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                runTask.cancel()
                box.resume(.success(.timedOut))
            }
        }

        switch outcome {
        case .completed(let captured):
            return ExecResult(
                stdout: captured.stdout,
                stderr: captured.stderr,
                exitCode: captured.exitStatus.code,
                timedOut: false,
                durationMs: durationMs(since: startTime)
            )
        case .timedOut:
            return ExecResult(
                stdout: "",
                stderr: "",
                exitCode: 124,
                timedOut: true,
                durationMs: durationMs(since: startTime)
            )
        }
    }

    public func grep(pattern: String, path: String, options: GrepOptions) async throws -> String {
        try await local.grep(pattern: pattern, path: path, options: options)
    }

    public func glob(pattern: String, path: String) async throws -> [String] {
        try await local.glob(pattern: pattern, path: path)
    }

    public func initialize() async throws {
        try await local.initialize()
    }

    public func cleanup() async throws {
        try await local.cleanup()
    }

    public func workingDirectory() -> String {
        if config.persistentSession,
           let persistentWorkingDirectory = shellLock.withLock({ persistentWorkingDirectory }) {
            return persistentWorkingDirectory
        }
        return workingDir
    }

    public func platform() -> String {
        local.platform()
    }

    public func osVersion() -> String {
        local.osVersion()
    }

    private func makeShell(workingDirectory: String, envVars: [String: String]?) -> Shell {
        Self.makeShell(
            workingDirectory: workingDirectory,
            envVars: envVars,
            baseWorkingDir: workingDir,
            config: config
        )
    }

    private static func makeShell(
        workingDirectory: String,
        envVars: [String: String]?,
        baseWorkingDir: String,
        config: SwiftBashBackendConfig
    ) -> Shell {
        var environment = config.useHostEnvironment
            ? Environment.current()
            : Environment.synthetic(workingDirectory: workingDirectory)
        environment.workingDirectory = workingDirectory
        environment["PWD"] = workingDirectory
        if let envVars {
            for (key, value) in envVars {
                environment[key] = value
            }
        }

        let shell = Shell(
            environment: environment,
            fileSystem: makeFileSystem(
                workingDirectory: workingDirectory,
                baseWorkingDir: baseWorkingDir,
                config: config
            )
        )
        shell.hostInfo = config.useHostEnvironment ? .real() : .synthetic
        shell.registerStandardCommands()
        shell.networkConfig = networkConfig(config: config)
        return shell
    }

    private static func makeFileSystem(
        workingDirectory: String,
        baseWorkingDir: String,
        config: SwiftBashBackendConfig
    ) -> any FileSystem {
        switch config.fileSystemMode {
        case .realFileSystem:
            return RealFileSystem()
        case .sandboxedWorkspace:
            do {
                return try SandboxedOverlayFileSystem(.init(
                    root: baseWorkingDir,
                    mountPoint: workingDirectory
                ))
            } catch {
                return InMemoryFileSystem()
            }
        case .inMemory:
            return InMemoryFileSystem()
        }
    }

    private static func networkConfig(config: SwiftBashBackendConfig) -> NetworkConfig? {
        guard config.networkEnabled else { return nil }
        if config.allowFullInternetAccess {
            return NetworkConfig(dangerouslyAllowFullInternetAccess: true)
        }
        return NetworkConfig(
            allowedURLPrefixes: config.allowedURLPrefixes.map(AllowedURLEntry.init)
        )
    }

    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return (workingDir as NSString).appendingPathComponent(path)
    }

    fileprivate static func durationMs(since startTime: Date) -> Int {
        Int(Date().timeIntervalSince(startTime) * 1000)
    }
}

private actor SwiftBashCommandConsoleSession: CommandConsoleSession {
    private let initialWorkingDirectory: String
    private let makeShell: @Sendable (String, [String: String]?) -> Shell
    private let envVars: [String: String]?
    private var shell: Shell

    init(
        initialWorkingDirectory: String,
        shell: Shell,
        makeShell: @Sendable @escaping (String, [String: String]?) -> Shell,
        envVars: [String: String]?
    ) {
        self.initialWorkingDirectory = initialWorkingDirectory
        self.shell = shell
        self.makeShell = makeShell
        self.envVars = envVars
    }

    func run(_ command: String, timeoutMs: Int) async throws -> ExecResult {
        try await SwiftBashExecutionEnvironment.runCommand(command, timeoutMs: timeoutMs, shell: shell)
    }

    func workingDirectory() async -> String {
        shell.environment.workingDirectory
    }

    func reset() async {
        shell = makeShell(initialWorkingDirectory, envVars)
    }
}

private enum SwiftBashCommandOutcome {
    case completed(CapturedRun)
    case timedOut
}

private final class SwiftBashCommandContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<SwiftBashCommandOutcome, Error>

    init(_ continuation: CheckedContinuation<SwiftBashCommandOutcome, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<SwiftBashCommandOutcome, Error>) {
        let shouldResume = lock.withLock {
            if didResume {
                return false
            }
            didResume = true
            return true
        }
        guard shouldResume else { return }

        switch result {
        case .success(let outcome):
            continuation.resume(returning: outcome)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
