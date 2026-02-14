import Foundation

public final class OpenAIAdapter: ProviderAdapter, @unchecked Sendable {

    // MARK: - Properties

    public let name = "openai"

    private let apiKey: String
    private let baseURL: String
    private let orgID: String?
    private let projectID: String?
    private let httpClient: HTTPClient

    // MARK: - Initialization

    public init(
        apiKey: String,
        baseURL: String? = nil,
        orgID: String? = nil,
        projectID: String? = nil,
        timeout: AdapterTimeout = .default
    ) {
        self.apiKey = apiKey
        self.baseURL = (baseURL ?? "https://api.openai.com").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.orgID = orgID
        self.projectID = projectID
        self.httpClient = HTTPClient(timeout: timeout)
    }

    // MARK: - ProviderAdapter

    public func complete(request: Request) async throws -> Response {
        let url = try buildURL()
        let body = try buildRequestBody(request: request, stream: false)
        let headers = buildHeaders()

        let httpResponse = try await httpClient.post(url: url, body: body, headers: headers)

        if httpResponse.statusCode != 200 {
            throw mapError(statusCode: httpResponse.statusCode, data: httpResponse.data, headers: httpResponse.headers)
        }

        let rateLimit = HTTPClient.parseRateLimitInfo(headers: httpResponse.headers)

        guard let json = try JSONSerialization.jsonObject(with: httpResponse.data) as? [String: Any] else {
            throw ProviderError(message: "Invalid JSON response from OpenAI", provider: name)
        }

        return try parseResponse(json: json, rateLimit: rateLimit)
    }

    public func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let url = try buildURL()
        let body = try buildRequestBody(request: request, stream: true)
        let headers = buildHeaders()

        let (byteStream, httpResponse) = try await httpClient.postStream(url: url, body: body, headers: headers)

