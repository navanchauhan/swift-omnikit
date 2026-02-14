import Foundation

public final class GeminiAdapter: ProviderAdapter, @unchecked Sendable {

    // MARK: - Properties

    public let name: String = "gemini"

    private let apiKey: String
    private let baseURL: String
    private let httpClient: HTTPClient

    /// Maps synthetic tool-call IDs (call_UUID) -> function name.
    /// Gemini does NOT return unique IDs for function calls, so we generate them
    /// and maintain this mapping so that when a tool-result message arrives keyed
    /// by synthetic ID we can look up the original function name that Gemini expects
    /// in its functionResponse.
    private let callIDLock = NSLock()
    private var callIDToFunctionName: [String: String] = [:]
    private var callIDToThoughtSignature: [String: String] = [:]

    // MARK: - Initializer

    public init(
        apiKey: String,
        baseURL: String? = nil,
        timeout: AdapterTimeout = .default
    ) {
        self.apiKey = apiKey
        self.baseURL = (baseURL ?? "https://generativelanguage.googleapis.com")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.httpClient = HTTPClient(timeout: timeout)
    }

    // MARK: - ProviderAdapter

    public func complete(request: Request) async throws -> Response {
        let (url, body) = try buildRequest(request: request, stream: false)
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let httpResponse = try await httpClient.post(url: url, body: bodyData, headers: [:])

        if httpResponse.statusCode != 200 {
            let parsed = ErrorMapper.parseErrorResponse(data: httpResponse.data, provider: name)
            let retryAfter = HTTPClient.parseRetryAfter(headers: httpResponse.headers)
            throw ErrorMapper.mapHTTPError(
                statusCode: httpResponse.statusCode,
                message: parsed.message,
                provider: name,
                errorCode: parsed.errorCode,
                raw: parsed.raw,
                retryAfter: retryAfter
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: httpResponse.data) as? [String: Any] else {
            throw ProviderError(message: "Invalid JSON response from Gemini", provider: name)
        }

        let rateLimit = HTTPClient.parseRateLimitInfo(headers: httpResponse.headers)
        return try parseResponse(json: json, model: request.model, rateLimit: rateLimit)
    }

    public func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let (url, body) = try buildRequest(request: request, stream: true)
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let (byteStream, httpResponse) = try await httpClient.postStream(url: url, body: bodyData, headers: [:])

        if httpResponse.statusCode != 200 {
            // Collect error body
            var errorData = Data()
            for try await byte in byteStream {
                errorData.append(byte)
            }
            let parsed = ErrorMapper.parseErrorResponse(data: errorData, provider: name)
            var headers: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let k = key as? String, let v = value as? String {
                    headers[k.lowercased()] = v
                }
            }
            let retryAfter = HTTPClient.parseRetryAfter(headers: headers)
            throw ErrorMapper.mapHTTPError(
                statusCode: httpResponse.statusCode,
                message: parsed.message,
                provider: name,
                errorCode: parsed.errorCode,
                raw: parsed.raw,
                retryAfter: retryAfter
            )
        }

        let sseStream = SSEParser.parse(stream: byteStream)
        let model = request.model
        let adapter = self

