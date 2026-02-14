import Foundation

public enum StreamEventType: String, Sendable {
    case streamStart = "stream_start"
    case textStart = "text_start"
    case textDelta = "text_delta"
    case textEnd = "text_end"
    case reasoningStart = "reasoning_start"
    case reasoningDelta = "reasoning_delta"
    case reasoningEnd = "reasoning_end"
    case toolCallStart = "tool_call_start"
    case toolCallDelta = "tool_call_delta"
    case toolCallEnd = "tool_call_end"
    case stepFinish = "step_finish"
    case finish = "finish"
    case error = "error"
    case providerEvent = "provider_event"
}

public struct StreamEvent: Sendable {
    public var type: String

    // text events
    public var delta: String?
    public var textId: String?

    // reasoning events
    public var reasoningDelta: String?

    // tool call events
    public var toolCall: ToolCall?

    // finish event
    public var finishReason: FinishReason?
    public var usage: Usage?
    public var response: Response?

    // error event
    public var error: SDKError?

    // passthrough
    public var raw: [String: Any]?

    public init(
        type: StreamEventType,
        delta: String? = nil,
        textId: String? = nil,
        reasoningDelta: String? = nil,
        toolCall: ToolCall? = nil,
        finishReason: FinishReason? = nil,
        usage: Usage? = nil,
        response: Response? = nil,
        error: SDKError? = nil,
        raw: [String: Any]? = nil
    ) {
        self.type = type.rawValue
        self.delta = delta
        self.textId = textId
        self.reasoningDelta = reasoningDelta
        self.toolCall = toolCall
        self.finishReason = finishReason
        self.usage = usage
        self.response = response
        self.error = error
        self.raw = raw
    }

    public init(
        typeString: String,
        delta: String? = nil,
        textId: String? = nil,
        reasoningDelta: String? = nil,
        toolCall: ToolCall? = nil,
        finishReason: FinishReason? = nil,
        usage: Usage? = nil,
        response: Response? = nil,
        error: SDKError? = nil,
        raw: [String: Any]? = nil
    ) {
        self.type = typeString
        self.delta = delta
        self.textId = textId
        self.reasoningDelta = reasoningDelta
        self.toolCall = toolCall
        self.finishReason = finishReason
        self.usage = usage
        self.response = response
        self.error = error
        self.raw = raw
    }

    public var eventType: StreamEventType? {
        StreamEventType(rawValue: type)
    }
}
