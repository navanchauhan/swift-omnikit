import Foundation
import OmniAILLMClient

public protocol ProviderProfile: Sendable {
    var id: String { get }
    var model: String { get }
    var toolRegistry: ToolRegistry { get }

    func buildSystemPrompt(environment: ExecutionEnvironment, projectDocs: String?, userInstructions: String?, gitContext: GitContext?) -> String
    func tools() -> [ToolDefinition]
    func providerOptions() -> [String: [String: AnyCodable]]?

    var supportsReasoning: Bool { get }
    var supportsStreaming: Bool { get }
    var supportsParallelToolCalls: Bool { get }
    var contextWindowSize: Int { get }
}

extension ProviderProfile {
    public func tools() -> [ToolDefinition] {
        toolRegistry.llmKitDefinitions()
    }
}
