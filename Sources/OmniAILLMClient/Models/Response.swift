import Foundation

public struct Response: Sendable {
    public var id: String
    public var model: String
    public var provider: String
    public var message: Message
    public var finishReason: FinishReason
    public var usage: Usage
    public var raw: [String: Any]?
    public var warnings: [Warning]
    public var rateLimit: RateLimitInfo?

    public init(
        id: String,
        model: String,
        provider: String,
        message: Message,
        finishReason: FinishReason,
        usage: Usage,
        raw: [String: Any]? = nil,
        warnings: [Warning] = [],
        rateLimit: RateLimitInfo? = nil
    ) {
        self.id = id
        self.model = model
        self.provider = provider
        self.message = message
        self.finishReason = finishReason
        self.usage = usage
        self.raw = raw
        self.warnings = warnings
        self.rateLimit = rateLimit
    }

    public var text: String { message.text }

    public var toolCalls: [ToolCall] { message.toolCalls }

    public var reasoning: String? { message.reasoning }
}

public struct FinishReason: Sendable {
    public var reason: String
    public var raw: String?

    public init(reason: String, raw: String? = nil) {
        self.reason = reason
        self.raw = raw
    }

    public static let stop = FinishReason(reason: "stop")
    public static let length = FinishReason(reason: "length")
    public static let toolCalls = FinishReason(reason: "tool_calls")
    public static let contentFilter = FinishReason(reason: "content_filter")
    public static let error = FinishReason(reason: "error")
    public static let other = FinishReason(reason: "other")
}

public struct Usage: Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int
    public var reasoningTokens: Int?
    public var cacheReadTokens: Int?
    public var cacheWriteTokens: Int?
    public var raw: [String: Any]?

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        totalTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        raw: [String: Any]? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens ?? (inputTokens + outputTokens)
        self.reasoningTokens = reasoningTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.raw = raw
    }

    public static func + (lhs: Usage, rhs: Usage) -> Usage {
        Usage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens,
            reasoningTokens: Self.addOptional(lhs.reasoningTokens, rhs.reasoningTokens),
            cacheReadTokens: Self.addOptional(lhs.cacheReadTokens, rhs.cacheReadTokens),
            cacheWriteTokens: Self.addOptional(lhs.cacheWriteTokens, rhs.cacheWriteTokens),
            raw: nil
        )
    }

    private static func addOptional(_ a: Int?, _ b: Int?) -> Int? {
        if a == nil && b == nil { return nil }
        return (a ?? 0) + (b ?? 0)
    }

    public static let zero = Usage()
}

public struct Warning: Sendable {
    public var message: String
    public var code: String?

    public init(message: String, code: String? = nil) {
        self.message = message
        self.code = code
    }
}

public struct RateLimitInfo: Sendable {
    public var requestsRemaining: Int?
    public var requestsLimit: Int?
    public var tokensRemaining: Int?
    public var tokensLimit: Int?
    public var resetAt: Date?

    public init(
        requestsRemaining: Int? = nil,
        requestsLimit: Int? = nil,
        tokensRemaining: Int? = nil,
        tokensLimit: Int? = nil,
        resetAt: Date? = nil
    ) {
        self.requestsRemaining = requestsRemaining
        self.requestsLimit = requestsLimit
        self.tokensRemaining = tokensRemaining
        self.tokensLimit = tokensLimit
        self.resetAt = resetAt
    }
}
