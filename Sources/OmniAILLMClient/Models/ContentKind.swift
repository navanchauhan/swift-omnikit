import Foundation

public enum ContentKind: String, Codable, Sendable {
    case text
    case image
    case audio
    case document
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case thinking
    case redactedThinking = "redacted_thinking"
}
