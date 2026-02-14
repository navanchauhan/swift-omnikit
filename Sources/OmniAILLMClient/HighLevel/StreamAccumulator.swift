import Foundation

public final class StreamAccumulator: @unchecked Sendable {
    private var textParts: [String: String] = [:]  // textId -> accumulated text
    private var reasoningText: String = ""
    private var toolCalls: [String: ToolCall] = [:]  // callId -> accumulated tool call
    private var toolCallArgBuffers: [String: String] = [:]  // callId -> partial args JSON
    private var finishReason: FinishReason?
    private var usage: Usage?
    private var responseId: String = ""
    private var model: String = ""
    private var provider: String = ""
    private var warnings: [Warning] = []
    private var raw: [String: Any]?
    private var currentTextId: String?

    public init() {}

    public func process(_ event: StreamEvent) {
        guard let eventType = event.eventType else { return }

        switch eventType {
        case .streamStart:
            break

        case .textStart:
            let textId = event.textId ?? "default"
            textParts[textId] = ""
            currentTextId = textId

        case .textDelta:
            let textId = event.textId ?? currentTextId ?? "default"
            if textParts[textId] == nil {
                textParts[textId] = ""
            }
            textParts[textId]! += event.delta ?? ""

        case .textEnd:
            break

        case .reasoningStart:
            break

        case .reasoningDelta:
            reasoningText += event.reasoningDelta ?? ""

        case .reasoningEnd:
            break

        case .toolCallStart:
            if let tc = event.toolCall {
                toolCalls[tc.id] = tc
                toolCallArgBuffers[tc.id] = ""
            }

        case .toolCallDelta:
            if let tc = event.toolCall {
                toolCallArgBuffers[tc.id, default: ""] += tc.rawArguments ?? ""
            }

        case .toolCallEnd:
            if let tc = event.toolCall {
                toolCalls[tc.id] = tc
                toolCallArgBuffers.removeValue(forKey: tc.id)
            }

        case .finish:
            finishReason = event.finishReason
            usage = event.usage
            if let resp = event.response {
                responseId = resp.id
                model = resp.model
                provider = resp.provider
                raw = resp.raw
            }

        case .error, .providerEvent, .stepFinish:
            break
        }
    }

    public func response() -> Response {
        let allText = textParts.sorted(by: { $0.key < $1.key }).map { $0.value }.joined()
        var contentParts: [ContentPart] = []

        if !reasoningText.isEmpty {
            contentParts.append(.thinking(ThinkingData(text: reasoningText)))
        }

        if !allText.isEmpty {
            contentParts.append(.text(allText))
        }

        for tc in toolCalls.values.sorted(by: { $0.id < $1.id }) {
            contentParts.append(.toolCall(ToolCallData(
                id: tc.id,
                name: tc.name,
                arguments: AnyCodable(tc.arguments)
            )))
        }

        let message = Message(role: .assistant, content: contentParts)

        return Response(
            id: responseId,
            model: model,
            provider: provider,
            message: message,
            finishReason: finishReason ?? .stop,
            usage: usage ?? .zero,
            raw: raw,
            warnings: warnings
        )
    }
}
