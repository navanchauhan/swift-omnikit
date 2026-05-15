import BashCommandKit
import Foundation

public struct Environment: Sendable {
    public var workingDirectory: String
    private var values: [String: String]

    public static func current() -> Environment {
        var environment = Environment(
            workingDirectory: FileManager.default.currentDirectoryPath,
            values: ProcessInfo.processInfo.environment
        )
        if let pwd = environment.values["PWD"], !pwd.isEmpty {
            environment.workingDirectory = pwd
        }
        return environment
    }

    public static func synthetic(workingDirectory: String) -> Environment {
        Environment(
            workingDirectory: workingDirectory,
            values: [
                "HOME": NSHomeDirectory(),
                "PATH": "/usr/local/bin:/usr/bin:/bin",
                "PWD": workingDirectory,
                "SHELL": "/bin/bash",
                "TERM": "xterm-256color",
            ]
        )
    }

    public subscript(key: String) -> String? {
        get { values[key] }
        set { values[key] = newValue }
    }

    var processValues: [String: String] {
        var next = values
        next["PWD"] = workingDirectory
        return next
    }

    mutating func replace(withProcessValues next: [String: String], workingDirectory: String) {
        values = next
        self.workingDirectory = workingDirectory
        values["PWD"] = workingDirectory
    }

    private init(workingDirectory: String, values: [String: String]) {
        self.workingDirectory = workingDirectory
        self.values = values
    }
}

public enum HostInfo: Sendable, Equatable {
    case real
    case synthetic

    public static func real() -> HostInfo { .real }
}

public struct ExitStatus: Sendable, Equatable {
    public var code: Int32

    public init(code: Int32) {
        self.code = code
    }
}

public struct CapturedRun: Sendable, Equatable {
    public var stdout: String
    public var stderr: String
    public var exitStatus: ExitStatus

    public init(stdout: String, stderr: String, exitStatus: ExitStatus) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitStatus = exitStatus
    }
}

public final class Shell: @unchecked Sendable {
    public var environment: Environment
    public var hostInfo: HostInfo = .synthetic
    public var networkConfig: NetworkConfig?

    private let fileSystem: any FileSystem
    private let lock = NSLock()

    public init(environment: Environment, fileSystem: any FileSystem) {
        self.environment = environment
        self.fileSystem = fileSystem
    }

    public func registerStandardCommands() {}

    public func runCapturing(_ command: String) async throws -> CapturedRun {
        try Task.checkCancellation()

        let marker = "__OMNI_SWIFTBASH_STATE_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"
        let envMarker = "__OMNI_SWIFTBASH_ENV_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"
        let script = """
        \(command)
        __omni_status=$?
        printf '\\n\(marker)\\n'
        pwd
        printf '\\n\(envMarker)\\n'
        env -0
        exit $__omni_status
        """

        let snapshot = lock.withLock { environment }
        let process = Process()
        let processBox = ProcessBox(process)
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", script]
        process.environment = snapshot.processValues
        process.currentDirectoryURL = URL(fileURLWithPath: fileSystem.executionRoot ?? snapshot.workingDirectory, isDirectory: true)
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                        process.waitUntilExit()
                        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
                        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
                        let parsed = Self.parseState(stdoutText, marker: marker, envMarker: envMarker)
                        if let state = parsed.state {
                            self.lock.withLock {
                                self.environment.replace(
                                    withProcessValues: state.environment,
                                    workingDirectory: self.logicalWorkingDirectory(
                                        processWorkingDirectory: state.workingDirectory,
                                        fallback: snapshot.workingDirectory
                                    )
                                )
                            }
                        }
                        continuation.resume(returning: CapturedRun(
                            stdout: parsed.stdout,
                            stderr: stderrText,
                            exitStatus: ExitStatus(code: process.terminationStatus)
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            processBox.terminate()
        }
    }

    private func logicalWorkingDirectory(processWorkingDirectory: String, fallback: String) -> String {
        guard let executionRoot = fileSystem.executionRoot,
              processWorkingDirectory.hasPrefix(executionRoot) else {
            return processWorkingDirectory
        }
        let suffix = processWorkingDirectory.dropFirst(executionRoot.count)
        if suffix.isEmpty { return fallback }
        return (fallback as NSString).appendingPathComponent(String(suffix).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private static func parseState(
        _ stdout: String,
        marker: String,
        envMarker: String
    ) -> (stdout: String, state: (workingDirectory: String, environment: [String: String])?) {
        let stateDelimiter = "\n\(marker)\n"
        guard let stateRange = stdout.range(of: stateDelimiter) else {
            return (stdout, nil)
        }

        let commandStdout = String(stdout[..<stateRange.lowerBound])
        let stateText = String(stdout[stateRange.upperBound...])
        let envDelimiter = "\n\(envMarker)\n"
        guard let envRange = stateText.range(of: envDelimiter) else {
            return (commandStdout, nil)
        }

        let workingDirectory = String(stateText[..<envRange.lowerBound])
            .trimmingCharacters(in: .newlines)
        let envText = String(stateText[envRange.upperBound...])
        var environment: [String: String] = [:]
        for entry in envText.split(separator: "\0", omittingEmptySubsequences: true) {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<equals])
            let value = String(entry[entry.index(after: equals)...])
            environment[key] = value
        }
        return (commandStdout, (workingDirectory, environment))
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        lock.withLock {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