        return AsyncThrowingStream<StreamEvent, Error> { continuation in
            let task = Task {
                var textStarted = false
                var accumulatedText = ""
                var accumulatedToolCalls: [ToolCall] = []
                var finalUsage: Usage?
                var finalFinishReason: FinishReason?
                var accumulatedContentParts: [ContentPart] = []

                // Emit stream start
                continuation.yield(StreamEvent(type: .streamStart))

                do {
                    for try await sseEvent in sseStream {
                        let data = sseEvent.data
                        guard !data.isEmpty,
                              let eventData = data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any]
                        else {
                            continue
                        }

                        // Parse usage from this chunk
                        if let usageMeta = json["usageMetadata"] as? [String: Any] {
                            finalUsage = adapter.parseUsage(usageMeta)
                        }

                        // Parse candidates
                        guard let candidates = json["candidates"] as? [[String: Any]],
                              let candidate = candidates.first
                        else {
                            continue
                        }

                        // Check finish reason
                        if let rawFinish = candidate["finishReason"] as? String {
                            finalFinishReason = adapter.mapFinishReason(rawFinish)
                        }

                        // Parse content parts
                        guard let content = candidate["content"] as? [String: Any],
                              let parts = content["parts"] as? [[String: Any]]
                        else {
                            // Might be a chunk with only finishReason, no content
                            if finalFinishReason != nil {
                                // Emit text end and finish at the end of the loop
                            }
                            continue
                        }

                        for part in parts {
                            if let thought = part["thought"] as? Bool, thought == true,
                               let thoughtText = part["text"] as? String {
                                // Reasoning/thinking delta
                                continuation.yield(StreamEvent(
                                    type: .reasoningStart,
                                    reasoningDelta: ""
                                ))
                                continuation.yield(StreamEvent(
                                    type: .reasoningDelta,
                                    reasoningDelta: thoughtText
                                ))
                                continuation.yield(StreamEvent(
                                    type: .reasoningEnd,
                                    reasoningDelta: ""
                                ))
                                accumulatedContentParts.append(.thinking(ThinkingData(text: thoughtText)))
                            } else if let text = part["text"] as? String {
                                // Text delta
                                if !textStarted {
                                    continuation.yield(StreamEvent(type: .textStart))
                                    textStarted = true
                                }
                                accumulatedText += text
                                continuation.yield(StreamEvent(
                                    type: .textDelta,
                                    delta: text
                                ))
                            } else if let functionCall = part["functionCall"] as? [String: Any],
                                      let fnName = functionCall["name"] as? String {
                                // Function call - Gemini delivers complete in one chunk
                                let args = functionCall["args"] as? [String: Any] ?? [:]
                                let syntheticID = "call_" + UUID().uuidString

                                // Store mapping
                                adapter.recordCallID(syntheticID, functionName: fnName)
                                if let thoughtSig = part["thoughtSignature"] as? String {
                                    adapter.recordThoughtSignature(syntheticID, signature: thoughtSig)
                                }

                                let toolCall = ToolCall(id: syntheticID, name: fnName, arguments: args)
                                accumulatedToolCalls.append(toolCall)

                                accumulatedContentParts.append(.toolCall(ToolCallData(
                                    id: syntheticID,
                                    name: fnName,
                                    arguments: AnyCodable(args)
                                )))

                                continuation.yield(StreamEvent(
                                    type: .toolCallStart,
                                    toolCall: toolCall
                                ))
                                continuation.yield(StreamEvent(
                                    type: .toolCallEnd,
                                    toolCall: toolCall
                                ))
                            }
                        }
                    }

                    // Stream ended - emit text end if we started text
                    if textStarted {
                        continuation.yield(StreamEvent(type: .textEnd))
                        accumulatedContentParts.insert(.text(accumulatedText), at: 0)
                    }

                    // Determine finish reason
                    let finishReason: FinishReason
                    if !accumulatedToolCalls.isEmpty && (finalFinishReason == nil || finalFinishReason?.reason == "stop") {
                        finishReason = .toolCalls
                    } else {
                        finishReason = finalFinishReason ?? .stop
                    }

                    let usage = finalUsage ?? .zero

                    // Build the accumulated response message
                    var messageParts = accumulatedContentParts
                    if messageParts.isEmpty && !accumulatedText.isEmpty {
                        messageParts = [.text(accumulatedText)]
                    }

                    let message = Message(role: .assistant, content: messageParts)

                    let response = Response(
                        id: UUID().uuidString,
                        model: model,
                        provider: "gemini",
                        message: message,
                        finishReason: finishReason,
                        usage: usage
                    )

                    // Emit finish event
                    continuation.yield(StreamEvent(
                        type: .finish,
                        finishReason: finishReason,
                        usage: usage,
                        response: response
                    ))

                    continuation.finish()
                } catch {
                    continuation.yield(StreamEvent(
                        type: .error,
                        error: error as? SDKError ?? StreamError(message: error.localizedDescription, cause: error)
                    ))
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request Building

    private func buildRequest(request: Request, stream: Bool) throws -> (URL, [String: Any]) {
        let model = request.model

        let action = stream ? "streamGenerateContent" : "generateContent"
        var urlString = "\(baseURL)/v1beta/models/\(model):\(action)"

        // Authentication via query parameter
        if stream {
            urlString += "?alt=sse&key=\(apiKey)"
        } else {
            urlString += "?key=\(apiKey)"
        }

        guard let url = URL(string: urlString) else {
            throw InvalidRequestError(message: "Invalid URL: \(urlString)", provider: name)
        }

        var body: [String: Any] = [:]

        // Extract system instruction from system and developer messages
        let systemParts = extractSystemParts(from: request.messages)
        if !systemParts.isEmpty {
            body["system_instruction"] = ["parts": systemParts]
        }

        // Build contents array (non-system messages)
        let contents = try buildContents(from: request.messages)
        body["contents"] = contents

        // Generation config
        var genConfig: [String: Any] = [:]
        if let temp = request.temperature {
            genConfig["temperature"] = temp
        }
        if let topP = request.topP {
            genConfig["topP"] = topP
        }
        if let maxTokens = request.maxTokens {
            genConfig["maxOutputTokens"] = maxTokens
        }
        if let stops = request.stopSequences, !stops.isEmpty {
            genConfig["stopSequences"] = stops
        }

        // Structured output / response format
        if let responseFormat = request.responseFormat {
            if responseFormat.type == "json" || responseFormat.type == "json_schema" {
                genConfig["responseMimeType"] = "application/json"
                if let schema = responseFormat.jsonSchema {
                    genConfig["responseSchema"] = schema
                }
            }
        }

        if !genConfig.isEmpty {
            body["generationConfig"] = genConfig
        }

        // Tools
        if let tools = request.tools, !tools.isEmpty {
            let functionDeclarations: [[String: Any]] = tools.map { tool in
                var decl: [String: Any] = [
                    "name": tool.name,
                    "description": tool.description
                ]
                if !tool.parameters.isEmpty {
                    decl["parameters"] = tool.parameters
                }
                return decl
            }
            body["tools"] = [["functionDeclarations": functionDeclarations]]
        }

        // Tool choice -> toolConfig.functionCallingConfig
        if let toolChoice = request.toolChoice {
            let callingConfig = buildToolConfig(toolChoice)
            body["toolConfig"] = ["functionCallingConfig": callingConfig]
        }

        // Provider options escape hatch (gemini-specific)
        if let geminiOpts = request.providerOptions?["gemini"] {
            for (key, value) in geminiOpts {
                // Safety settings
                if key == "safetySettings" {
                    body["safetySettings"] = value.value
                }
                // Thinking config
                else if key == "thinkingConfig" {
                    body["thinkingConfig"] = value.value
                }
                // Any other top-level Gemini params
                else {
                    body[key] = value.value
                }
            }
        }

        return (url, body)
    }

    // MARK: - System Instruction

    private func extractSystemParts(from messages: [Message]) -> [[String: Any]] {
        var parts: [[String: Any]] = []
        for message in messages {
            guard message.role == .system || message.role == .developer else { continue }
            for contentPart in message.content {
                if let text = contentPart.text {
                    parts.append(["text": text])
                }
            }
        }
        return parts
    }

    // MARK: - Contents Building

    private func buildContents(from messages: [Message]) throws -> [[String: Any]] {
        var contents: [[String: Any]] = []

        for message in messages {
            // Skip system and developer messages (handled in system_instruction)
            if message.role == .system || message.role == .developer {
                continue
            }

            let geminiRole: String
            switch message.role {
            case .user:
                geminiRole = "user"
            case .assistant:
                geminiRole = "model"
            case .tool:
                geminiRole = "user"
            default:
                geminiRole = "user"
            }

            var parts: [[String: Any]] = []

            for contentPart in message.content {
                switch contentPart.contentKind {
                case .text:
                    if let text = contentPart.text {
                        parts.append(["text": text])
                    }

                case .image:
                    if let imageData = contentPart.image {
                        if let url = imageData.url {
                            if isLocalFilePath(url), let inlined = inlineLocalFile(url) {
                                // Local file -> inline base64
                                parts.append([
                                    "inlineData": [
                                        "mimeType": inlined.mimeType,
                                        "data": inlined.data.base64EncodedString()
                                    ]
                                ])
                            } else {
                                // URL-based image -> fileData
                                let mimeType = imageData.mediaType ?? guessMimeType(from: url)
                                parts.append([
                                    "fileData": [
                                        "mimeType": mimeType,
                                        "fileUri": url
                                    ]
                                ])
                            }
                        } else if let data = imageData.data {
                            // Inline base64 image -> inlineData
                            let mimeType = imageData.mediaType ?? "image/png"
                            parts.append([
                                "inlineData": [
                                    "mimeType": mimeType,
                                    "data": data.base64EncodedString()
                                ]
                            ])
                        }
                    }

                case .audio:
                    if let audioData = contentPart.audio {
                        if let url = audioData.url {
                            let mimeType = audioData.mediaType ?? "audio/mp3"
                            parts.append([
                                "fileData": [
                                    "mimeType": mimeType,
                                    "fileUri": url
                                ]
                            ])
                        } else if let data = audioData.data {
                            let mimeType = audioData.mediaType ?? "audio/mp3"
                            parts.append([
                                "inlineData": [
                                    "mimeType": mimeType,
                                    "data": data.base64EncodedString()
                                ]
                            ])
                        }
                    }

                case .document:
                    if let docData = contentPart.document {
                        if let url = docData.url {
                            let mimeType = docData.mediaType ?? "application/pdf"
                            parts.append([
                                "fileData": [
                                    "mimeType": mimeType,
                                    "fileUri": url
                                ]
                            ])
                        } else if let data = docData.data {
                            let mimeType = docData.mediaType ?? "application/pdf"
                            parts.append([
                                "inlineData": [
                                    "mimeType": mimeType,
                                    "data": data.base64EncodedString()
                                ]
                            ])
                        }
                    }

                case .toolCall:
                    // Assistant message with a function call
                    if let tc = contentPart.toolCall {
                        let args: [String: Any]
                        if let dict = tc.arguments.dictValue {
                            args = dict
                        } else if let str = tc.arguments.stringValue,
                                  let data = str.data(using: .utf8),
                                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            args = parsed
                        } else {
                            args = [:]
                        }
                        let fcDict: [String: Any] = [
                            "name": tc.name,
                            "args": args
                        ]
                        // thoughtSignature is at the part level (sibling of functionCall)
                        var partDict: [String: Any] = [
                            "functionCall": fcDict
                        ]
                        if let sig = lookupThoughtSignature(forCallID: tc.id) {
                            partDict["thoughtSignature"] = sig
                        }
                        parts.append(partDict)
                    }

                case .toolResult:
                    // Tool result -> functionResponse
                    if let tr = contentPart.toolResult {
                        // Gemini uses function NAME, not call ID.
                        // Look up the function name from our synthetic ID mapping.
                        let functionName = lookupFunctionName(forCallID: tr.toolCallId)
                            ?? tr.toolCallId  // fallback: use the ID itself if no mapping found

                        let responseBody: [String: Any]
                        if let dict = tr.content.dictValue {
                            responseBody = dict
                        } else if let str = tr.content.stringValue {
                            responseBody = ["result": str]
                        } else if let arr = tr.content.arrayValue {
                            responseBody = ["result": arr]
                        } else {
                            responseBody = ["result": "\(tr.content.value)"]
                        }

                        parts.append([
                            "functionResponse": [
                                "name": functionName,
                                "response": responseBody
                            ]
                        ])
                    }

                case .thinking:
                    // Thinking content is not directly sent to Gemini in user messages
                    break

                case .redactedThinking:
                    break

                case .none:
                    break
                }
            }

            if !parts.isEmpty {
                // Try to merge with previous content entry if same role
                // Gemini requires alternating user/model roles, so merge consecutive same-role
                if let lastIndex = contents.indices.last,
                   let lastRole = contents[lastIndex]["role"] as? String,
                   lastRole == geminiRole {
                    var existing = contents[lastIndex]["parts"] as? [[String: Any]] ?? []
                    existing.append(contentsOf: parts)
                    contents[lastIndex]["parts"] = existing
                } else {
                    contents.append([
                        "role": geminiRole,
                        "parts": parts
                    ])
                }
            }
        }

        return contents
    }

    // MARK: - Tool Config

    private func buildToolConfig(_ toolChoice: ToolChoice) -> [String: Any] {
        switch toolChoice.mode {
        case "auto":
            return ["mode": "AUTO"]
        case "none":
            return ["mode": "NONE"]
        case "required":
            return ["mode": "ANY"]
        case "named":
            var config: [String: Any] = ["mode": "ANY"]
            if let name = toolChoice.toolName {
                config["allowedFunctionNames"] = [name]
            }
            return config
        default:
            return ["mode": "AUTO"]
        }
    }

    // MARK: - Response Parsing

    private func parseResponse(json: [String: Any], model: String, rateLimit: RateLimitInfo?) throws -> Response {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let candidate = candidates.first
        else {
            // Check for prompt-level block
            if let promptFeedback = json["promptFeedback"] as? [String: Any],
               let blockReason = promptFeedback["blockReason"] as? String {
                throw ContentFilterError(
                    message: "Request blocked by Gemini safety filter: \(blockReason)",
                    provider: name,
                    raw: json
                )
            }
            throw ProviderError(message: "No candidates in Gemini response", provider: name, raw: json)
        }

        // Parse finish reason
        let rawFinishReason = candidate["finishReason"] as? String ?? "STOP"
        var finishReason = mapFinishReason(rawFinishReason)

        // Parse content parts
        var contentParts: [ContentPart] = []
        var hasToolCalls = false

        if let content = candidate["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            for part in parts {
                if let thought = part["thought"] as? Bool, thought == true,
                   let thoughtText = part["text"] as? String {
                    contentParts.append(.thinking(ThinkingData(text: thoughtText)))
                } else if let text = part["text"] as? String {
                    contentParts.append(.text(text))
                } else if let functionCall = part["functionCall"] as? [String: Any],
                          let fnName = functionCall["name"] as? String {
                    let args = functionCall["args"] as? [String: Any] ?? [:]
                    let syntheticID = "call_" + UUID().uuidString

                    // Store mapping for later tool-result correlation
                    recordCallID(syntheticID, functionName: fnName)
                    // Preserve thoughtSignature for round-tripping (sibling of functionCall in part)
                    if let thoughtSig = part["thoughtSignature"] as? String {
                        recordThoughtSignature(syntheticID, signature: thoughtSig)
                    }

                    contentParts.append(.toolCall(ToolCallData(
                        id: syntheticID,
                        name: fnName,
                        arguments: AnyCodable(args)
                    )))
                    hasToolCalls = true
                }
            }
        }

        // Infer tool_calls finish reason if function calls are present
        if hasToolCalls {
            finishReason = .toolCalls
        }

        // Parse usage
        let usage: Usage
        if let usageMeta = json["usageMetadata"] as? [String: Any] {
            usage = parseUsage(usageMeta)
        } else {
            usage = .zero
        }

        let message = Message(role: .assistant, content: contentParts)

        return Response(
            id: UUID().uuidString,
            model: model,
            provider: name,
            message: message,
            finishReason: finishReason,
            usage: usage,
            raw: json,
            rateLimit: rateLimit
        )
    }

