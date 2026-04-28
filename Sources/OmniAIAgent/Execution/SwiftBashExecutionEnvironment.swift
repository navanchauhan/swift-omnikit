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

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
            runTask.cancel()
        }

        do {
            let captured = try await runTask.value
            timeoutTask.cancel()
            return ExecResult(
                stdout: captured.stdout,
                stderr: captured.stderr,
                exitCode: captured.exitStatus.code,
                timedOut: false,
                durationMs: durationMs(since: startTime)
            )
        } catch is CancellationError {
            timeoutTask.cancel()
            return ExecResult(
                stdout: "",
                stderr: "",
                exitCode: 124,
                timedOut: true,
                durationMs: durationMs(since: startTime)
            )
        } catch {
            timeoutTask.cancel()
            throw error
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

        let shell = Shell(environment: environment, fileSystem: RealFileSystem())
        shell.hostInfo = config.useHostEnvironment ? .real() : .synthetic
        shell.registerStandardCommands()
        shell.networkConfig = networkConfig()
        return shell
    }

    private func networkConfig() -> NetworkConfig? {
        guard config.networkEnabled else { return nil }
        if config.allowedURLPrefixes.isEmpty {
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
