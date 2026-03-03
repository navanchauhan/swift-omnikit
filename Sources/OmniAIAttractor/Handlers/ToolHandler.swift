import Foundation

// MARK: - Tool Handler

// Safety: @unchecked Sendable — no mutable state; all state is local to execute().
// Note: execute() blocks a cooperative thread pool thread via readDataToEndOfFile()
// and waitUntilExit(). This is acceptable for sequential pipeline execution but
// may cause thread starvation under ParallelHandler with many tool nodes.
// TODO: Move Process execution to a detached task or blocking executor.
public final class ToolHandler: NodeHandler, @unchecked Sendable {
    public let handlerType: HandlerType = .tool

    public init() {}

    public func execute(
        node: Node,
        context: PipelineContext,
        graph: Graph,
        logsRoot: URL
    ) async throws -> Outcome {
        // Get command from node prompt or tool command attributes.
        // `tool_command` is the spec key; `command` is supported for compatibility.
        var command = node.prompt
        if command.isEmpty, let cmdAttr = node.rawAttributes["tool_command"] {
            command = cmdAttr.stringValue
        }
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
        } catch {
            return .fail(reason: "Failed to launch command for node \(node.id): \(error)")
        }

        // Read pipe data BEFORE waitUntilExit to avoid deadlock when output
        // exceeds the pipe buffer (~64KB). Reading first drains the buffer so
        // the child process can continue writing.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

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
                    "tool.output": outStr,
                    "tool.stderr": errStr,
                    "tool.exit_code": String(exitCode),
                    // Legacy aliases for compatibility.
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
                "tool.output": outStr,
                "tool.exit_code": "0",
                // Legacy aliases for compatibility.
                "tool_stdout": outStr,
                "tool_exit_code": "0",
            ],
            notes: "Command completed successfully"
        )
    }
}
