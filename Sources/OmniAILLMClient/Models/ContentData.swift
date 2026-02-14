import Foundation

public struct ImageData: Codable, Sendable {
    public var url: String?
    public var data: Data?
    public var mediaType: String?
    public var detail: String?

    public init(url: String? = nil, data: Data? = nil, mediaType: String? = nil, detail: String? = nil) {
        self.url = url
        self.data = data
        self.mediaType = mediaType
        self.detail = detail
    }
}

public struct AudioData: Codable, Sendable {
    public var url: String?
    public var data: Data?
    public var mediaType: String?

    public init(url: String? = nil, data: Data? = nil, mediaType: String? = nil) {
        self.url = url
        self.data = data
        self.mediaType = mediaType
    }
}

public struct DocumentData: Codable, Sendable {
    public var url: String?
    public var data: Data?
    public var mediaType: String?
    public var fileName: String?

    public init(url: String? = nil, data: Data? = nil, mediaType: String? = nil, fileName: String? = nil) {
        self.url = url
        self.data = data
        self.mediaType = mediaType
        self.fileName = fileName
    }
}

public struct ToolCallData: Codable, Sendable {
    public var id: String
    public var name: String
    public var arguments: AnyCodable
    public var type: String

    public init(id: String, name: String, arguments: AnyCodable, type: String = "function") {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.type = type
    }
}

public struct ToolResultData: Codable, Sendable {
    public var toolCallId: String
    public var content: AnyCodable
    public var isError: Bool
    public var imageData: Data?
    public var imageMediaType: String?

    public init(toolCallId: String, content: AnyCodable, isError: Bool = false, imageData: Data? = nil, imageMediaType: String? = nil) {
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
        self.imageData = imageData
        self.imageMediaType = imageMediaType
    }
}

public struct ThinkingData: Codable, Sendable {
    public var text: String
    public var signature: String?
    public var redacted: Bool

    public init(text: String, signature: String? = nil, redacted: Bool = false) {
        self.text = text
        self.signature = signature
        self.redacted = redacted
    }
}
