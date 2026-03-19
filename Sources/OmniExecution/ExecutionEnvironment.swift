import Foundation

public protocol ExecutionEnvironment: Sendable {
    func readFile(path: String, offset: Int?, limit: Int?) async throws -> String
    func writeFile(path: String, content: String) async throws
    func fileExists(path: String) async -> Bool
    func listDirectory(path: String, depth: Int) async throws -> [DirEntry]
    func execCommand(command: String, timeoutMs: Int, workingDir: String?, envVars: [String: String]?) async throws -> ExecResult
    func grep(pattern: String, path: String, options: GrepOptions) async throws -> String
    func glob(pattern: String, path: String) async throws -> [String]
    func initialize() async throws
    func cleanup() async throws
    func workingDirectory() -> String
    func platform() -> String
    func osVersion() -> String
}
