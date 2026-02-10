import Foundation

public struct ToolExecutionContext: Sendable {
    public var messages: [Message]
    public var abortSignal: AbortSignal?
    public var toolCallId: String

    public init(messages: [Message], abortSignal: AbortSignal?, toolCallId: String) {
        self.messages = messages
        self.abortSignal = abortSignal
        self.toolCallId = toolCallId
    }
}

public typealias ToolExecute = @Sendable (_ arguments: [String: JSONValue], _ context: ToolExecutionContext) async throws -> JSONValue

public struct Tool: Sendable {
    public var name: String
    public var description: String
    public var parameters: JSONValue
    public var execute: ToolExecute?

    public init(name: String, description: String, parameters: JSONValue, execute: ToolExecute? = nil) throws {
        try Tool.validateName(name)
        try Tool.validateParametersSchema(parameters)
        self.name = name
        self.description = description
        self.parameters = parameters
        self.execute = execute
    }

    private static func validateName(_ name: String) throws {
        if name.count > 64 {
            throw InvalidToolCallError(message: "Tool name too long (max 64): \(name)")
        }
        let regex = try! NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9_]*$", options: [])
        let range = NSRange(location: 0, length: (name as NSString).length)
        if regex.firstMatch(in: name, options: [], range: range) == nil {
            throw InvalidToolCallError(message: "Invalid tool name: \(name)")
        }
    }

    private static func validateParametersSchema(_ schema: JSONValue) throws {
        guard let obj = schema.objectValue else {
            throw InvalidToolCallError(message: "Tool parameters must be a JSON object schema")
        }
        guard let type = obj["type"]?.stringValue, type == "object" else {
            throw InvalidToolCallError(message: "Tool parameters schema root type must be 'object'")
        }
    }
}

public enum ToolChoiceMode: String, Sendable, Equatable {
    case auto
    case none
    case required
    case named
}

public struct ToolChoice: Sendable, Equatable {
    public var mode: ToolChoiceMode
    public var toolName: String?

    public init(mode: ToolChoiceMode, toolName: String? = nil) {
        self.mode = mode
        self.toolName = toolName
    }
}
