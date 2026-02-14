import Foundation

// MARK: - generate_object()

public func generateObject(
    model: String,
    prompt: String? = nil,
    messages: [Message]? = nil,
    system: String? = nil,
    schema: [String: Any],
    temperature: Double? = nil,
    topP: Double? = nil,
    maxTokens: Int? = nil,
    reasoningEffort: String? = nil,
    provider: String? = nil,
    providerOptions: [String: [String: AnyCodable]]? = nil,
    maxRetries: Int = 2,
    client: LLMClient? = nil
) async throws -> GenerateResult {
    if prompt != nil && messages != nil {
        throw ConfigurationError(message: "Cannot provide both 'prompt' and 'messages'.")
    }
    if prompt == nil && messages == nil {
        throw ConfigurationError(message: "Must provide either 'prompt' or 'messages'.")
    }

    let activeClient = client ?? getDefaultClient()

    var conversation: [Message] = []
    if let system = system {
        conversation.append(.system(system))
    }

    // Determine provider for strategy selection
    guard let resolvedProvider = provider ?? activeClient.defaultProviderName else {
        throw ConfigurationError(message: "No provider specified and no default provider configured. Set a provider or configure a default provider in the client.")
    }

    if resolvedProvider == "anthropic" {
        // Anthropic: use tool-based extraction
        return try await generateObjectViaToolExtraction(
            model: model,
            prompt: prompt,
            messages: messages,
            system: system,
            schema: schema,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            reasoningEffort: reasoningEffort,
            provider: provider,
            providerOptions: providerOptions,
            maxRetries: maxRetries,
            client: activeClient
        )
    } else {
        // OpenAI and Gemini: native structured output
        return try await generateObjectNative(
            model: model,
            prompt: prompt,
            messages: messages,
            system: system,
            schema: schema,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            reasoningEffort: reasoningEffort,
            provider: provider,
            providerOptions: providerOptions,
            maxRetries: maxRetries,
            client: activeClient
        )
    }
}

// Native structured output (OpenAI json_schema, Gemini responseSchema)
private func generateObjectNative(
    model: String,
    prompt: String?,
    messages: [Message]?,
    system: String?,
    schema: [String: Any],
    temperature: Double?,
    topP: Double?,
    maxTokens: Int?,
    reasoningEffort: String?,
    provider: String?,
    providerOptions: [String: [String: AnyCodable]]?,
    maxRetries: Int,
    client: LLMClient
) async throws -> GenerateResult {
    let result = try await generate(
        model: model,
        prompt: prompt,
        messages: messages,
        system: system,
        responseFormat: .jsonSchema(schema, strict: true),
        temperature: temperature,
        topP: topP,
        maxTokens: maxTokens,
        reasoningEffort: reasoningEffort,
        provider: provider,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        client: client
    )

    guard let data = result.text.data(using: .utf8),
          let parsed = try? JSONSerialization.jsonObject(with: data) else {
        throw NoObjectGeneratedError(message: "Failed to parse structured output as JSON: \(result.text.prefix(200))")
    }

    return GenerateResult(
        text: result.text,
        reasoning: result.reasoning,
        toolCalls: result.toolCalls,
        toolResults: result.toolResults,
        finishReason: result.finishReason,
        usage: result.usage,
        totalUsage: result.totalUsage,
        steps: result.steps,
        response: result.response,
        output: AnyCodable(parsed)
    )
}

// Anthropic: tool-based extraction
private func generateObjectViaToolExtraction(
    model: String,
    prompt: String?,
    messages: [Message]?,
    system: String?,
    schema: [String: Any],
    temperature: Double?,
    topP: Double?,
    maxTokens: Int?,
    reasoningEffort: String?,
    provider: String?,
    providerOptions: [String: [String: AnyCodable]]?,
    maxRetries: Int,
    client: LLMClient
) async throws -> GenerateResult {
    let extractionTool = Tool(
        name: "extract_structured_output",
        description: "Extract the structured data from the input. Call this function with the extracted data matching the schema.",
        parameters: schema
    )

    let systemMsg = (system ?? "") + "\nYou MUST call the extract_structured_output tool with the extracted data. Do not respond with text."

    let result = try await generate(
        model: model,
        prompt: prompt,
        messages: messages,
        system: systemMsg.trimmingCharacters(in: .whitespaces),
        tools: [extractionTool],
        toolChoice: .named("extract_structured_output"),
        maxToolRounds: 0,
        temperature: temperature,
        topP: topP,
        maxTokens: maxTokens,
        reasoningEffort: reasoningEffort,
        provider: provider,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        client: client
    )

    guard let toolCall = result.toolCalls.first else {
        throw NoObjectGeneratedError(message: "Model did not produce a tool call for structured output extraction")
    }

    return GenerateResult(
        text: result.text,
        reasoning: result.reasoning,
        toolCalls: result.toolCalls,
        toolResults: result.toolResults,
        finishReason: result.finishReason,
        usage: result.usage,
        totalUsage: result.totalUsage,
        steps: result.steps,
        response: result.response,
        output: AnyCodable(toolCall.arguments)
    )
}

// MARK: - stream_object() with incremental parsing

/// A stream of partial objects, yielding progressively more complete parsed values
/// as JSON text arrives.
public final class ObjectStreamResult<T>: AsyncSequence, @unchecked Sendable where T: Sendable {
    public typealias Element = T

    private let eventStream: AsyncThrowingStream<T, Error>
    private let underlyingStream: StreamResult

    init(eventStream: AsyncThrowingStream<T, Error>, underlyingStream: StreamResult) {
        self.eventStream = eventStream
        self.underlyingStream = underlyingStream
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var base: AsyncThrowingStream<T, Error>.AsyncIterator

        public mutating func next() async throws -> T? {
            return try await base.next()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: eventStream.makeAsyncIterator())
    }

    /// The underlying StreamResult for accessing the final response.
    public var rawStream: StreamResult { underlyingStream }
}

public func streamObject(
    model: String,
    prompt: String? = nil,
    messages: [Message]? = nil,
    system: String? = nil,
    schema: [String: Any],
    temperature: Double? = nil,
    topP: Double? = nil,
    maxTokens: Int? = nil,
    provider: String? = nil,
    providerOptions: [String: [String: AnyCodable]]? = nil,
    client: LLMClient? = nil
) async throws -> ObjectStreamResult<[String: Any]> {
    let baseStream = try await stream(
        model: model,
        prompt: prompt,
        messages: messages,
        system: system,
        responseFormat: .jsonSchema(schema, strict: true),
        temperature: temperature,
        topP: topP,
        maxTokens: maxTokens,
        provider: provider,
        providerOptions: providerOptions,
        client: client
    )

    let objectStream = AsyncThrowingStream<[String: Any], Error> { continuation in
        let task = Task {
            var accumulated = ""
            var lastParsed: [String: Any]?

            do {
                for try await event in baseStream {
                    if event.eventType == StreamEventType.textDelta, let delta = event.delta {
                        accumulated += delta

                        // Attempt incremental JSON parsing
                        if let data = accumulated.data(using: .utf8),
                           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if !NSDictionary(dictionary: parsed).isEqual(to: lastParsed ?? [:]) {
                                lastParsed = parsed
                                continuation.yield(parsed)
                            }
                        }
                    }
                }

                // Final parse attempt with the complete text
                if let data = accumulated.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if lastParsed == nil || !NSDictionary(dictionary: parsed).isEqual(to: lastParsed!) {
                        continuation.yield(parsed)
                    }
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }

    return ObjectStreamResult(eventStream: objectStream, underlyingStream: baseStream)
}
