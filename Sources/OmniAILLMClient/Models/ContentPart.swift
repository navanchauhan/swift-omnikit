import Foundation

public struct ContentPart: Codable, Sendable {
    public var kind: String
    public var text: String?
    public var image: ImageData?
    public var audio: AudioData?
    public var document: DocumentData?
    public var toolCall: ToolCallData?
    public var toolResult: ToolResultData?
    public var thinking: ThinkingData?

    public init(
        kind: ContentKind,
        text: String? = nil,
        image: ImageData? = nil,
        audio: AudioData? = nil,
        document: DocumentData? = nil,
        toolCall: ToolCallData? = nil,
        toolResult: ToolResultData? = nil,
        thinking: ThinkingData? = nil
    ) {
        self.kind = kind.rawValue
        self.text = text
        self.image = image
        self.audio = audio
        self.document = document
        self.toolCall = toolCall
        self.toolResult = toolResult
        self.thinking = thinking
    }

    public init(
        kindString: String,
        text: String? = nil,
        image: ImageData? = nil,
        audio: AudioData? = nil,
        document: DocumentData? = nil,
        toolCall: ToolCallData? = nil,
        toolResult: ToolResultData? = nil,
        thinking: ThinkingData? = nil
    ) {
        self.kind = kindString
        self.text = text
        self.image = image
        self.audio = audio
        self.document = document
        self.toolCall = toolCall
        self.toolResult = toolResult
        self.thinking = thinking
    }

    public var contentKind: ContentKind? {
        ContentKind(rawValue: kind)
    }

    // Convenience factory methods
    public static func text(_ text: String) -> ContentPart {
        ContentPart(kind: .text, text: text)
    }

    public static func image(_ imageData: ImageData) -> ContentPart {
        ContentPart(kind: .image, image: imageData)
    }

    public static func toolCall(_ data: ToolCallData) -> ContentPart {
        ContentPart(kind: .toolCall, toolCall: data)
    }

    public static func toolResult(_ data: ToolResultData) -> ContentPart {
        ContentPart(kind: .toolResult, toolResult: data)
    }

    public static func thinking(_ data: ThinkingData) -> ContentPart {
        ContentPart(kind: .thinking, thinking: data)
    }

    public static func redactedThinking(_ data: ThinkingData) -> ContentPart {
        ContentPart(kind: .redactedThinking, thinking: ThinkingData(text: data.text, signature: data.signature, redacted: true))
    }
}
