import Foundation
import OmniAILLMClient

public struct AgentToolDefinition: Sendable {
    public var name: String
    public var description: String
    public var parameters: [String: Any]

    public init(name: String, description: String, parameters: [String: Any]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    public func toLLMKitDefinition() -> ToolDefinition {
        ToolDefinition(name: name, description: description, parameters: parameters)
    }
}

public typealias ToolExecutor = @Sendable ([String: Any], ExecutionEnvironment) async throws -> String

public struct RegisteredTool: Sendable {
    public var definition: AgentToolDefinition
    public var executor: ToolExecutor

    public init(definition: AgentToolDefinition, executor: @escaping ToolExecutor) {
        self.definition = definition
        self.executor = executor
    }
}

public final class ToolRegistry: @unchecked Sendable {
    private var tools: [String: RegisteredTool] = [:]
    private let lock = NSLock()

    public init() {}

    public func register(_ tool: RegisteredTool) {
        lock.lock()
        defer { lock.unlock() }
        tools[tool.definition.name] = tool
    }

    public func unregister(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        tools.removeValue(forKey: name)
    }

    public func get(_ name: String) -> RegisteredTool? {
        lock.lock()
        defer { lock.unlock() }
        return tools[name]
    }

    public func definitions() -> [AgentToolDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tools.values.map { $0.definition })
    }

    public func llmKitDefinitions() -> [ToolDefinition] {
        definitions().map { $0.toLLMKitDefinition() }
    }

    public func names() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tools.keys)
    }
}
