import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - AnthropicAdapter

/// Provider adapter for the Anthropic Messages API (/v1/messages).
///
/// Translates unified LLMKit requests into Anthropic's native wire format and
/// maps responses (both synchronous and streaming) back to the unified types.
public final class AnthropicAdapter: ProviderAdapter, @unchecked Sendable {

    // MARK: - Properties

    public let name = "anthropic"

    private let apiKey: String
    private let baseURL: String
    private let defaultMaxTokens: Int
    private let httpClient: HTTPClient

    private static let apiVersion = "2023-06-01"
    private static let cachingBetaHeader = "prompt-caching-2024-07-31"

    // MARK: - Initialisation

    public init(
        apiKey: String,
        baseURL: String? = nil,
        timeout: AdapterTimeout = .default,
        defaultMaxTokens: Int = 4096
    ) {
        self.apiKey = apiKey
        self.baseURL = (baseURL ?? "https://api.anthropic.com").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.defaultMaxTokens = defaultMaxTokens
        self.httpClient = HTTPClient(timeout: timeout)
    }

    // MARK: - ProviderAdapter conformance

    public func complete(request: Request) async throws -> Response {
        let (body, headers) = try buildRequestBody(request: request, stream: false)
        let url = try makeURL()
        let httpResponse = try await httpClient.post(url: url, body: body, headers: headers)

        if httpResponse.statusCode != 200 {
            throw mapError(data: httpResponse.data, statusCode: httpResponse.statusCode, headers: httpResponse.headers)
        }

        guard let json = try? JSONSerialization.jsonObject(with: httpResponse.data) as? [String: Any] else {
            throw ProviderError(message: "Failed to parse Anthropic response", provider: name, statusCode: httpResponse.statusCode)
        }

        let rateLimit = HTTPClient.parseRateLimitInfo(headers: httpResponse.headers)
        return try parseResponse(json: json, rateLimit: rateLimit)
    }

    public func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let (body, headers) = try buildRequestBody(request: request, stream: true)
        let url = try makeURL()
        let (byteStream, httpResponse) = try await httpClient.postStream(url: url, body: body, headers: headers)

        if httpResponse.statusCode != 200 {
            // Read the error body from the stream
            var errorData = Data()
            for try await byte in byteStream {
                errorData.append(byte)
            }
            throw mapError(data: errorData, statusCode: httpResponse.statusCode, headers: parseHeaders(httpResponse))
        }

        let sseStream = SSEParser.parse(stream: byteStream)
        let providerName = self.name

