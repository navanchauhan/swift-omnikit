import Foundation

public struct Request: Sendable {
    public var model: String
    public var messages: [Message]
    public var provider: String?
    public var tools: [ToolDefinition]?
    public var toolChoice: ToolChoice?
    public var responseFormat: ResponseFormat?
    public var temperature: Double?
    public var topP: Double?
    public var maxTokens: Int?
    public var stopSequences: [String]?
    public var reasoningEffort: String?
    public var metadata: [String: String]?
    public var providerOptions: [String: [String: AnyCodable]]?

    public init(
        model: String,
        messages: [Message],
        provider: String? = nil,
        tools: [ToolDefinition]? = nil,
        toolChoice: ToolChoice? = nil,
        responseFormat: ResponseFormat? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        stopSequences: [String]? = nil,
        reasoningEffort: String? = nil,
        metadata: [String: String]? = nil,
        providerOptions: [String: [String: AnyCodable]]? = nil
    ) {
        self.model = model
        self.messages = messages
        self.provider = provider
        self.tools = tools
        self.toolChoice = toolChoice
        self.responseFormat = responseFormat
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.stopSequences = stopSequences
        self.reasoningEffort = reasoningEffort
        self.metadata = metadata
        self.providerOptions = providerOptions
    }
}

public struct ToolDefinition: Sendable {
    public var name: String
    public var description: String
    public var parameters: [String: Any]

    public init(name: String, description: String, parameters: [String: Any]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    public var parametersJSON: Data? {
        try? JSONSerialization.data(withJSONObject: parameters)
    }
}

public struct ToolChoice: Sendable {
    public var mode: String
    public var toolName: String?

    public init(mode: String, toolName: String? = nil) {
        self.mode = mode
        self.toolName = toolName
    }

    public static let auto = ToolChoice(mode: "auto")
    public static let none = ToolChoice(mode: "none")
    public static let required = ToolChoice(mode: "required")
    public static func named(_ name: String) -> ToolChoice {
        ToolChoice(mode: "named", toolName: name)
    }
}

public struct ResponseFormat: Sendable {
    public var type: String
    public var jsonSchema: [String: Any]?
    public var strict: Bool

    public init(type: String, jsonSchema: [String: Any]? = nil, strict: Bool = false) {
        self.type = type
        self.jsonSchema = jsonSchema
        self.strict = strict
    }

    public static let text = ResponseFormat(type: "text")
    public static let json = ResponseFormat(type: "json")
    public static func jsonSchema(_ schema: [String: Any], strict: Bool = false) -> ResponseFormat {
        ResponseFormat(type: "json_schema", jsonSchema: schema, strict: strict)
    }
}
