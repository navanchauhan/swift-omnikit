import Foundation

public typealias ToolExecuteHandler = @Sendable ([String: Any]) async throws -> Any

public struct Tool: Sendable {
    public var name: String
    public var description: String
    public var parameters: [String: Any]
    public var execute: ToolExecuteHandler?

    private static let validNamePattern = try! NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9_]*$")

    public init(
        name: String,
        description: String,
        parameters: [String: Any],
        execute: ToolExecuteHandler? = nil
    ) {
        // Validate tool name
        let nameRange = NSRange(name.startIndex..., in: name)
        if name.count > 64 {
            print("[LLMKit] Warning: Tool name '\(name)' exceeds 64 characters. Some providers may reject this.")
        } else if Self.validNamePattern.firstMatch(in: name, range: nameRange) == nil {
            print("[LLMKit] Warning: Tool name '\(name)' does not match ^[A-Za-z][A-Za-z0-9_]*$. Some providers may reject this.")
        }

        self.name = name
        self.description = description
        self.parameters = parameters
        self.execute = execute
    }

    public var definition: ToolDefinition {
        ToolDefinition(name: name, description: description, parameters: parameters)
    }

    public var isActive: Bool { execute != nil }
}

public enum StopCondition: Sendable {
    case custom(@Sendable ([StepResult]) -> Bool)

    public func shouldStop(steps: [StepResult]) -> Bool {
        switch self {
        case .custom(let fn):
            return fn(steps)
        }
    }
}
