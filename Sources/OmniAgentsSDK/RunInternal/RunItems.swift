import Foundation

enum RunItemFactory {
    static func items<TContext>(
        from response: ModelResponse,
        agent: Agent<TContext>,
        handoffNames: Set<String>
    ) -> [any RunItem] {
        response.output.map { item in
            switch item["type"]?.stringValue {
            case "message":
                return MessageOutputItem(agent: agent, rawItem: item)
            case "function_call":
                if let name = item["name"]?.stringValue, handoffNames.contains(name) {
                    return HandoffCallItem(agent: agent, rawItem: item)
                }
                return ToolCallItem(agent: agent, rawItem: item)
            case "reasoning":
                return ReasoningItem(agent: agent, rawItem: item)
            case "mcp_list_tools":
                return MCPListToolsItem(agent: agent, rawItem: item)
            default:
                return MessageOutputItem(agent: agent, rawItem: item)
            }
        }
    }
}