        return AsyncThrowingStream { continuation in
            let task = Task {
                // Mutable state tracked across SSE events
                var messageId = ""
                var modelName = ""
                var inputTokens = 0
                var outputTokens = 0
                var cacheReadTokens: Int?
                var cacheWriteTokens: Int?

                // Content block tracking
                var currentBlockIndex = -1
                var currentBlockType = ""
                var currentToolCallId = ""
                var currentToolCallName = ""
                var currentToolCallArgs = ""
                var currentThinkingText = ""
                var currentThinkingSignature = ""

                // Accumulated content for the final response
                var accumulatedText = ""
                var contentParts: [ContentPart] = []
                var finishReason: FinishReason = .stop

                do {
                    for try await sseEvent in sseStream {
                        // Anthropic uses the event field to distinguish SSE event types
                        let eventType = sseEvent.event ?? ""
                        let data = sseEvent.data

                        if data == "[DONE]" {
                            continue
                        }

                        guard let eventJSON = parseJSON(data) else {
                            continue
                        }

                        switch eventType {
                        case "message_start":
                            if let message = eventJSON["message"] as? [String: Any] {
                                messageId = message["id"] as? String ?? ""
                                modelName = message["model"] as? String ?? ""
                                if let usage = message["usage"] as? [String: Any] {
                                    inputTokens = usage["input_tokens"] as? Int ?? 0
                                    cacheReadTokens = usage["cache_read_input_tokens"] as? Int
                                    cacheWriteTokens = usage["cache_creation_input_tokens"] as? Int
                                }
                            }
                            continuation.yield(StreamEvent(
                                type: .streamStart,
                                raw: eventJSON
                            ))

                        case "content_block_start":
                            currentBlockIndex = eventJSON["index"] as? Int ?? currentBlockIndex + 1
                            if let block = eventJSON["content_block"] as? [String: Any] {
                                let blockType = block["type"] as? String ?? ""
                                currentBlockType = blockType

                                switch blockType {
                                case "text":
                                    continuation.yield(StreamEvent(
                                        type: .textStart,
                                        raw: eventJSON
                                    ))

                                case "tool_use":
                                    currentToolCallId = block["id"] as? String ?? ""
                                    currentToolCallName = block["name"] as? String ?? ""
                                    currentToolCallArgs = ""
                                    continuation.yield(StreamEvent(
                                        type: .toolCallStart,
                                        toolCall: ToolCall(
                                            id: currentToolCallId,
                                            name: currentToolCallName,
                                            arguments: [:]
                                        ),
                                        raw: eventJSON
                                    ))

                                case "thinking":
                                    currentThinkingText = ""
                                    currentThinkingSignature = ""
                                    continuation.yield(StreamEvent(
                                        type: .reasoningStart,
                                        raw: eventJSON
                                    ))

                                default:
                                    continuation.yield(StreamEvent(
                                        type: .providerEvent,
                                        raw: eventJSON
                                    ))
                                }
                            }

                        case "content_block_delta":
                            if let delta = eventJSON["delta"] as? [String: Any] {
                                let deltaType = delta["type"] as? String ?? ""

                                switch deltaType {
                                case "text_delta":
                                    let text = delta["text"] as? String ?? ""
                                    accumulatedText += text
                                    continuation.yield(StreamEvent(
                                        type: .textDelta,
                                        delta: text,
                                        raw: eventJSON
                                    ))

                                case "input_json_delta":
                                    let partial = delta["partial_json"] as? String ?? ""
                                    currentToolCallArgs += partial
                                    continuation.yield(StreamEvent(
                                        type: .toolCallDelta,
                                        toolCall: ToolCall(
                                            id: currentToolCallId,
                                            name: currentToolCallName,
                                            arguments: [:],
                                            rawArguments: partial
                                        ),
                                        raw: eventJSON
                                    ))

                                case "thinking_delta":
                                    let thinking = delta["thinking"] as? String ?? ""
                                    currentThinkingText += thinking
                                    continuation.yield(StreamEvent(
                                        type: .reasoningDelta,
                                        reasoningDelta: thinking,
                                        raw: eventJSON
                                    ))

                                case "signature_delta":
                                    let sig = delta["signature"] as? String ?? ""
                                    currentThinkingSignature += sig

                                default:
                                    continuation.yield(StreamEvent(
                                        type: .providerEvent,
                                        raw: eventJSON
                                    ))
                                }
                            }

                        case "content_block_stop":
                            switch currentBlockType {
                            case "text":
                                contentParts.append(.text(accumulatedText))
                                continuation.yield(StreamEvent(
                                    type: .textEnd,
                                    raw: eventJSON
                                ))

                            case "tool_use":
                                let args = Self.parseToolArguments(currentToolCallArgs)
                                contentParts.append(.toolCall(ToolCallData(
                                    id: currentToolCallId,
                                    name: currentToolCallName,
                                    arguments: AnyCodable(args)
                                )))
                                continuation.yield(StreamEvent(
                                    type: .toolCallEnd,
                                    toolCall: ToolCall(
                                        id: currentToolCallId,
                                        name: currentToolCallName,
                                        arguments: args,
                                        rawArguments: currentToolCallArgs
                                    ),
                                    raw: eventJSON
                                ))
                                currentToolCallId = ""
                                currentToolCallName = ""
                                currentToolCallArgs = ""

                            case "thinking":
                                if !currentThinkingText.isEmpty || !currentThinkingSignature.isEmpty {
                                    contentParts.append(.thinking(ThinkingData(
                                        text: currentThinkingText,
                                        signature: currentThinkingSignature.isEmpty ? nil : currentThinkingSignature,
                                        redacted: false
                                    )))
                                }
                                continuation.yield(StreamEvent(
                                    type: .reasoningEnd,
                                    raw: eventJSON
                                ))
                                currentThinkingText = ""
                                currentThinkingSignature = ""

                            default:
                                continuation.yield(StreamEvent(
                                    type: .providerEvent,
                                    raw: eventJSON
                                ))
                            }
                            currentBlockType = ""

                        case "message_delta":
                            if let delta = eventJSON["delta"] as? [String: Any] {
                                if let stopReason = delta["stop_reason"] as? String {
                                    finishReason = Self.mapFinishReason(stopReason)
                                }
                            }
                            if let usage = eventJSON["usage"] as? [String: Any] {
                                outputTokens = usage["output_tokens"] as? Int ?? outputTokens
                            }

                        case "message_stop":
                            let usage = Usage(
                                inputTokens: inputTokens,
                                outputTokens: outputTokens,
                                cacheReadTokens: cacheReadTokens,
                                cacheWriteTokens: cacheWriteTokens,
                                raw: [
                                    "input_tokens": inputTokens,
                                    "output_tokens": outputTokens
                                ]
                            )

                            let message = Message(role: .assistant, content: contentParts)
                            let response = Response(
                                id: messageId,
                                model: modelName,
                                provider: providerName,
                                message: message,
                                finishReason: finishReason,
                                usage: usage
                            )

                            continuation.yield(StreamEvent(
                                type: .finish,
                                finishReason: finishReason,
                                usage: usage,
                                response: response,
                                raw: eventJSON
                            ))

                        case "ping":
                            // Keep-alive, ignore
                            break

                        case "error":
                            let errorObj = eventJSON["error"] as? [String: Any]
                            let errorMessage = errorObj?["message"] as? String ?? "Stream error"
                            let errorType = errorObj?["type"] as? String
                            continuation.yield(StreamEvent(
                                type: .error,
                                error: ProviderError(
                                    message: errorMessage,
                                    provider: providerName,
                                    errorCode: errorType,
                                    raw: eventJSON
                                ),
                                raw: eventJSON
                            ))

                        default:
                            // Unknown event type, pass through
                            continuation.yield(StreamEvent(
                                type: .providerEvent,
                                raw: eventJSON
                            ))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - URL construction

    private func makeURL() throws -> URL {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw ConfigurationError(message: "Invalid Anthropic base URL: \(baseURL)")
        }
        return url
    }

    // MARK: - Request building

    private func buildRequestBody(request: Request, stream: Bool) throws -> (Data, [String: String]) {
        let anthropicOptions = request.providerOptions?["anthropic"]

        // Determine auto-caching behaviour
        let autoCacheDisabled: Bool = {
            if let val = anthropicOptions?["auto_cache"] {
                if let b = val.boolValue { return !b }
                if let s = val.stringValue { return s == "false" }
            }
            return false
        }()
        let autoCache = !autoCacheDisabled

        // ---- Extract system messages ----
        var systemBlocks: [[String: Any]] = []
        var conversationMessages: [Message] = []

        for msg in request.messages {
            switch msg.role {
            case .system, .developer:
                for part in msg.content {
                    if let text = part.text {
                        systemBlocks.append(["type": "text", "text": text])
                    }
                }
            default:
                conversationMessages.append(msg)
            }
        }

        // Inject cache_control on the last system block
        if autoCache && !systemBlocks.isEmpty {
            systemBlocks[systemBlocks.count - 1]["cache_control"] = ["type": "ephemeral"]
        }

        // ---- Translate conversation messages ----
        // Anthropic requires strict user/assistant alternation.
        // Tool results must be sent as user messages.
        var translatedMessages: [[String: Any]] = []

        for msg in conversationMessages {
            let role: String
            var contentBlocks: [[String: Any]] = []

            switch msg.role {
            case .assistant:
                role = "assistant"
                for part in msg.content {
                    if let block = translateContentPart(part) {
                        contentBlocks.append(block)
                    }
                }
            case .user:
                role = "user"
                for part in msg.content {
                    if let block = translateContentPart(part) {
                        contentBlocks.append(block)
                    }
                }
            case .tool:
                // Tool results are sent inside user messages
                role = "user"
                for part in msg.content {
                    if let tr = part.toolResult {
                        var block: [String: Any] = [
                            "type": "tool_result",
                            "tool_use_id": tr.toolCallId
                        ]
                        // Content can be string or structured
                        if let s = tr.content.stringValue {
                            block["content"] = s
                        } else if let arr = tr.content.arrayValue {
                            block["content"] = arr
                        } else if let dict = tr.content.dictValue {
                            // Wrap dict in a text block
                            if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                               let jsonStr = String(data: jsonData, encoding: .utf8) {
                                block["content"] = jsonStr
                            }
                        } else {
                            block["content"] = tr.content.description
                        }
                        if tr.isError {
                            block["is_error"] = true
                        }
                        contentBlocks.append(block)
                    } else if let block = translateContentPart(part) {
                        contentBlocks.append(block)
                    }
                }
            default:
                continue
            }

            guard !contentBlocks.isEmpty else { continue }

            // Enforce user/assistant alternation: merge consecutive same-role messages
            if let last = translatedMessages.last,
               let lastRole = last["role"] as? String,
               lastRole == role {
                var merged = last
                var existing = merged["content"] as? [[String: Any]] ?? []
                existing.append(contentsOf: contentBlocks)
                merged["content"] = existing
                translatedMessages[translatedMessages.count - 1] = merged
            } else {
                translatedMessages.append([
                    "role": role,
                    "content": contentBlocks
                ])
            }
        }

        // Inject cache_control on the second-to-last user message (conversation prefix caching)
        if autoCache {
            injectCacheOnPenultimateUserMessage(&translatedMessages)
        }

        // ---- Build the request body ----
        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens ?? defaultMaxTokens,
            "messages": translatedMessages
        ]

        if !systemBlocks.isEmpty {
            body["system"] = systemBlocks
        }

        if stream {
            body["stream"] = true
        }

        if let temp = request.temperature {
            body["temperature"] = temp
        }

        if let topP = request.topP {
            body["top_p"] = topP
        }

        if let stop = request.stopSequences, !stop.isEmpty {
            body["stop_sequences"] = stop
        }

        // ---- Tools ----
        var needsCachingBeta = autoCache && !systemBlocks.isEmpty
        if let tools = request.tools, !tools.isEmpty {
            if let tc = request.toolChoice {
                switch tc.mode {
                case "none":
                    // Omit tools entirely when tool_choice is none
                    break
                default:
                    let toolDefs = buildToolDefinitions(tools, autoCache: autoCache)
                    body["tools"] = toolDefs
                    body["tool_choice"] = mapToolChoice(tc)
                    if autoCache { needsCachingBeta = true }
                }
            } else {
                let toolDefs = buildToolDefinitions(tools, autoCache: autoCache)
                body["tools"] = toolDefs
                if autoCache { needsCachingBeta = true }
            }
        }

        // ---- Extended thinking ----
        if let thinking = anthropicOptions?["thinking"] {
            if let thinkingDict = thinking.dictValue {
                body["thinking"] = thinkingDict
            }
        }

        // ---- Metadata ----
        if let metadata = request.metadata, !metadata.isEmpty {
            body["metadata"] = metadata
        }

        // ---- Headers ----
        var headers: [String: String] = [
            "x-api-key": apiKey,
            "anthropic-version": Self.apiVersion
        ]

        // Beta headers
        var betaHeaders: [String] = []
        if needsCachingBeta {
            betaHeaders.append(Self.cachingBetaHeader)
        }
        if let extraBeta = anthropicOptions?["beta_headers"] {
            if let s = extraBeta.stringValue {
                betaHeaders.append(contentsOf: s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            } else if let arr = extraBeta.arrayValue {
                betaHeaders.append(contentsOf: arr.compactMap { $0 as? String })
            }
        }
        // Deduplicate
        let uniqueBetas = Array(Set(betaHeaders))
        if !uniqueBetas.isEmpty {
            headers["anthropic-beta"] = uniqueBetas.joined(separator: ",")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        return (jsonData, headers)
    }

    // MARK: - Content part translation

    private func translateContentPart(_ part: ContentPart) -> [String: Any]? {
        guard let kind = part.contentKind else { return nil }

        switch kind {
        case .text:
            guard let text = part.text else { return nil }
            return ["type": "text", "text": text]

        case .image:
            guard let img = part.image else { return nil }
            if let url = img.url {
                if isLocalFilePath(url), let inlined = inlineLocalFile(url) {
                    return [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": inlined.mimeType,
                            "data": inlined.data.base64EncodedString()
                        ]
                    ]
                }
                return [
                    "type": "image",
                    "source": [
                        "type": "url",
                        "url": url
                    ]
                ]
            } else if let data = img.data {
                return [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": img.mediaType ?? "image/png",
                        "data": data.base64EncodedString()
                    ]
                ]
            }
            return nil

        case .document:
            guard let doc = part.document else { return nil }
            if let data = doc.data {
                return [
                    "type": "document",
                    "source": [
                        "type": "base64",
                        "media_type": doc.mediaType ?? "application/pdf",
                        "data": data.base64EncodedString()
                    ]
                ]
            } else if let url = doc.url {
                return [
                    "type": "document",
                    "source": [
                        "type": "url",
                        "url": url
                    ]
                ]
            }
            return nil

        case .toolCall:
            guard let tc = part.toolCall else { return nil }
            let input: Any
            if let dict = tc.arguments.dictValue {
                input = dict
            } else if let s = tc.arguments.stringValue,
                      let data = s.data(using: .utf8),
                      let parsed = try? JSONSerialization.jsonObject(with: data) {
                input = parsed
            } else {
                input = [String: Any]()
            }
            return [
                "type": "tool_use",
                "id": tc.id,
                "name": tc.name,
                "input": input
            ]

        case .toolResult:
            guard let tr = part.toolResult else { return nil }
            var block: [String: Any] = [
                "type": "tool_result",
                "tool_use_id": tr.toolCallId
            ]
            if let s = tr.content.stringValue {
                block["content"] = s
            } else {
                block["content"] = tr.content.description
            }
            if tr.isError {
                block["is_error"] = true
            }
            return block

        case .thinking:
            guard let th = part.thinking else { return nil }
            if th.redacted {
                return [
                    "type": "redacted_thinking",
                    "data": th.text
                ]
            }
            var block: [String: Any] = [
                "type": "thinking",
                "thinking": th.text
            ]
            if let sig = th.signature {
                block["signature"] = sig
            }
            return block

        case .redactedThinking:
            guard let th = part.thinking else { return nil }
            return [
                "type": "redacted_thinking",
                "data": th.text
            ]

        case .audio:
            // Anthropic does not support audio content
            return nil
        }
    }

    // MARK: - Tool definitions

    private func buildToolDefinitions(_ tools: [ToolDefinition], autoCache: Bool) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for (index, tool) in tools.enumerated() {
            var def: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.parameters
            ]
            // Inject cache_control on the last tool definition
            if autoCache && index == tools.count - 1 {
                def["cache_control"] = ["type": "ephemeral"]
            }
            result.append(def)
        }
        return result
    }

    // MARK: - Tool choice mapping

    private func mapToolChoice(_ tc: ToolChoice) -> [String: Any] {
        switch tc.mode {
        case "auto":
            return ["type": "auto"]
        case "required":
            return ["type": "any"]
        case "named":
            var result: [String: Any] = ["type": "tool"]
            if let name = tc.toolName {
                result["name"] = name
            }
            return result
        default:
            return ["type": "auto"]
        }
    }

    // MARK: - Cache control injection

    /// Injects a `cache_control` breakpoint on the last content block of the
    /// second-to-last user message in the conversation.
    private func injectCacheOnPenultimateUserMessage(_ messages: inout [[String: Any]]) {
        // Find all user-message indices
        var userIndices: [Int] = []
        for (i, msg) in messages.enumerated() {
            if msg["role"] as? String == "user" {
                userIndices.append(i)
            }
        }

        // We want the second-to-last user message
        guard userIndices.count >= 2 else { return }
        let targetIndex = userIndices[userIndices.count - 2]

        guard var contentArray = messages[targetIndex]["content"] as? [[String: Any]],
              !contentArray.isEmpty else { return }

        contentArray[contentArray.count - 1]["cache_control"] = ["type": "ephemeral"]
        messages[targetIndex]["content"] = contentArray
    }

    // MARK: - Response parsing (non-streaming)

    private func parseResponse(json: [String: Any], rateLimit: RateLimitInfo?) throws -> Response {
        let id = json["id"] as? String ?? ""
        let model = json["model"] as? String ?? ""

        // Parse content blocks
        let contentBlocks = json["content"] as? [[String: Any]] ?? []
        var contentParts: [ContentPart] = []

        for block in contentBlocks {
            if let part = parseContentBlock(block) {
                contentParts.append(part)
            }
        }

        // Parse finish reason
        let stopReason = json["stop_reason"] as? String ?? "end_turn"
        let finishReason = Self.mapFinishReason(stopReason)

        // Parse usage
        let usageJSON = json["usage"] as? [String: Any] ?? [:]
        let inputTokens = usageJSON["input_tokens"] as? Int ?? 0
        let outputTokens = usageJSON["output_tokens"] as? Int ?? 0
        let cacheRead = usageJSON["cache_read_input_tokens"] as? Int
        let cacheWrite = usageJSON["cache_creation_input_tokens"] as? Int

        let usage = Usage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite,
            raw: usageJSON
        )

        let message = Message(role: .assistant, content: contentParts)

        return Response(
            id: id,
            model: model,
            provider: name,
            message: message,
            finishReason: finishReason,
            usage: usage,
            raw: json,
            rateLimit: rateLimit
        )
    }

