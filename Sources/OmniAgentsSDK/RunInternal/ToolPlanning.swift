import Foundation
import OmniAICore

enum ToolPlanningRuntime {
    static func handoffMap<TContext>(for agent: Agent<TContext>) -> [String: Handoff<TContext>] {
        Dictionary(uniqueKeysWithValues: agent.handoffs.map { ($0.toolName, $0) })
    }

    static func toolMap(for tools: [Tool]) -> [String: Tool] {
        Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    static func extractToolCalls(from response: ModelResponse) -> [TResponseOutputItem] {
        let executableTypes: Set<String> = [
            "function_call",
            "computer_call",
            "shell_call",
            "apply_patch_call",
            "local_shell_call",
        ]
        return response.output.filter { item in
            guard let type = item["type"]?.stringValue else { return false }
            return executableTypes.contains(type)
        }
    }

    static func toolName(for item: TResponseOutputItem) -> String {
        if let name = item["name"]?.stringValue, !name.isEmpty {
            return name
        }
        switch item["type"]?.stringValue {
        case "computer_call":
            return "computer_use_preview"
        case "shell_call":
            return "shell"
        case "apply_patch_call":
            return "apply_patch"
        case "local_shell_call":
            return "local_shell"
        case "web_search_call":
            return "web_search"
        case "file_search_call":
            return "file_search"
        case "code_interpreter_call":
            return "code_interpreter"
        case "image_generation_call":
            return "image_generation"
        case "mcp_call":
            return item["tool_name"]?.stringValue ?? "hosted_mcp"
        default:
            return item["type"]?.stringValue ?? "tool"
        }
    }

    static func shouldExecuteLocally(_ tool: Tool) -> Bool {
        switch tool {
        case .function, .computer, .applyPatch, .localShell:
            return true
        case .shell(let shellTool):
            if let environment = shellTool.environment {
                switch environment {
                case .hosted:
                    return false
                case .local:
                    return true
                }
            }
            return true
        case .fileSearch, .webSearch, .hostedMCP, .codeInterpreter, .imageGeneration:
            return false
        }
    }

    static func hostedApprovalRequests(from response: ModelResponse) -> [TResponseOutputItem] {
        response.output.filter { $0["type"]?.stringValue == "mcp_approval_request" }
    }

    static func hostedToolUsedNames(from response: ModelResponse) -> [String] {
        let hostedTypes: Set<String> = [
            "file_search_call",
            "web_search_call",
            "code_interpreter_call",
            "image_generation_call",
            "mcp_call",
            "shell_call",
            "apply_patch_call",
            "local_shell_call",
            "computer_call",
        ]
        return response.output.compactMap { item in
            guard let type = item["type"]?.stringValue, hostedTypes.contains(type) else { return nil }
            return toolName(for: item)
        }
    }
}