        if httpResponse.statusCode != 200 {
            // Read the error body from the stream
            var errorData = Data()
            for try await byte in byteStream {
                errorData.append(byte)
            }
            var responseHeaders: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let k = key as? String, let v = value as? String {
                    responseHeaders[k.lowercased()] = v
                }
            }
            throw mapError(statusCode: httpResponse.statusCode, data: errorData, headers: responseHeaders)
        }

        let sseStream = SSEParser.parse(stream: byteStream)
        let providerName = self.name

        return AsyncThrowingStream { continuation in
            let task = Task {
                var emittedTextStart = false
                // Track tool calls: toolCallId -> (name, accumulated arguments)
                var activeToolCalls: [String: (name: String, arguments: String)] = [:]
                var emittedStreamStart = false

                do {
                    for try await sseEvent in sseStream {
                        // Skip [DONE] sentinel
                        if sseEvent.data == "[DONE]" {
                            continue
                        }

                        guard let eventData = sseEvent.data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
                            continue
                        }

                        let eventType = sseEvent.event ?? json["type"] as? String ?? ""

                        switch eventType {

                        // MARK: Stream start
                        case "response.created":
                            if !emittedStreamStart {
                                emittedStreamStart = true
                                let responseId = (json["response"] as? [String: Any])?["id"] as? String
                                    ?? json["id"] as? String
                                continuation.yield(StreamEvent(
                                    type: .streamStart,
                                    textId: responseId,
                                    raw: json
                                ))
                            }

                        // MARK: Text output delta
                        case "response.output_text.delta":
                            let delta = json["delta"] as? String ?? ""
                            if !emittedTextStart {
                                emittedTextStart = true
                                let itemId = json["item_id"] as? String
                                continuation.yield(StreamEvent(
                                    type: .textStart,
                                    textId: itemId
                                ))
                            }
                            continuation.yield(StreamEvent(
                                type: .textDelta,
                                delta: delta
                            ))

                        // MARK: Text output done
                        case "response.output_text.done":
                            if emittedTextStart {
                                continuation.yield(StreamEvent(type: .textEnd))
                                emittedTextStart = false
                            }

                        // MARK: Reasoning/summary text delta (for reasoning models)
                        case "response.reasoning.delta":
                            let delta = json["delta"] as? String ?? ""
                            if !delta.isEmpty {
                                continuation.yield(StreamEvent(
                                    type: .reasoningDelta,
                                    reasoningDelta: delta
                                ))
                            }

                        case "response.reasoning.done":
                            // Reasoning section complete - no action needed, accumulated via deltas
                            break

                        case "response.output_text.annotation.delta":
                            // Annotation deltas are not reasoning content
                            break

                        // MARK: Output item added (track new items)
                        case "response.output_item.added":
                            if let item = json["item"] as? [String: Any],
                               let itemType = item["type"] as? String {
                                if itemType == "function_call" {
                                    let callId = item["call_id"] as? String ?? item["id"] as? String ?? ""
                                    let fnName = item["name"] as? String ?? ""
                                    activeToolCalls[callId] = (name: fnName, arguments: "")
                                    continuation.yield(StreamEvent(
                                        type: .toolCallStart,
                                        toolCall: ToolCall(id: callId, name: fnName, arguments: [:])
                                    ))
                                }
                            }

                        // MARK: Function call arguments delta
                        case "response.function_call_arguments.delta":
                            let delta = json["delta"] as? String ?? ""
                            let callId = json["call_id"] as? String ?? json["item_id"] as? String ?? ""
                            if var existing = activeToolCalls[callId] {
                                existing.arguments += delta
                                activeToolCalls[callId] = existing
                            }
                            continuation.yield(StreamEvent(
                                type: .toolCallDelta,
                                delta: delta,
                                toolCall: ToolCall(id: callId, name: activeToolCalls[callId]?.name ?? "", arguments: [:], rawArguments: delta)
                            ))

                        // MARK: Function call arguments done
                        case "response.function_call_arguments.done":
                            let callId = json["call_id"] as? String ?? json["item_id"] as? String ?? ""
                            let rawArgs = json["arguments"] as? String ?? activeToolCalls[callId]?.arguments ?? ""
                            let fnName = json["name"] as? String ?? activeToolCalls[callId]?.name ?? ""
                            let parsedArgs = parseArguments(rawArgs)
                            activeToolCalls.removeValue(forKey: callId)
                            continuation.yield(StreamEvent(
                                type: .toolCallEnd,
                                toolCall: ToolCall(id: callId, name: fnName, arguments: parsedArgs, rawArguments: rawArgs)
                            ))

                        // MARK: Output item done
                        case "response.output_item.done":
                            if let item = json["item"] as? [String: Any],
                               let itemType = item["type"] as? String {
                                switch itemType {
                                case "message", "text":
                                    if emittedTextStart {
                                        continuation.yield(StreamEvent(type: .textEnd))
                                        emittedTextStart = false
                                    }
                                case "function_call":
                                    let callId = item["call_id"] as? String ?? item["id"] as? String ?? ""
                                    let fnName = item["name"] as? String ?? ""
                                    let rawArgs = item["arguments"] as? String ?? ""
                                    let parsedArgs = parseArguments(rawArgs)
                                    activeToolCalls.removeValue(forKey: callId)
                                    continuation.yield(StreamEvent(
                                        type: .toolCallEnd,
                                        toolCall: ToolCall(id: callId, name: fnName, arguments: parsedArgs, rawArguments: rawArgs)
                                    ))
                                default:
                                    break
                                }
                            }

                        // MARK: Response completed
                        case "response.completed":
                            let responseObj = json["response"] as? [String: Any] ?? json
                            let usage = parseUsage(responseObj["usage"] as? [String: Any])
                            let status = responseObj["status"] as? String ?? "completed"
                            let finishReason = mapStatusToFinishReason(status: status, output: responseObj["output"] as? [[String: Any]])

                            if emittedTextStart {
                                continuation.yield(StreamEvent(type: .textEnd))
                                emittedTextStart = false
                            }

                            // Build a full response for the finish event
                            let fullResponse = try? buildFinalResponse(from: responseObj, rateLimit: nil)

                            continuation.yield(StreamEvent(
                                type: .finish,
                                finishReason: finishReason,
                                usage: usage,
                                response: fullResponse,
                                raw: json
                            ))

                        // MARK: Response failed
                        case "response.failed":
                            let responseObj = json["response"] as? [String: Any] ?? json
                            let errorInfo = responseObj["error"] as? [String: Any]
                                ?? (responseObj["last_error"] as? [String: Any])
                            let errorMessage = errorInfo?["message"] as? String ?? "Response failed"
                            let errorCode = errorInfo?["code"] as? String
                            continuation.yield(StreamEvent(
                                type: .error,
                                error: ProviderError(
                                    message: errorMessage,
                                    provider: providerName,
                                    errorCode: errorCode,
                                    raw: json
                                )
                            ))
                            continuation.finish()
                            return

                        // MARK: Response incomplete
                        case "response.incomplete":
                            let responseObj = json["response"] as? [String: Any] ?? json
                            let usage = parseUsage(responseObj["usage"] as? [String: Any])
                            if emittedTextStart {
                                continuation.yield(StreamEvent(type: .textEnd))
                                emittedTextStart = false
                            }
                            continuation.yield(StreamEvent(
                                type: .finish,
                                finishReason: FinishReason(reason: "length", raw: "incomplete"),
                                usage: usage,
                                raw: json
                            ))

                        // MARK: Error event
                        case "error":
                            let errorMessage = json["message"] as? String
                                ?? (json["error"] as? [String: Any])?["message"] as? String
                                ?? "Stream error"
                            continuation.yield(StreamEvent(
                                type: .error,
                                error: ProviderError(message: errorMessage, provider: providerName, raw: json)
                            ))

                        default:
                            // Pass through unknown events as provider events
                            continuation.yield(StreamEvent(
                                type: .providerEvent,
                                raw: json
                            ))
                        }
                    }

                    // If we exit the loop without a finish event, close cleanly
                    continuation.finish()
                } catch {
                    continuation.yield(StreamEvent(
                        type: .error,
                        error: StreamError(message: "Stream processing error: \(error.localizedDescription)", cause: error)
                    ))
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - URL Building

    private func buildURL() throws -> URL {
        guard let url = URL(string: "\(baseURL)/v1/responses") else {
            throw ConfigurationError(message: "Invalid base URL: \(baseURL)")
        }
        return url
    }

    // MARK: - Headers

    private func buildHeaders() -> [String: String] {
        var headers: [String: String] = [
            "Authorization": "Bearer \(apiKey)"
        ]
        if let orgID = orgID {
            headers["OpenAI-Organization"] = orgID
        }
        if let projectID = projectID {
            headers["OpenAI-Project"] = projectID
        }
        return headers
    }

    // MARK: - Request Body Construction

    private func buildRequestBody(request: Request, stream: Bool) throws -> Data {
        var body: [String: Any] = [
            "model": request.model
        ]

        // Extract system/developer messages as instructions
        let instructions = extractInstructions(from: request.messages)
        if let instructions = instructions {
            body["instructions"] = instructions
        }

        // Build input array from non-system messages
        let input = buildInputArray(from: request.messages)
        if !input.isEmpty {
            body["input"] = input
        }

        // Temperature
        if let temperature = request.temperature {
            body["temperature"] = temperature
        }

        // Top P
        if let topP = request.topP {
            body["top_p"] = topP
        }

        // Max output tokens
        if let maxTokens = request.maxTokens {
            body["max_output_tokens"] = maxTokens
        }

        // Stop sequences
        if let stopSequences = request.stopSequences, !stopSequences.isEmpty {
            body["stop"] = stopSequences
        }

        // Reasoning effort
        if let effort = request.reasoningEffort {
            body["reasoning"] = ["effort": effort]
        }

        // Tools
        if let tools = request.tools, !tools.isEmpty {
            body["tools"] = tools.map { buildToolDefinition($0) }
        }

        // Tool choice
        if let toolChoice = request.toolChoice {
            body["tool_choice"] = buildToolChoice(toolChoice)
        }

        // Response format (structured output)
        if let format = request.responseFormat {
            body["text"] = buildResponseFormat(format)
        }

        // Streaming
        if stream {
            body["stream"] = true
        }

        // Metadata
        if let metadata = request.metadata, !metadata.isEmpty {
            body["metadata"] = metadata
        }

        // Provider-specific options escape hatch
        if let openaiOptions = request.providerOptions?["openai"] {
            for (key, value) in openaiOptions {
                body[key] = value.value
            }
        }

        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Instructions Extraction

    /// Extracts system and developer messages into an instructions string.
    /// System messages are concatenated. Developer messages are included as well.
    private func extractInstructions(from messages: [Message]) -> String? {
        var instructionParts: [String] = []

        for message in messages {
            switch message.role {
            case .system:
                let text = message.text
                if !text.isEmpty {
                    instructionParts.append(text)
                }
            case .developer:
                let text = message.text
                if !text.isEmpty {
                    instructionParts.append(text)
                }
            default:
                break
            }
        }

        return instructionParts.isEmpty ? nil : instructionParts.joined(separator: "\n\n")
    }

    // MARK: - Input Array Construction

    private func buildInputArray(from messages: [Message]) -> [[String: Any]] {
        var input: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .system, .developer:
                // Already extracted to instructions
                continue

            case .user:
                let items = buildUserInputItems(from: message)
                input.append(contentsOf: items)

            case .assistant:
                let items = buildAssistantInputItems(from: message)
                input.append(contentsOf: items)

            case .tool:
                let items = buildToolResultItems(from: message)
                input.append(contentsOf: items)
            }
        }

        return input
    }

    private func buildUserInputItems(from message: Message) -> [[String: Any]] {
        var items: [[String: Any]] = []

        for part in message.content {
            guard let kind = part.contentKind else { continue }

            switch kind {
            case .text:
                if let text = part.text {
                    items.append([
                        "type": "message",
                        "role": "user",
                        "content": [
                            ["type": "input_text", "text": text]
                        ]
                    ])
                }

            case .image:
                if let image = part.image {
                    var imageContent: [String: Any] = ["type": "input_image"]
                    if let url = image.url {
                        if isLocalFilePath(url), let inlined = inlineLocalFile(url) {
                            imageContent["image_url"] = inlined.dataURL
                        } else {
                            imageContent["image_url"] = url
                        }
                    } else if let data = image.data {
                        let mediaType = image.mediaType ?? "image/png"
                        let b64 = data.base64EncodedString()
                        imageContent["image_url"] = "data:\(mediaType);base64,\(b64)"
                    }
                    if let detail = image.detail {
                        imageContent["detail"] = detail
                    }
                    items.append([
                        "type": "message",
                        "role": "user",
                        "content": [imageContent]
                    ])
                }

            default:
                break
            }
        }

        // If there are multiple content parts, merge them into a single message
        if items.count > 1 {
            var mergedContent: [[String: Any]] = []
            for item in items {
                if let content = item["content"] as? [[String: Any]] {
                    mergedContent.append(contentsOf: content)
                }
            }
            return [[
                "type": "message",
                "role": "user",
                "content": mergedContent
            ]]
        }

        return items
    }

    private func buildAssistantInputItems(from message: Message) -> [[String: Any]] {
        var items: [[String: Any]] = []
        var textParts: [String] = []

        for part in message.content {
            guard let kind = part.contentKind else { continue }

            switch kind {
            case .text:
                if let text = part.text {
                    textParts.append(text)
                }

            case .toolCall:
                if let tc = part.toolCall {
                    // Emit accumulated text first as an assistant message
                    if !textParts.isEmpty {
                        let combinedText = textParts.joined()
                        items.append([
                            "type": "message",
                            "role": "assistant",
                            "content": [
                                ["type": "output_text", "text": combinedText]
                            ]
                        ])
                        textParts = []
                    }
                    // Emit function_call as a top-level item
                    let argsString: String
                    if let str = tc.arguments.stringValue {
                        argsString = str
                    } else if let dict = tc.arguments.dictValue,
                              let data = try? JSONSerialization.data(withJSONObject: dict),
                              let str = String(data: data, encoding: .utf8) {
                        argsString = str
                    } else {
                        argsString = "{}"
                    }
                    items.append([
                        "type": "function_call",
                        "call_id": tc.id,
                        "name": tc.name,
                        "arguments": argsString
                    ])
                }

            default:
                break
            }
        }

        // Flush remaining text
        if !textParts.isEmpty {
            let combinedText = textParts.joined()
            items.append([
                "type": "message",
                "role": "assistant",
                "content": [
                    ["type": "output_text", "text": combinedText]
                ]
            ])
        }

        return items
    }

    private func buildToolResultItems(from message: Message) -> [[String: Any]] {
        var items: [[String: Any]] = []

        for part in message.content {
            guard let kind = part.contentKind else { continue }

            if kind == .toolResult, let result = part.toolResult {
                let outputString: String
                if let str = result.content.stringValue {
                    outputString = str
                } else if let dict = result.content.dictValue,
                          let data = try? JSONSerialization.data(withJSONObject: dict),
                          let str = String(data: data, encoding: .utf8) {
                    outputString = str
                } else if let arr = result.content.arrayValue,
                          let data = try? JSONSerialization.data(withJSONObject: arr),
                          let str = String(data: data, encoding: .utf8) {
                    outputString = str
                } else {
                    outputString = "\(result.content.value)"
                }

                items.append([
                    "type": "function_call_output",
                    "call_id": result.toolCallId,
                    "output": outputString
                ])
            }
        }

        // Fallback: if no tool result content parts found but message has toolCallId
        if items.isEmpty, let toolCallId = message.toolCallId {
            let text = message.text
            items.append([
                "type": "function_call_output",
                "call_id": toolCallId,
                "output": text
            ])
        }

        return items
    }

    // MARK: - Tool Definitions

    private func buildToolDefinition(_ tool: ToolDefinition) -> [String: Any] {
        var def: [String: Any] = [
            "type": "function",
            "name": tool.name
        ]
        if !tool.description.isEmpty {
            def["description"] = tool.description
        }
        if !tool.parameters.isEmpty {
            def["parameters"] = tool.parameters
        }
        return def
    }

    // MARK: - Tool Choice

    private func buildToolChoice(_ choice: ToolChoice) -> Any {
        switch choice.mode {
        case "auto":
            return "auto"
        case "none":
            return "none"
        case "required":
            return "required"
        case "named":
            if let toolName = choice.toolName {
                return [
                    "type": "function",
                    "function": ["name": toolName]
                ] as [String: Any]
            }
            return "auto"
        default:
            return "auto"
        }
    }

    // MARK: - Response Format

    private func buildResponseFormat(_ format: ResponseFormat) -> [String: Any] {
        switch format.type {
        case "json_schema":
            if var schema = format.jsonSchema {
                let schemaName = schema["name"] as? String ?? "response"
                // When strict mode, OpenAI requires additionalProperties: false on object types
                if format.strict && schema["type"] as? String == "object" {
                    schema["additionalProperties"] = false
                }
                var formatObj: [String: Any] = [
                    "type": "json_schema",
                    "name": schemaName,
                    "schema": schema
                ]
                if format.strict {
                    formatObj["strict"] = true
                }
                return ["format": formatObj]
            }
            return ["format": ["type": "json_object"]]
        case "json":
            return ["format": ["type": "json_object"]]
        default:
            return ["format": ["type": "text"]]
        }
    }

    // MARK: - Response Parsing

    private func parseResponse(json: [String: Any], rateLimit: RateLimitInfo?) throws -> Response {
        return try buildFinalResponse(from: json, rateLimit: rateLimit)
    }

    private func buildFinalResponse(from json: [String: Any], rateLimit: RateLimitInfo?) throws -> Response {
        let id = json["id"] as? String ?? ""
        let model = json["model"] as? String ?? ""
        let status = json["status"] as? String ?? "completed"
        let output = json["output"] as? [[String: Any]] ?? []

        // Parse output items
        var contentParts: [ContentPart] = []

        for item in output {
            let itemType = item["type"] as? String ?? ""

            switch itemType {
            case "message":
                // A message output item contains content array
                if let content = item["content"] as? [[String: Any]] {
                    for contentItem in content {
                        let contentType = contentItem["type"] as? String ?? ""
                        if contentType == "output_text" || contentType == "text" {
                            if let text = contentItem["text"] as? String {
                                contentParts.append(.text(text))
                            }
                        }
                    }
                }

            case "text":
                // Direct text output item
                if let text = item["text"] as? String {
                    contentParts.append(.text(text))
                }

            case "function_call":
                // In the Responses API, "call_id" is used for function_call_output correlation
                let callId = item["call_id"] as? String ?? item["id"] as? String ?? ""
                let fnName = item["name"] as? String ?? ""
                let rawArgs = item["arguments"] as? String ?? "{}"
                let parsedArgs = parseArguments(rawArgs)
                contentParts.append(.toolCall(ToolCallData(
                    id: callId,
                    name: fnName,
                    arguments: AnyCodable(parsedArgs),
                    type: "function"
                )))

            case "reasoning":
                // Reasoning/thinking content
                if let summary = item["summary"] as? [[String: Any]] {
                    for summaryItem in summary {
                        if let text = summaryItem["text"] as? String {
                            contentParts.append(.thinking(ThinkingData(text: text)))
                        }
                    }
                } else if let text = item["text"] as? String {
                    contentParts.append(.thinking(ThinkingData(text: text)))
                }

            default:
                break
            }
        }

        let message = Message(role: .assistant, content: contentParts)
        let usage = parseUsage(json["usage"] as? [String: Any])
        let finishReason = mapStatusToFinishReason(status: status, output: output)

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

    // MARK: - Usage Parsing

    private func parseUsage(_ usageDict: [String: Any]?) -> Usage {
        guard let u = usageDict else {
            return .zero
        }

        let inputTokens = u["input_tokens"] as? Int ?? 0
        let outputTokens = u["output_tokens"] as? Int ?? 0
        let totalTokens = u["total_tokens"] as? Int

        // Reasoning tokens from output_tokens_details
        var reasoningTokens: Int?
        if let outputDetails = u["output_tokens_details"] as? [String: Any] {
            reasoningTokens = outputDetails["reasoning_tokens"] as? Int
        }

        // Cache read tokens from input_tokens_details
        var cacheReadTokens: Int?
        if let inputDetails = u["input_tokens_details"] as? [String: Any] {
            cacheReadTokens = inputDetails["cached_tokens"] as? Int
        }

        return Usage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            reasoningTokens: reasoningTokens,
            cacheReadTokens: cacheReadTokens,
            raw: u
        )
    }

    // MARK: - Finish Reason Mapping

    private func mapStatusToFinishReason(status: String, output: [[String: Any]]?) -> FinishReason {
        switch status {
        case "completed":
            // Check if there are tool calls in the output
            let hasToolCalls = output?.contains(where: { ($0["type"] as? String) == "function_call" }) ?? false
            if hasToolCalls {
                return FinishReason(reason: "tool_calls", raw: status)
            }
            return FinishReason(reason: "stop", raw: status)
        case "incomplete":
            return FinishReason(reason: "length", raw: status)
        case "failed":
            return FinishReason(reason: "error", raw: status)
        case "cancelled":
            return FinishReason(reason: "other", raw: status)
        default:
            return FinishReason(reason: "other", raw: status)
        }
    }

    // MARK: - Argument Parsing

    private func parseArguments(_ raw: String) -> [String: Any] {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return parsed
    }

    // MARK: - Error Handling

    private func mapError(statusCode: Int, data: Data, headers: [String: String]) -> ProviderError {
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
}
