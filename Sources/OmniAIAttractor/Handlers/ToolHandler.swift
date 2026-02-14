import Foundation

// MARK: - Tool Handler

public final class ToolHandler: NodeHandler, @unchecked Sendable {
    public let handlerType: HandlerType = .tool

    public init() {}

    public func execute(
        node: Node,
        context: PipelineContext,
        graph: Graph,
        logsRoot: URL
    ) async throws -> Outcome {
        // Get command from node prompt or command attribute
        var command = node.prompt
        if command.isEmpty, let cmdAttr = node.rawAttributes["command"] {
            command = cmdAttr.stringValue
        }

        guard !command.isEmpty else {
            return .fail(reason: "Tool node \(node.id) has no command specified")
        }

        // Execute command via shell
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .fail(reason: "Failed to launch command for node \(node.id): \(error)")
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        let exitCode = process.terminationStatus

        // Write logs
        let stageDir = logsRoot.appendingPathComponent(node.id)
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

        let logFile = stageDir.appendingPathComponent("tool_output.txt")
        var logContent = "Command: \(command)\nExit code: \(exitCode)\n\n--- stdout ---\n\(outStr)"
        if !errStr.isEmpty {
            logContent += "\n\n--- stderr ---\n\(errStr)"
        }
        try Data(logContent.utf8).write(to: logFile)

        if exitCode != 0 {
            return Outcome(
                status: .fail,
                contextUpdates: [
                    "tool_stdout": outStr,
                    "tool_stderr": errStr,
                    "tool_exit_code": String(exitCode),
                ],
                failureReason: "Command exited with code \(exitCode)"
            )
        }

        return Outcome(
            status: .success,
            contextUpdates: [
                "tool_stdout": outStr,
                "tool_exit_code": "0",
            ],
            notes: "Command completed successfully"
        )
    }
}
