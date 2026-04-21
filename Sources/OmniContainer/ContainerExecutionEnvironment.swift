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
        let content = try await container.readFile(path: guestPath)
        let lines = content.components(separatedBy: "\n")
        let startLine = max(0, (offset ?? 1) - 1)
        let maxLines = limit ?? 2000
        let endLine = min(startLine + maxLines, lines.count)

        guard startLine < lines.count else {
            return ""
        }

        var result = ""
        for index in startLine..<endLine {
            let lineNumber = String(format: "%4d", index + 1)
            result += "\(lineNumber) | \(lines[index])\n"
        }
        return result
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
            .sorted { $0.name < $1.name }
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
                            let hostPath = hostPath(forGuestPath: entryPath)
                            results.append("\(hostPath):\(i + 1):\(line)")
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
        let regex = try globRegularExpression(pattern: pattern)
        var matches: [String] = []
        try await globRecursive(
            matcher: regex,
            basePath: guestPath,
            currentPath: guestPath,
            matches: &matches
        )
        return Array(Set(matches)).sorted()
    }

    public func startInteractiveSession(
        command: String?,
        workingDir: String?,
        envVars: [String: String]?,
        size: TerminalSize
    ) async throws -> any InteractiveExecutionSession {
        let guestWorkDir = workingDir.map { translatePath($0) } ?? guestWorkspaceDir
        return try await container.startInteractiveShell(
            command: command,
            env: envVars,
            workingDir: guestWorkDir,
            size: size
        )
    }

    private func globRecursive(
        matcher: NSRegularExpression,
        basePath: String,
        currentPath: String,
        matches: inout [String]
    ) async throws {
        let entries = try await container.listDirectory(path: currentPath, depth: 1)
        for entry in entries {
            let entryPath = currentPath == "." ? entry.name : "\(currentPath)/\(entry.name)"
            if entry.isDir {
                try await globRecursive(
                    matcher: matcher,
                    basePath: basePath,
                    currentPath: entryPath,
                    matches: &matches
                )
                continue
            }

            let relativePath = relativePath(forGuestPath: entryPath, basePath: basePath)
            let range = NSRange(relativePath.startIndex..<relativePath.endIndex, in: relativePath)
            if matcher.firstMatch(in: relativePath, options: [], range: range) != nil {
                matches.append(hostPath(forGuestPath: entryPath))
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
        guestWorkspaceDir
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

    private func hostPath(forGuestPath guestPath: String) -> String {
        let normalized = guestPath.hasPrefix("/") ? String(guestPath.dropFirst()) : guestPath
        if normalized.isEmpty || normalized == "." || normalized == "workspace" {
            return hostWorkspaceDir
        }
        if normalized.hasPrefix("workspace/") {
            let relative = String(normalized.dropFirst("workspace/".count))
            return (hostWorkspaceDir as NSString).appendingPathComponent(relative)
        }
        return (hostWorkspaceDir as NSString).appendingPathComponent(normalized)
    }

    private func relativePath(forGuestPath guestPath: String, basePath: String) -> String {
        let normalizedBase = basePath.hasPrefix("/") ? String(basePath.dropFirst()) : basePath
        let normalizedGuest = guestPath.hasPrefix("/") ? String(guestPath.dropFirst()) : guestPath

        guard normalizedBase != ".", normalizedGuest.hasPrefix(normalizedBase) else {
            return normalizedGuest
        }

        let suffix = String(normalizedGuest.dropFirst(normalizedBase.count))
        if suffix.hasPrefix("/") {
            return String(suffix.dropFirst())
        }
        return suffix
    }

    private func globRegularExpression(pattern: String) throws -> NSRegularExpression {
        let normalizedPattern = pattern.replacingOccurrences(of: "\\", with: "/")
        var regex = "^"
        var index = normalizedPattern.startIndex

        while index < normalizedPattern.endIndex {
            let character = normalizedPattern[index]
            if character == "*" {
                let nextIndex = normalizedPattern.index(after: index)
                if nextIndex < normalizedPattern.endIndex, normalizedPattern[nextIndex] == "*" {
                    let afterDoubleStar = normalizedPattern.index(after: nextIndex)
                    if afterDoubleStar < normalizedPattern.endIndex, normalizedPattern[afterDoubleStar] == "/" {
                        regex += "(?:.*/)?"
                        index = normalizedPattern.index(after: afterDoubleStar)
                    } else {
                        regex += ".*"
                        index = afterDoubleStar
                    }
                    continue
                }

                regex += "[^/]*"
                index = nextIndex
                continue
            }

            if character == "?" {
                regex += "[^/]"
                index = normalizedPattern.index(after: index)
                continue
            }

            if ".+()^$|{}".contains(character) {
                regex += "\\"
            }

            regex.append(character)
            index = normalizedPattern.index(after: index)
        }

        regex += "$"
        return try NSRegularExpression(pattern: regex, options: [])
    }
}
