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
        response.output.filter { $0["type"]?.stringValue == "function_call" }
    }
}