    // MARK: - Finish Reason Mapping

    private func mapFinishReason(_ raw: String) -> FinishReason {
        switch raw {
        case "STOP":
            return FinishReason(reason: "stop", raw: raw)
        case "MAX_TOKENS":
            return FinishReason(reason: "length", raw: raw)
        case "SAFETY":
            return FinishReason(reason: "content_filter", raw: raw)
        case "RECITATION":
            return FinishReason(reason: "content_filter", raw: raw)
        case "FINISH_REASON_UNSPECIFIED":
            return FinishReason(reason: "other", raw: raw)
        case "OTHER":
            return FinishReason(reason: "other", raw: raw)
        default:
            return FinishReason(reason: "other", raw: raw)
        }
    }

    // MARK: - Usage Parsing

    private func parseUsage(_ meta: [String: Any]) -> Usage {
        let inputTokens = meta["promptTokenCount"] as? Int ?? 0
        let outputTokens = meta["candidatesTokenCount"] as? Int ?? 0
        let reasoningTokens = meta["thoughtsTokenCount"] as? Int
        let cacheReadTokens = meta["cachedContentTokenCount"] as? Int
        let cacheWriteTokens = meta["cacheCreationInputTokenCount"] as? Int
            ?? meta["cachedContentCreationTokenCount"] as? Int

        return Usage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            reasoningTokens: reasoningTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            raw: meta
        )
    }

    // MARK: - Call ID Mapping

    /// Records a synthetic call ID -> function name mapping.
    private func recordCallID(_ callID: String, functionName: String) {
        callIDLock.lock()
        defer { callIDLock.unlock() }
        callIDToFunctionName[callID] = functionName
    }

    /// Looks up the function name for a synthetic call ID.
    private func lookupFunctionName(forCallID callID: String) -> String? {
        callIDLock.lock()
        defer { callIDLock.unlock() }
        return callIDToFunctionName[callID]
    }

    // MARK: - Thought Signature Mapping

    private func recordThoughtSignature(_ callID: String, signature: String) {
        callIDLock.lock()
        defer { callIDLock.unlock() }
        callIDToThoughtSignature[callID] = signature
    }

    private func lookupThoughtSignature(forCallID callID: String) -> String? {
        callIDLock.lock()
        defer { callIDLock.unlock() }
        return callIDToThoughtSignature[callID]
    }

    // MARK: - Helpers

    private func guessMimeType(from url: String) -> String {
        let lower = url.lowercased()
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".gif") { return "image/gif" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        if lower.hasSuffix(".svg") { return "image/svg+xml" }
        if lower.hasSuffix(".bmp") { return "image/bmp" }
        if lower.hasSuffix(".mp3") { return "audio/mp3" }
        if lower.hasSuffix(".wav") { return "audio/wav" }
        if lower.hasSuffix(".pdf") { return "application/pdf" }
        return "application/octet-stream"
    }
}
