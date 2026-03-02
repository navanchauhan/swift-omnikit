import Foundation

public enum EventKind: String, Sendable {
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case userInput = "user_input"
    case assistantTextStart = "assistant_text_start"
    case assistantTextDelta = "assistant_text_delta"
    case assistantTextEnd = "assistant_text_end"
    case toolCallStart = "tool_call_start"
    case toolCallOutputDelta = "tool_call_output_delta"
    case toolCallEnd = "tool_call_end"
    case steeringInjected = "steering_injected"
    case turnLimit = "turn_limit"
    case loopDetection = "loop_detection"
    case warning = "warning"
    case error = "error"
}

public struct SessionEvent: Sendable {
    public var kind: EventKind
    public var timestamp: Date
    public var sessionId: String
    public var data: [String: String]

    public init(kind: EventKind, sessionId: String, data: [String: String] = [:]) {
        self.kind = kind
        self.timestamp = Date()
        self.sessionId = sessionId
        self.data = data
    }
}

public actor EventEmitter {
    private var handlers: [@Sendable (SessionEvent) -> Void] = []
    private var eventBuffer: [SessionEvent] = []
    private var continuations: [AsyncStream<SessionEvent>.Continuation] = []

    public init() {}

    public func on(_ handler: @escaping @Sendable (SessionEvent) -> Void) {
        handlers.append(handler)
    }

    public func emit(_ event: SessionEvent) {
        for handler in handlers {
            handler(event)
        }
        for continuation in continuations {
            continuation.yield(event)
        }
        eventBuffer.append(event)
    }

    public func events() -> AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            Task { [weak self] in
                await self?.addContinuation(continuation)
            }
        }
    }

    private func addContinuation(_ continuation: AsyncStream<SessionEvent>.Continuation) {
        continuations.append(continuation)
    }

    public func flush() {
        for continuation in continuations {
            continuation.finish()
        }
    }

    public func allEvents() -> [SessionEvent] {
        eventBuffer
    }
}
