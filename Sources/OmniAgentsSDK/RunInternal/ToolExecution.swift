import Foundation
import OmniAICore

private struct AnySendableBox: @unchecked Sendable {
    let value: Any
}

enum ToolRuntime {
    static func isToolEnabled<TContext>(_ tool: Tool, runContext: RunContextWrapper<TContext>, agent: Any) async throws -> Bool {
        switch tool {
        case .function(let functionTool):
            return try await functionTool.isEnabled.evaluate(context: runContext, agent: agent)
        default:
            return true
        }
    }

    static func execute<TContext>(
        tool: Tool,
        call: TResponseOutputItem,
        runContext: RunContextWrapper<TContext>,
        agent: Any,
        runConfig: RunConfig?
    ) async throws -> FunctionToolResult {
        let callID = call["call_id"]?.stringValue ?? call["id"]?.stringValue ?? UUID().uuidString
        let argumentsObject: [String: JSONValue]
        let rawArguments: String
        if let object = call["arguments"]?.objectValue {
            argumentsObject = object
            rawArguments = ItemHelpers.stringifyJSON(.object(object))
        } else if let string = call["arguments"]?.stringValue {
            rawArguments = string
            if let data = string.data(using: .utf8), let value = try? JSONValue.parse(data), case .object(let object) = value {
                argumentsObject = object
            } else {
                argumentsObject = [:]
            }
        } else {
            argumentsObject = [:]
            rawArguments = "{}"
        }

        let erasedContext = ToolContext<Any>(
            context: runContext.context as Any,
            usage: runContext.usage,
            toolName: call["name"]?.stringValue ?? call["type"]?.stringValue ?? "tool",
            toolCallID: callID,
            toolArguments: rawArguments,
            toolCall: buildToolCall(from: call, fallbackID: callID),
            agent: agent,
            runConfig: runConfig,
            turnInput: runContext.turnInput,
            toolInput: runContext.toolInput
        )
        erasedContext.rebuildApprovals(from: runContext.serializedApprovals())
        erasedContext.toolInput = runContext.toolInput

        switch tool {
        case .function(let functionTool):
            for guardrail in functionTool.toolInputGuardrails ?? [] {
                let result = try await guardrail.run(.init(context: erasedContext, agent: unsafeBitCast(agent, to: Agent<Any>.self)))
                switch result.behavior {
                case .allow:
                    break
                case .rejectContent(let message):
                    return FunctionToolResult(tool: functionTool, output: message)
                case .raiseException:
                    throw ToolInputGuardrailTripwireTriggered(guardrail: guardrail, output: result, guardrailName: guardrail.getName())
                }
            }

            let output = try await withTimeoutAny(seconds: functionTool.timeoutSeconds) {
                try await functionTool.onInvokeTool(erasedContext, rawArguments)
            }

            for guardrail in functionTool.toolOutputGuardrails ?? [] {
                let result = try await guardrail.run(.init(context: erasedContext, agent: unsafeBitCast(agent, to: Agent<Any>.self), output: output))
                switch result.behavior {
                case .allow:
                    break
                case .rejectContent(let message):
                    return FunctionToolResult(tool: functionTool, output: message)
                case .raiseException:
                    throw ToolOutputGuardrailTripwireTriggered(guardrail: guardrail, output: result, guardrailName: guardrail.getName())
                }
            }

            return FunctionToolResult(tool: functionTool, output: output)

        case .shell(let shellTool):
            guard let executor = shellTool.executor else {
                throw UserError(message: "Shell tool has no executor")
            }
            let request = ShellCommandRequest(
                contextWrapper: RunContextWrapper<Any>(context: runContext.context as Any, usage: runContext.usage, turnInput: runContext.turnInput),
                data: .init(
                    callID: callID,
                    action: .init(
                        commands: argumentsObject["commands"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                        timeoutMS: argumentsObject["timeout_ms"]?.doubleValue.map(Int.init),
                        maxOutputLength: argumentsObject["max_output_length"]?.doubleValue.map(Int.init)
                    ),
                    status: nil,
                    raw: .object(call)
                )
            )
            let result = try await executor(request)
            let wrapped = FunctionTool(
                name: shellTool.name,
                description: "Run shell commands.",
                paramsJSONSchema: Tool.shell(shellTool).inputSchema,
                onInvokeTool: { _, _ in result }
            )
            return FunctionToolResult(tool: wrapped, output: result)

        case .localShell(let localShellTool):
            let request = LocalShellCommandRequest(
                contextWrapper: RunContextWrapper<Any>(context: runContext.context as Any, usage: runContext.usage, turnInput: runContext.turnInput),
                data: .init(
                    callID: callID,
                    action: .init(
                        commands: argumentsObject["commands"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                        timeoutMS: argumentsObject["timeout_ms"]?.doubleValue.map(Int.init),
                        maxOutputLength: argumentsObject["max_output_length"]?.doubleValue.map(Int.init)
                    ),
                    status: nil,
                    raw: .object(call)
                )
            )
            let result = try await localShellTool.executor(request)
            let wrapped = FunctionTool(
                name: localShellTool.name,
                description: "Run local shell commands.",
                paramsJSONSchema: Tool.localShell(localShellTool).inputSchema,
                onInvokeTool: { _, _ in result }
            )
            return FunctionToolResult(tool: wrapped, output: result)

        case .applyPatch(let applyPatchTool):
            let operations = argumentsObject["operations"]?.arrayValue?.compactMap { value -> ApplyPatchOperation? in
                guard case .object(let object) = value else { return nil }
                guard let type = object["type"]?.stringValue.flatMap(ApplyPatchOperationType.init(rawValue:)),
                      let path = object["path"]?.stringValue
                else { return nil }
                return ApplyPatchOperation(type: type, path: path, diff: object["diff"]?.stringValue)
            } ?? []
            var outputs: [String] = []
            for operation in operations {
                switch operation.type {
                case .createFile:
                    if let result = try await applyPatchTool.editor.createFile(operation), let output = result.output { outputs.append(output) }
                case .updateFile:
                    if let result = try await applyPatchTool.editor.updateFile(operation), let output = result.output { outputs.append(output) }
                case .deleteFile:
                    if let result = try await applyPatchTool.editor.deleteFile(operation), let output = result.output { outputs.append(output) }
                }
            }
            let outputText = outputs.joined(separator: "\n")
            let wrapped = FunctionTool(
                name: applyPatchTool.name,
                description: "Apply filesystem patches.",
                paramsJSONSchema: Tool.applyPatch(applyPatchTool).inputSchema,
                onInvokeTool: { _, _ in outputText }
            )
            return FunctionToolResult(tool: wrapped, output: outputText)

        default:
            throw UserError(message: "Tool \(tool.name) cannot be executed locally by this runtime")
        }
    }
}

private func buildToolCall(from item: TResponseOutputItem, fallbackID: String) -> ToolCall {
    let arguments: [String: JSONValue]
    let rawArguments: String?
    if let object = item["arguments"]?.objectValue {
        arguments = object
        rawArguments = ItemHelpers.stringifyJSON(.object(object))
    } else if let string = item["arguments"]?.stringValue {
        rawArguments = string
        if let data = string.data(using: .utf8), let value = try? JSONValue.parse(data), case .object(let object) = value {
            arguments = object
        } else {
            arguments = [:]
        }
    } else {
        arguments = [:]
        rawArguments = nil
    }

    return ToolCall(
        id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? fallbackID,
        name: item["name"]?.stringValue ?? item["type"]?.stringValue ?? "tool",
        arguments: arguments,
        rawArguments: rawArguments,
        thoughtSignature: item["thought_signature"]?.stringValue,
        providerItemId: item["id"]?.stringValue
    )
}

private final class _UncheckedValueBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private func withTimeoutAny<T>(seconds: Double?, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    guard let seconds else {
        return try await operation()
    }
    return try await withThrowingTaskGroup(of: _UncheckedValueBox<T>.self) { group in
        group.addTask {
            _UncheckedValueBox(try await operation())
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ToolTimeoutError(toolName: "tool", timeoutSeconds: seconds)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result.value
    }
}
