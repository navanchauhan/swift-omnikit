import Foundation

public struct ToolCall: Sendable {
    public var id: String
    public var name: String
    public var arguments: [String: Any]
    public var rawArguments: String?

    public init(id: String, name: String, arguments: [String: Any], rawArguments: String? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.rawArguments = rawArguments
    }

    public var argumentsJSON: Data? {
        try? JSONSerialization.data(withJSONObject: arguments)
    }
}

public struct ToolResult: Sendable {
    public var toolCallId: String
    public var content: Any
    public var isError: Bool

    public init(toolCallId: String, content: Any, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }

    public var contentString: String {
        if let s = content as? String { return s }
        if let data = try? JSONSerialization.data(withJSONObject: content),
           let s = String(data: data, encoding: .utf8) { return s }
        return "\(content)"
    }
}
