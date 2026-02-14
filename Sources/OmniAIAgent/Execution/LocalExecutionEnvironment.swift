import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class LocalExecutionEnvironment: ExecutionEnvironment, @unchecked Sendable {
    private let workingDir: String
    private let fileManager = FileManager.default

    // Sensitive env var patterns to exclude
    private static let sensitivePatterns = [
        "_API_KEY", "_SECRET", "_TOKEN", "_PASSWORD", "_CREDENTIAL",
    ]

    // Always include these env vars
    private static let safeVarNames: Set<String> = [
        "PATH", "HOME", "USER", "SHELL", "LANG", "TERM", "TMPDIR",
        "GOPATH", "CARGO_HOME", "NVM_DIR", "RUSTUP_HOME",
        "PYENV_ROOT", "RBENV_ROOT", "JAVA_HOME",
        "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME",
    ]

    public init(workingDir: String? = nil) {
        self.workingDir = workingDir ?? FileManager.default.currentDirectoryPath
    }

    // MARK: - File Operations

    public func readFile(path: String, offset: Int?, limit: Int?) async throws -> String {
        let resolvedPath = resolvePath(path)
        guard fileManager.fileExists(atPath: resolvedPath) else {
            throw ToolError.fileNotFound(resolvedPath)
        }

        guard let data = fileManager.contents(atPath: resolvedPath) else {
            throw ToolError.permissionDenied(resolvedPath)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw ToolError.binaryFile(resolvedPath)
        }

        let lines = content.components(separatedBy: "\n")
        let startLine = (offset ?? 1) - 1  // 1-based to 0-based
        let maxLines = limit ?? 2000
        let endLine = min(startLine + maxLines, lines.count)

        guard startLine >= 0 && startLine < lines.count else {
            return ""
        }

        var result = ""
        for i in startLine..<endLine {
            let lineNum = String(format: "%4d", i + 1)
            result += "\(lineNum) | \(lines[i])\n"
        }
        return result
    }

    public func writeFile(path: String, content: String) async throws {
        let resolvedPath = resolvePath(path)
        let dir = (resolvedPath as NSString).deletingLastPathComponent

        // Create parent directories
        if !fileManager.fileExists(atPath: dir) {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        guard let data = content.data(using: .utf8) else {
            throw ToolError.writeError("Failed to encode content as UTF-8")
        }

        let success = fileManager.createFile(atPath: resolvedPath, contents: data)
        if !success {
            throw ToolError.permissionDenied(resolvedPath)
        }
    }

    public func fileExists(path: String) async -> Bool {
        fileManager.fileExists(atPath: resolvePath(path))
    }

    public func listDirectory(path: String, depth: Int) async throws -> [DirEntry] {
        let resolvedPath = resolvePath(path)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDir), isDir.boolValue else {
            throw ToolError.fileNotFound(resolvedPath)
        }

        let contents = try fileManager.contentsOfDirectory(atPath: resolvedPath)
        return contents.compactMap { name in
            let fullPath = (resolvedPath as NSString).appendingPathComponent(name)
            var isSubDir: ObjCBool = false
            fileManager.fileExists(atPath: fullPath, isDirectory: &isSubDir)
            let attrs = try? fileManager.attributesOfItem(atPath: fullPath)
            let size = attrs?[.size] as? Int
            return DirEntry(name: name, isDir: isSubDir.boolValue, size: size)
        }.sorted(by: { $0.name < $1.name })
    }

    // MARK: - Command Execution

    public func execCommand(
        command: String,
        timeoutMs: Int,
        workingDir: String?,
        envVars: [String: String]?
    ) async throws -> ExecResult {
        let resolvedWorkingDir = workingDir.map { resolvePath($0) } ?? self.workingDir
        let startTime = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: resolvedWorkingDir)

        // Filter environment variables
        var env = filteredEnvironment()
        if let extra = envVars {
            env.merge(extra) { _, new in new }
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.qualityOfService = .userInitiated

        try process.run()

        let pid = process.processIdentifier

        // Place the child in its own process group so kill(-pid, SIGTERM) works
        setpgid(pid, pid)

        // Timeout task
        var timedOut = false
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
            timedOut = true
            // SIGTERM to process group
            kill(-pid, SIGTERM)
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            if process.isRunning {
                kill(-pid, SIGKILL)
            }
        }

        // Read output asynchronously to avoid deadlock when pipe buffers fill
        var stdoutData = Data()
        var stderrData = Data()
        let stdoutLock = NSLock()
        let stderrLock = NSLock()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutLock.lock()
                stdoutData.append(data)
                stdoutLock.unlock()
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrLock.lock()
                stderrData.append(data)
                stderrLock.unlock()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        // Stop handlers and read any remaining data
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutLock.lock()
        stdoutData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stdoutLock.unlock()
        stderrLock.lock()
        stderrData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        stderrLock.unlock()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        return ExecResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus,
            timedOut: timedOut,
            durationMs: durationMs
        )
    }

    // MARK: - Search Operations

    public func grep(pattern: String, path: String, options: GrepOptions) async throws -> String {
        let resolvedPath = resolvePath(path)
        var args = ["rg", "--no-heading", "--line-number"]

        if options.caseInsensitive {
            args.append("-i")
        }
        args.append("--max-count=\(options.maxResults)")

        if let globFilter = options.globFilter {
            args.append("--glob=\(globFilter)")
        }

        args.append(pattern)
        args.append(resolvedPath)

        let cmd = args.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
        let result = try await execCommand(command: cmd, timeoutMs: 10_000, workingDir: nil, envVars: nil)

        if result.exitCode == 0 {
            return result.stdout
        } else if result.exitCode == 1 {
            return "No matches found."
        } else {
            // Fallback to grep if rg not available
            var grepArgs = ["grep", "-rn"]
            if options.caseInsensitive { grepArgs.append("-i") }
            if let globFilter = options.globFilter {
                grepArgs.append("--include=\(globFilter)")
            }
            grepArgs.append(pattern)
            grepArgs.append(resolvedPath)
            let grepCmd = grepArgs.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
            let grepResult = try await execCommand(command: grepCmd, timeoutMs: 10_000, workingDir: nil, envVars: nil)
            return grepResult.stdout.isEmpty ? "No matches found." : grepResult.stdout
        }
    }

    public func glob(pattern: String, path: String) async throws -> [String] {
        let resolvedPath = resolvePath(path)
        // Sort by modification time (newest first) as required by the spec
        let cmd: String
        #if os(Linux)
        cmd = "find '\(resolvedPath)' -path '\(resolvedPath)/\(pattern)' -type f -printf '%T@ %p\\n' 2>/dev/null | sort -rn | cut -d' ' -f2- | head -1000"
        #else
        // macOS/Darwin: use stat -f for modification time
        cmd = "find '\(resolvedPath)' -path '\(resolvedPath)/\(pattern)' -type f -print0 2>/dev/null | xargs -0 stat -f '%m %N' 2>/dev/null | sort -rn | cut -d' ' -f2- | head -1000"
        #endif
        let result = try await execCommand(command: cmd, timeoutMs: 10_000, workingDir: nil, envVars: nil)

        if result.stdout.isEmpty {
            return []
        }
        return result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // MARK: - Lifecycle

    public func initialize() async throws {
        // Create working directory if needed
        if !fileManager.fileExists(atPath: workingDir) {
            try fileManager.createDirectory(atPath: workingDir, withIntermediateDirectories: true)
        }
    }

    public func cleanup() async throws {
        // Nothing to clean up for local env
    }

    // MARK: - Metadata

    public func workingDirectory() -> String {
        workingDir
    }

    public func platform() -> String {
        #if os(macOS)
        return "darwin"
        #elseif os(Linux)
        return "linux"
        #elseif os(Windows)
        return "windows"
        #else
        return "unknown"
        #endif
    }

    public func osVersion() -> String {
        let info = ProcessInfo.processInfo
        let version = info.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #if os(macOS)
        return "Darwin \(versionString)"
        #elseif os(Linux)
        // Try to read /etc/os-release for distribution info
        if let data = FileManager.default.contents(atPath: "/etc/os-release"),
           let content = String(data: data, encoding: .utf8) {
            for line in content.components(separatedBy: "\n") {
                if line.hasPrefix("PRETTY_NAME=") {
                    let name = line.dropFirst("PRETTY_NAME=".count)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    return "Linux \(name)"
                }
            }
        }
        return "Linux \(versionString)"
        #else
        return "Unknown \(versionString)"
        #endif
    }

    // MARK: - Helpers

    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return (workingDir as NSString).appendingPathComponent(path)
    }

    private func filteredEnvironment() -> [String: String] {
        var filtered: [String: String] = [:]
        for (key, value) in ProcessInfo.processInfo.environment {
            let upperKey = key.uppercased()
            let isSensitive = Self.sensitivePatterns.contains { upperKey.contains($0) }

            if Self.safeVarNames.contains(key) || !isSensitive {
                filtered[key] = value
            }
        }
        return filtered
    }
}

// MARK: - Tool Errors

public enum ToolError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case permissionDenied(String)
    case binaryFile(String)
    case writeError(String)
    case editConflict(String)
    case patchError(String)
    case timeout(Int)
    case validationError(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .permissionDenied(let path): return "Permission denied: \(path)"
        case .binaryFile(let path): return "Cannot read binary file: \(path)"
        case .writeError(let msg): return "Write error: \(msg)"
        case .editConflict(let msg): return "Edit conflict: \(msg)"
        case .patchError(let msg): return "Patch error: \(msg)"
        case .timeout(let ms): return "Command timed out after \(ms)ms"
        case .validationError(let msg): return "Validation error: \(msg)"
        }
    }
}
