import Foundation
import OmniVFS
import OmniExecution

/// Implements ExecutionEnvironment by delegating to a ContainerActor.
public final class ContainerExecutionEnvironment: ExecutionEnvironment, @unchecked Sendable {
    private let container: ContainerActor
    private let hostWorkspaceDir: String
    private let guestWorkspaceDir: String
    private let hostPlatform: String

    public init(container: ContainerActor, hostWorkspaceDir: String, guestWorkspaceDir: String = "/workspace") {
        self.container = container
        self.hostWorkspaceDir = hostWorkspaceDir
        self.guestWorkspaceDir = guestWorkspaceDir
        #if os(macOS)
        self.hostPlatform = "Darwin"
        #elseif os(Linux)
        self.hostPlatform = "Linux"
        #else
        self.hostPlatform = "Unknown"
        #endif
    }

    public func readFile(path: String, offset: Int?, limit: Int?) async throws -> String {
        let guestPath = translatePath(path)
        var content = try await container.readFile(path: guestPath)
        if let offset = offset, offset > 0 {
            let lines = content.components(separatedBy: "\n")
            let sliced = lines.dropFirst(offset)
            if let limit = limit {
                content = sliced.prefix(limit).joined(separator: "\n")
            } else {
                content = sliced.joined(separator: "\n")
            }
        } else if let limit = limit {
            let lines = content.components(separatedBy: "\n")
            content = lines.prefix(limit).joined(separator: "\n")
        }
        return content
    }

    public func writeFile(path: String, content: String) async throws {
        let guestPath = translatePath(path)
        try await container.writeFile(path: guestPath, content: content)
    }

    public func fileExists(path: String) async -> Bool {
        let guestPath = translatePath(path)
        return await container.fileExists(path: guestPath)
    }

    public func listDirectory(path: String, depth: Int) async throws -> [DirEntry] {
        let guestPath = translatePath(path)
        return try await container.listDirectory(path: guestPath, depth: depth)
    }

    public func execCommand(command: String, timeoutMs: Int, workingDir: String?, envVars: [String: String]?) async throws -> ExecResult {
        let guestWorkDir = workingDir.map { translatePath($0) } ?? guestWorkspaceDir
        return try await container.exec(
            command: command,
            env: envVars,
            workingDir: guestWorkDir,
            timeoutMs: timeoutMs
        )
    }

    public func grep(pattern: String, path: String, options: GrepOptions) async throws -> String {
        let guestPath = translatePath(path)
        var results: [String] = []
        try await grepRecursive(pattern: pattern, path: guestPath, options: options, results: &results)
        return results.prefix(options.maxResults).joined(separator: "\n")
    }

    private func grepRecursive(pattern: String, path: String, options: GrepOptions, results: inout [String]) async throws {
        let entries = try await container.listDirectory(path: path, depth: 1)
        for entry in entries {
            let entryPath = path == "." ? entry.name : "\(path)/\(entry.name)"
            if entry.isDir {
                try await grepRecursive(pattern: pattern, path: entryPath, options: options, results: &results)
            } else {
                if let globFilter = options.globFilter {
                    guard PathUtils.matchGlob(pattern: globFilter, path: entry.name) else { continue }
                }
                do {
                    let content = try await container.readFile(path: entryPath)
                    let lines = content.components(separatedBy: "\n")
                    for (i, line) in lines.enumerated() {
                        let searchLine = options.caseInsensitive ? line.lowercased() : line
                        let searchPattern = options.caseInsensitive ? pattern.lowercased() : pattern
                        if searchLine.contains(searchPattern) {
                            results.append("\(entryPath):\(i + 1):\(line)")
                            if results.count >= options.maxResults { return }
                        }
                    }
                } catch {
                    continue // skip unreadable files
                }
            }
        }
    }

    public func glob(pattern: String, path: String) async throws -> [String] {
        let guestPath = translatePath(path)
        var matches: [String] = []
        try await globRecursive(pattern: pattern, basePath: guestPath, currentPath: guestPath, matches: &matches)
        return matches
    }

    private func globRecursive(pattern: String, basePath: String, currentPath: String, matches: inout [String]) async throws {
        let entries = try await container.listDirectory(path: currentPath, depth: 1)
        for entry in entries {
            let entryPath = currentPath == "." ? entry.name : "\(currentPath)/\(entry.name)"
            let relativePath = basePath == "." ? entryPath : String(entryPath.dropFirst(basePath.count + 1))
            if PathUtils.matchGlob(pattern: pattern, path: relativePath) || PathUtils.matchGlob(pattern: pattern, path: entry.name) {
                matches.append(entryPath)
            }
            if entry.isDir {
                try await globRecursive(pattern: pattern, basePath: basePath, currentPath: entryPath, matches: &matches)
            }
        }
    }

    public func initialize() async throws {
        try await container.start()
    }

    public func cleanup() async throws {
        await container.stop()
    }

    public func workingDirectory() -> String {
        hostWorkspaceDir
    }

    public func platform() -> String {
        "linux"
    }

    public func osVersion() -> String {
        "Alpine Linux 3.21 (host: \(hostPlatform))"
    }

    // MARK: - Path Translation

    private func translatePath(_ path: String) -> String {
        // Host absolute path under workspace -> guest /workspace/...
        if path.hasPrefix(hostWorkspaceDir) {
            let relative = String(path.dropFirst(hostWorkspaceDir.count))
            let trimmed = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
            return trimmed.isEmpty ? "workspace" : "workspace/\(trimmed)"
        }
        // Guest absolute path -> strip leading /
        if path.hasPrefix("/") {
            let stripped = String(path.dropFirst())
            return stripped.isEmpty ? "." : stripped
        }
        // Relative path -> resolve from workspace
        return path.isEmpty ? "workspace" : "workspace/\(path)"
    }
}
