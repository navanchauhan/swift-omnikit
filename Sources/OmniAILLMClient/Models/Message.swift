import Foundation

public struct Message: Codable, Sendable {
    public var role: Role
    public var content: [ContentPart]
    public var name: String?
    public var toolCallId: String?

    public init(role: Role, content: [ContentPart], name: String? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCallId = toolCallId
    }

    /// Concatenates text from all text content parts
    public var text: String {
        content
            .filter { $0.contentKind == .text }
            .compactMap { $0.text }
            .joined()
    }

    /// Extracts all tool calls from this message
    public var toolCalls: [ToolCall] {
        content
            .filter { $0.contentKind == .toolCall }
            .compactMap { part -> ToolCall? in
                guard let tc = part.toolCall else { return nil }
                return ToolCall(
                    id: tc.id,
                    name: tc.name,
                    arguments: tc.arguments.dictValue ?? [:],
                    rawArguments: tc.arguments.stringValue
                )
            }
    }

    /// Extracts reasoning/thinking text
    public var reasoning: String? {
        let texts = content
            .filter { $0.contentKind == .thinking }
            .compactMap { $0.thinking?.text }
        return texts.isEmpty ? nil : texts.joined()
    }

    // MARK: - Convenience Constructors

    public static func system(_ text: String) -> Message {
        Message(role: .system, content: [.text(text)])
    }

    public static func user(_ text: String) -> Message {
        Message(role: .user, content: [.text(text)])
    }

    public static func assistant(_ text: String) -> Message {
        Message(role: .assistant, content: [.text(text)])
    }

    public static func developer(_ text: String) -> Message {
        Message(role: .developer, content: [.text(text)])
    }

    public static func toolResult(toolCallId: String, content: String, isError: Bool = false) -> Message {
        Message(
            role: .tool,
            content: [.toolResult(ToolResultData(toolCallId: toolCallId, content: AnyCodable(content), isError: isError))],
            toolCallId: toolCallId
        )
    }

    public static func toolResult(toolCallId: String, content: [String: Any], isError: Bool = false) -> Message {
        Message(
            role: .tool,
            content: [.toolResult(ToolResultData(toolCallId: toolCallId, content: AnyCodable(content), isError: isError))],
            toolCallId: toolCallId
        )
    }
}
