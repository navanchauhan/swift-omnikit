import Foundation

public struct StreamAccumulator: Sendable {
    private var textOrder: [String] = []
    private var textById: [String: String] = [:]

    private var toolCallOrder: [String] = []
    private var toolCallById: [String: ToolCall] = [:]

    private var reasoning: String = ""

    private var finishReason: FinishReason?
    private var usage: Usage?
    private var finalResponse: Response?

    public init() {}

    public mutating func process(_ event: StreamEvent) {
        if let response = event.response, event.type.rawValue == StreamEventType.finish.rawValue {
            finalResponse = response
            finishReason = event.finishReason ?? response.finishReason
            usage = event.usage ?? response.usage
            return
        }

        switch event.type.rawValue {
        case StreamEventType.textStart.rawValue:
            let id = event.textId ?? "text_0"
            if textById[id] == nil {
                textOrder.append(id)
                textById[id] = ""
            }
        case StreamEventType.textDelta.rawValue:
            let id = event.textId ?? "text_0"
            if textById[id] == nil {
                textOrder.append(id)
                textById[id] = ""
            }
            textById[id, default: ""].append(event.delta ?? "")
        case StreamEventType.reasoningDelta.rawValue:
            reasoning.append(event.reasoningDelta ?? "")
        case StreamEventType.toolCallStart.rawValue, StreamEventType.toolCallDelta.rawValue, StreamEventType.toolCallEnd.rawValue:
            if let call = event.toolCall {
                if toolCallById[call.id] == nil {
                    toolCallOrder.append(call.id)
                }
                toolCallById[call.id] = call
            }
        case StreamEventType.finish.rawValue:
            finishReason = event.finishReason
            usage = event.usage
        default:
            break
        }
    }

    public func response() -> Response? {
        if let finalResponse { return finalResponse }

        let text = textOrder.compactMap { textById[$0] }.joined()
        var parts: [ContentPart] = []
        if !text.isEmpty {
            parts.append(.text(text))
        }
        for id in toolCallOrder {
            if let call = toolCallById[id] {
                parts.append(.toolCall(call))
            }
        }
        if !reasoning.isEmpty {
            parts.append(.thinking(ThinkingData(text: reasoning, signature: nil, redacted: false)))
        }

        guard let finishReason, let usage else {
            return nil
        }

        return Response(
            id: "accumulated",
            model: "unknown",
            provider: "unknown",
            message: Message(role: .assistant, content: parts),
            finishReason: finishReason,
            usage: usage,
            raw: nil,
            warnings: [],
            rateLimit: nil
        )
    }
}

