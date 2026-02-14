import Foundation

// MARK: - StreamResult

public final class StreamResult: AsyncSequence, @unchecked Sendable {
    public typealias Element = StreamEvent

    private let eventStream: AsyncThrowingStream<StreamEvent, Error>
    private let accumulator = StreamAccumulator()
    private var _response: Response?
    private var _partialResponse: Response?
    private let lock = NSLock()

    init(eventStream: AsyncThrowingStream<StreamEvent, Error>) {
        self.eventStream = eventStream
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var base: AsyncThrowingStream<StreamEvent, Error>.AsyncIterator
        let accumulator: StreamAccumulator
        let onEvent: (StreamEvent) -> Void

        public mutating func next() async throws -> StreamEvent? {
            guard let event = try await base.next() else { return nil }
            accumulator.process(event)
            onEvent(event)
            return event
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            base: eventStream.makeAsyncIterator(),
            accumulator: accumulator,
            onEvent: { [weak self] event in
                guard let self = self else { return }
                self.lock.lock()
                if event.eventType == StreamEventType.finish {
                    self._response = event.response ?? self.accumulator.response()
                }
                self._partialResponse = self.accumulator.response()
                self.lock.unlock()
            }
        )
    }

    public func response() -> Response {
        lock.lock()
        defer { lock.unlock() }
        return _response ?? accumulator.response()
    }

    public var partialResponse: Response? {
        lock.lock()
        defer { lock.unlock() }
        return _partialResponse
    }

    public var textStream: AsyncTextStream {
        AsyncTextStream(source: self)
    }
}

// MARK: - AsyncTextStream

public struct AsyncTextStream: AsyncSequence, Sendable {
    public typealias Element = String

    let source: StreamResult

    public struct AsyncIterator: AsyncIteratorProtocol {
        var base: StreamResult.AsyncIterator

        public mutating func next() async throws -> String? {
            while let event = try await base.next() {
                if event.eventType == StreamEventType.textDelta, let delta = event.delta {
                    return delta
                }
            }
            return nil
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: source.makeAsyncIterator())
    }
}

// MARK: - stream()

public func stream(
    model: String,
    prompt: String? = nil,
    messages: [Message]? = nil,
    system: String? = nil,
    tools: [Tool]? = nil,
    toolChoice: ToolChoice? = nil,
    maxToolRounds: Int = 1,
    stopWhen: StopCondition? = nil,
    responseFormat: ResponseFormat? = nil,
    temperature: Double? = nil,
    topP: Double? = nil,
    maxTokens: Int? = nil,
    stopSequences: [String]? = nil,
    reasoningEffort: String? = nil,
    provider: String? = nil,
    providerOptions: [String: [String: AnyCodable]]? = nil,
    timeout: TimeoutConfig? = nil,
    client: LLMClient? = nil
) async throws -> StreamResult {
    if prompt != nil && messages != nil {
        throw ConfigurationError(message: "Cannot provide both 'prompt' and 'messages'.")
    }
    if prompt == nil && messages == nil {
        throw ConfigurationError(message: "Must provide either 'prompt' or 'messages'.")
    }

    let activeClient = client ?? getDefaultClient()

    // Check cancellation early
    try Task.checkCancellation()

    var conversation: [Message] = []
    if let system = system {
        conversation.append(.system(system))
    }
    if let prompt = prompt {
        conversation.append(.user(prompt))
    } else if let messages = messages {
        conversation.append(contentsOf: messages)
    }

    let toolDefs = tools?.map { $0.definition }
    let effectiveToolChoice = tools != nil ? (toolChoice ?? .auto) : nil
    let activeTools = tools?.filter { $0.isActive } ?? []
    let hasActiveTools = !activeTools.isEmpty

    let totalDeadline: ContinuousClock.Instant?
    if let totalTimeout = timeout?.total {
        totalDeadline = .now + .seconds(totalTimeout)
    } else {
        totalDeadline = nil
    }

    if !hasActiveTools || maxToolRounds == 0 {
        // Simple case: no tool loop needed
        let request = Request(
            model: model,
            messages: conversation,
            provider: provider,
            tools: toolDefs,
            toolChoice: effectiveToolChoice,
            responseFormat: responseFormat,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            stopSequences: stopSequences,
            reasoningEffort: reasoningEffort,
            providerOptions: providerOptions
        )

        let eventStream = try await withStepTimeout(perStep: timeout?.perStep, totalDeadline: totalDeadline) {
            try await activeClient.stream(request: request)
        }
        if let deadline = totalDeadline {
            return StreamResult(eventStream: wrapStreamWithTimeout(eventStream, deadline: deadline))
        }
        return StreamResult(eventStream: eventStream)
    }

    // Complex case: streaming with tool loop
    let capturedDeadline = totalDeadline
    let capturedPerStep = timeout?.perStep
    let wrappedStream = AsyncThrowingStream<StreamEvent, Error> { continuation in
        let task = Task {
            do {
                var currentConversation = conversation
                for round in 0...maxToolRounds {
                    try Task.checkCancellation()

                    // Check total timeout
                    if let deadline = capturedDeadline, ContinuousClock.now >= deadline {
                        throw RequestTimeoutError(message: "Total stream timeout exceeded")
                    }

                    let request = Request(
                        model: model,
                        messages: currentConversation,
                        provider: provider,
                        tools: toolDefs,
                        toolChoice: effectiveToolChoice,
                        responseFormat: responseFormat,
                        temperature: temperature,
                        topP: topP,
                        maxTokens: maxTokens,
                        stopSequences: stopSequences,
                        reasoningEffort: reasoningEffort,
                        providerOptions: providerOptions
                    )

                    let eventStream = try await withStepTimeout(perStep: capturedPerStep, totalDeadline: capturedDeadline) {
                        try await activeClient.stream(request: request)
                    }
                    let acc = StreamAccumulator()

                    for try await event in eventStream {
                        try Task.checkCancellation()
                        if let deadline = capturedDeadline, ContinuousClock.now >= deadline {
                            throw RequestTimeoutError(message: "Total stream timeout exceeded")
                        }
                        acc.process(event)
                        continuation.yield(event)
                    }

                    let response = acc.response()
                    let responseTCs = response.toolCalls

                    if responseTCs.isEmpty || response.finishReason.reason != "tool_calls" {
                        break
                    }
                    if round >= maxToolRounds {
                        break
                    }

                    // Execute tools
                    let toolResults = await executeTools(tools: activeTools, calls: responseTCs)

                    continuation.yield(StreamEvent(type: .stepFinish))

                    // Continue conversation
                    currentConversation.append(response.message)
                    for result in toolResults {
                        currentConversation.append(Message.toolResult(
                            toolCallId: result.toolCallId,
                            content: result.contentString,
                            isError: result.isError
                        ))
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }

    return StreamResult(eventStream: wrappedStream)
}

/// Wraps an event stream with a total deadline. If the deadline is exceeded,
/// a RequestTimeoutError is thrown.
private func wrapStreamWithTimeout(
    _ source: AsyncThrowingStream<StreamEvent, Error>,
    deadline: ContinuousClock.Instant
) -> AsyncThrowingStream<StreamEvent, Error> {
    AsyncThrowingStream<StreamEvent, Error> { continuation in
        let task = Task {
            do {
                for try await event in source {
                    try Task.checkCancellation()
                    if ContinuousClock.now >= deadline {
                        throw RequestTimeoutError(message: "Total stream timeout exceeded")
                    }
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