    // MARK: - Content block parsing

    private func parseContentBlock(_ block: [String: Any]) -> ContentPart? {
        let type = block["type"] as? String ?? ""

        switch type {
        case "text":
            let text = block["text"] as? String ?? ""
            return .text(text)

        case "tool_use":
            let id = block["id"] as? String ?? ""
            let name = block["name"] as? String ?? ""
            let input = block["input"] ?? [String: Any]()
            return .toolCall(ToolCallData(
                id: id,
                name: name,
                arguments: AnyCodable(input)
            ))

        case "thinking":
            let text = block["thinking"] as? String ?? ""
            let signature = block["signature"] as? String
            return .thinking(ThinkingData(
                text: text,
                signature: signature,
                redacted: false
            ))

        case "redacted_thinking":
            let data = block["data"] as? String ?? ""
            return .redactedThinking(ThinkingData(
                text: data,
                signature: nil,
                redacted: true
            ))

        default:
            return nil
        }
    }

    // MARK: - Finish reason mapping

    private static func mapFinishReason(_ anthropicReason: String) -> FinishReason {
        switch anthropicReason {
        case "end_turn":
            return FinishReason(reason: "stop", raw: anthropicReason)
        case "stop_sequence":
            return FinishReason(reason: "stop", raw: anthropicReason)
        case "max_tokens":
            return FinishReason(reason: "length", raw: anthropicReason)
        case "tool_use":
            return FinishReason(reason: "tool_calls", raw: anthropicReason)
        default:
            return FinishReason(reason: "other", raw: anthropicReason)
        }
    }

    // MARK: - Error handling

    private func mapError(data: Data, statusCode: Int, headers: [String: String]) -> ProviderError {
        let (message, errorCode, raw) = ErrorMapper.parseErrorResponse(data: data, provider: name)
        let retryAfter = HTTPClient.parseRetryAfter(headers: headers)
        return ErrorMapper.mapHTTPError(
            statusCode: statusCode,
            message: message,
            provider: name,
            errorCode: errorCode,
            raw: raw,
            retryAfter: retryAfter
        )
    }

    // MARK: - Helpers

    private func parseHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k.lowercased()] = v
            }
        }
        return headers
    }

    private func parseJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func parseToolArguments(_ jsonString: String) -> [String: Any] {
        guard !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return parsed
    }
}
