import BashCommandKit
import BashInterpreter
import Foundation
import OmniExecution

public final class SwiftBashExecutionEnvironment: ExecutionEnvironment, @unchecked Sendable {
    private let local: LocalExecutionEnvironment
    private let workingDir: String
    private let config: SwiftBashBackendConfig

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
        let startTime = Date()
        let shell = makeShell(workingDirectory: resolvedWorkingDir, envVars: envVars)

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
        workingDir
    }

    public func platform() -> String {
        local.platform()
    }

    public func osVersion() -> String {
        local.osVersion()
    }

    private func makeShell(workingDirectory: String, envVars: [String: String]?) -> Shell {
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

        let shell = Shell(environment: environment, fileSystem: makeFileSystem(workingDirectory: workingDirectory))
        shell.hostInfo = config.useHostEnvironment ? .real() : .synthetic
        shell.registerStandardCommands()
        shell.networkConfig = networkConfig()
        return shell
    }

    private func makeFileSystem(workingDirectory: String) -> any FileSystem {
        switch config.fileSystemMode {
        case .realFileSystem:
            return RealFileSystem()
        case .sandboxedWorkspace:
            do {
                return try SandboxedOverlayFileSystem(.init(
                    root: self.workingDir,
                    mountPoint: workingDirectory
                ))
            } catch {
                return InMemoryFileSystem()
            }
        case .inMemory:
            return InMemoryFileSystem()
        }
    }

    private func networkConfig() -> NetworkConfig? {
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

    private func durationMs(since startTime: Date) -> Int {
        Int(Date().timeIntervalSince(startTime) * 1000)
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
