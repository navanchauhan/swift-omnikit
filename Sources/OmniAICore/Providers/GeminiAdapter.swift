import Foundation

import OmniHTTP

public final class GeminiAdapter: ProviderAdapter, @unchecked Sendable {
    public let name: String = "gemini"

    private let apiKey: String
    private let baseURL: String
    private let transport: HTTPTransport

    public init(apiKey: String, baseURL: String? = nil, transport: HTTPTransport) {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? "https://generativelanguage.googleapis.com"
        self.transport = transport
    }

    public func complete(request: Request) async throws -> Response {
        try await request.abortSignal?.check()

        let url = try _ProviderHTTP.makeURL(
            baseURL: baseURL,
            path: "/v1beta/models/\(request.model):generateContent",
            query: ["key": apiKey]
        )

        let body = try buildRequestBody(request: request, stream: false)
        var headers = HTTPHeaders()
        headers.set(name: "content-type", value: "application/json")

        let timeout = request.timeout?.asConfig.total
        let http = try await transport.send(
            HTTPRequest(method: .post, url: url, headers: headers, body: .bytes(body)),
            timeout: timeout
        )

        if !(200..<300).contains(http.statusCode) {
            let json = _ProviderHTTP.parseJSONBody(http)
            let msg = _ProviderHTTP.errorMessage(from: json).message ?? "Gemini error"
            let code = _ProviderHTTP.errorMessage(from: json).code
            let retryAfter = _ProviderHTTP.parseRetryAfterSeconds(http.headers)
            let err = _ErrorMapping.sdkErrorFromHTTP(
                provider: name,
                statusCode: http.statusCode,
                message: msg,
                errorCode: code,
                retryAfter: retryAfter,
                raw: json
            )
            throw err
        }

        let json = _ProviderHTTP.parseJSONBody(http) ?? .object([:])
        return try parseResponse(json: json, headers: http.headers, requestedModel: request.model)
    }

    public func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        try await request.abortSignal?.check()

        // Gemini streams via SSE when using alt=sse on streamGenerateContent.
        let url = try _ProviderHTTP.makeURL(
            baseURL: baseURL,
            path: "/v1beta/models/\(request.model):streamGenerateContent",
            query: ["key": apiKey, "alt": "sse"]
        )

        let body = try buildRequestBody(request: request, stream: true)
        var headers = HTTPHeaders()
        headers.set(name: "content-type", value: "application/json")
        headers.set(name: "accept", value: "text/event-stream")

        let timeout = request.timeout?.asConfig.total
        let res: HTTPStreamResponse
        do {
            res = try await transport.openStream(
                HTTPRequest(method: .post, url: url, headers: headers, body: .bytes(body)),
                timeout: timeout
            )
        } catch {
            // Linux FoundationNetworking does not currently support URLSession streaming.
            // Fallback to non-stream complete and synthesize stream events.
            return try await fallbackStreamViaComplete(request: request)
        }

        if !(200..<300).contains(res.statusCode) {
            var bytes: [UInt8] = []
            for try await chunk in res.body {
                bytes.append(contentsOf: chunk)
                if bytes.count > 512 * 1024 { break }
            }
            let json = (try? JSONValue.parse(bytes)) ?? nil
            let msg = _ProviderHTTP.errorMessage(from: json).message ?? "Gemini error"
            let code = _ProviderHTTP.errorMessage(from: json).code
            let retryAfter = _ProviderHTTP.parseRetryAfterSeconds(res.headers)
            let err = _ErrorMapping.sdkErrorFromHTTP(
                provider: name,
                statusCode: res.statusCode,
                message: msg,
                errorCode: code,
                retryAfter: retryAfter,
                raw: json
            )
            throw err
        }

        let sse = SSE.parse(res.body)

        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(StreamEvent(type: .standard(.streamStart)))

                var didStartText = false
                let textId = "text_0"
                var accumulatedText = ""
                var accumulatedParts: [ContentPart] = []
                var finishReasonRaw: String? = nil
                var finalUsage: Usage? = nil

                do {
                    for try await ev in sse {
                        if Task.isCancelled { break }

                        let payload: JSONValue? = {
                            guard let data = ev.data.data(using: .utf8) else { return nil }
                            return try? JSONValue.parse(data)
                        }()
                        guard let payload else { continue }

                        // Each chunk is a full JSON response-ish object (candidates + usageMetadata).
                        if let candidates = payload["candidates"]?.arrayValue, let first = candidates.first {
                            finishReasonRaw = first["finishReason"]?.stringValue ?? finishReasonRaw

                            let content = first["content"]
                            let parts = content?["parts"]?.arrayValue ?? []
                            for p in parts {
                                let isThought = p["thought"]?.boolValue == true
                                let sig = p["thoughtSignature"]?.stringValue
                                if isThought, let t = p["text"]?.stringValue, !t.isEmpty {
                                    // Thought part: text field contains the reasoning content.
                                    accumulatedParts.append(.thinking(ThinkingData(text: t, signature: sig, redacted: false)))
                                    continuation.yield(StreamEvent(type: .standard(.reasoningStart)))
                                    continuation.yield(StreamEvent(type: .standard(.reasoningDelta), reasoningDelta: t))
                                    continuation.yield(StreamEvent(type: .standard(.reasoningEnd)))
                                } else if let t = p["text"]?.stringValue, !t.isEmpty {
                                    if !didStartText {
                                        didStartText = true
                                        continuation.yield(StreamEvent(type: .standard(.textStart), textId: textId))
                                    }
                                    accumulatedText += t
                                    continuation.yield(StreamEvent(type: .standard(.textDelta), delta: t, textId: textId))
                                } else if sig != nil, p["text"] != nil {
                                    // Empty text part with thoughtSignature (Gemini 3 streaming final chunk).
                                    // Attach to the last thinking part if possible.
                                    if let lastIdx = accumulatedParts.lastIndex(where: { $0.kind.rawValue == ContentKind.thinking.rawValue }),
                                       let existing = accumulatedParts[lastIdx].thinking {
                                        accumulatedParts[lastIdx] = .thinking(ThinkingData(text: existing.text, signature: sig, redacted: false))
                                    }
                                }
                                if let fc = p["functionCall"] {
                                    let name = fc["name"]?.stringValue ?? ""
                                    let args = fc["args"]?.objectValue ?? [:]
                                    let callId = fc["id"]?.stringValue ?? "call_\(UUID().uuidString)"
                                    let call = ToolCall(id: callId, name: name, arguments: args, rawArguments: nil, thoughtSignature: sig)
                                    accumulatedParts.append(.toolCall(call))
                                    continuation.yield(StreamEvent(type: .standard(.toolCallStart), toolCall: call))
                                    continuation.yield(StreamEvent(type: .standard(.toolCallEnd), toolCall: call))
                                }
                            }
                        }

                        if let usage = payload["usageMetadata"] {
                            finalUsage = parseUsage(usage)
                        }
                    }

                    if didStartText {
                        continuation.yield(StreamEvent(type: .standard(.textEnd), textId: textId))
                    }

                    if !accumulatedText.isEmpty {
                        accumulatedParts.insert(.text(accumulatedText), at: 0)
                    }

                    let finish = FinishReason(reason: mapFinishReason(finishReasonRaw, hasToolCalls: accumulatedParts.contains(where: { $0.kind.rawValue == ContentKind.toolCall.rawValue })), raw: finishReasonRaw)
                    let usage = finalUsage ?? Usage(inputTokens: 0, outputTokens: 0)
                    let msg = Message(role: .assistant, content: accumulatedParts)
                    let response = Response(
                        id: "gemini_stream",
                        model: request.model,
                        provider: name,
                        message: msg,
                        finishReason: finish,
                        usage: usage,
                        raw: nil,
                        warnings: [],
                        rateLimit: _ProviderHTTP.parseRateLimitInfo(res.headers)
                    )
                    continuation.yield(StreamEvent(type: .standard(.finish), finishReason: finish, usage: usage, response: response))
                    continuation.finish()
                } catch {
                    continuation.yield(StreamEvent(type: .standard(.error), error: (error as? SDKError) ?? StreamError(message: String(describing: error), cause: error)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func supportsToolChoice(_ mode: ToolChoiceMode) -> Bool {
        true
    }

    // MARK: - Request/Response Translation

    private func buildRequestBody(request: Request, stream: Bool) throws -> [UInt8] {
        var systemParts: [JSONValue] = []
        var contents: [JSONValue] = []

        func translatePart(_ part: ContentPart, role: Role) throws -> [JSONValue] {
            func wrapFunctionResponse(_ value: JSONValue) -> JSONValue {
                // Gemini expects `functionResponse.response` to be an object (protobuf Struct).
                // Wrap scalars/arrays so tool results like `4` become `{ "result": 4 }`.
                if value.objectValue != nil { return value }
                return .object(["result": value])
            }

            switch part.kind.rawValue {
            case ContentKind.text.rawValue:
                return [.object(["text": .string(part.text ?? "")])]
            case ContentKind.image.rawValue:
                guard let image = part.image else { return [] }
                if let url = image.url {
                    if _ProviderHTTP.isProbablyLocalFilePath(url) {
                        let bytes = try _ProviderHTTP.readLocalFileBytes(url)
                        let mime = image.mediaType ?? _ProviderHTTP.mimeType(forPath: url) ?? "image/png"
                        return [.object(["inlineData": .object(["mimeType": .string(mime), "data": .string(_ProviderHTTP.base64(bytes))])])]
                    }
                    let mime = image.mediaType ?? _ProviderHTTP.mimeType(forPath: url) ?? "image/png"
                    return [.object(["fileData": .object(["mimeType": .string(mime), "fileUri": .string(url)])])]
                }
                if let data = image.data {
                    let mime = image.mediaType ?? "image/png"
                    return [.object(["inlineData": .object(["mimeType": .string(mime), "data": .string(_ProviderHTTP.base64(data))])])]
                }
                return []
            case ContentKind.toolCall.rawValue:
                guard let call = part.toolCall else { return [] }
                var obj: [String: JSONValue] = [
                    "functionCall": .object([
                        "name": .string(call.name),
                        "args": .object(call.arguments),
                    ]),
                ]
                // Gemini tool calling requires round-tripping `thoughtSignature` for functionCall parts.
                if let sig = call.thoughtSignature, !sig.isEmpty {
                    obj["thoughtSignature"] = .string(sig)
                }
                return [.object(obj)]
            case ContentKind.toolResult.rawValue:
                guard let tr = part.toolResult else { return [] }
                let fname = tr.toolCallId // fallback; adapter should use message.name when available
                var frObj: [String: JSONValue] = [
                    "name": .string(fname),
                    "response": wrapFunctionResponse(tr.content),
                ]
                // Include the function call id for proper matching when the API provides one.
                if !tr.toolCallId.hasPrefix("call_") {
                    frObj["id"] = .string(tr.toolCallId)
                }
                return [.object(["functionResponse": .object(frObj)])]
            default:
                throw InvalidRequestError(message: "Unsupported content kind for Gemini: \(part.kind.rawValue)", provider: name, statusCode: nil, errorCode: nil, retryable: false)
            }
        }

        for msg in request.messages {
            switch msg.role {
            case .system, .developer:
                let t = msg.text
                if !t.isEmpty { systemParts.append(.object(["text": .string(t)])) }
            case .user, .assistant, .tool:
                let role: String = {
                    switch msg.role {
                    case .assistant: return "model"
                    default: return "user"
                    }
                }()
                var parts: [JSONValue] = []
                for p in msg.content {
                    parts.append(contentsOf: try translatePart(p, role: msg.role))
                }
                // Tool results must be sent in a user message with functionResponse parts.
                if msg.role == .tool,
                   let toolName = msg.name,
                   let tr = msg.content.first(where: { $0.kind.rawValue == ContentKind.toolResult.rawValue })?.toolResult
                {
                    let response = (tr.content.objectValue != nil) ? tr.content : .object(["result": tr.content])
                    var frObj: [String: JSONValue] = ["name": .string(toolName), "response": response]
                    if let callId = msg.toolCallId, !callId.hasPrefix("call_") {
                        frObj["id"] = .string(callId)
                    }
                    parts = [.object(["functionResponse": .object(frObj)])]
                }
                if !parts.isEmpty {
                    contents.append(.object(["role": .string(role), "parts": .array(parts)]))
                }
            }
        }

        var root: [String: JSONValue] = [
            "contents": .array(contents),
        ]

        if !systemParts.isEmpty {
            root["systemInstruction"] = .object(["parts": .array(systemParts)])
        }

        if let temperature = request.temperature {
            root["generationConfig"] = .object(["temperature": .number(temperature)])
        }

        if let maxTokens = request.maxTokens {
            var gen = (root["generationConfig"]?.objectValue) ?? [:]
            gen["maxOutputTokens"] = .number(Double(maxTokens))
            root["generationConfig"] = .object(gen)
        }

        if let rf = request.responseFormat {
            // Gemini supports responseSchema; map json_schema best-effort.
            if rf.type == "json_schema", let schema = rf.jsonSchema {
                var gen = (root["generationConfig"]?.objectValue) ?? [:]
                gen["responseMimeType"] = .string("application/json")
                gen["responseSchema"] = schema
                root["generationConfig"] = .object(gen)
            } else if rf.type == "json" {
                var gen = (root["generationConfig"]?.objectValue) ?? [:]
                gen["responseMimeType"] = .string("application/json")
                root["generationConfig"] = .object(gen)
            }
        }

        if let tools = request.tools, !tools.isEmpty {
            root["tools"] = .array([
                .object([
                    "functionDeclarations": .array(tools.map { tool in
                        .object([
                            "name": .string(tool.name),
                            "description": .string(tool.description),
                            "parameters": sanitizeToolSchemaForGemini(tool.parameters),
                        ])
                    }),
                ]),
            ])

            if let choice = request.toolChoice {
                root["toolConfig"] = .object(["functionCallingConfig": mapToolChoice(choice)])
            }
        }

        // Provider options escape hatch: shallow merge into root (gemini-specific).
        for (k, v) in request.optionsObject(for: name) {
            root[k] = v
        }

        return try _ProviderHTTP.jsonBytes(.object(root))
    }

    /// Gemini function declaration schemas reject some standard JSON-Schema fields
    /// (notably `additionalProperties`), so strip unsupported keys recursively.
    private func sanitizeToolSchemaForGemini(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let obj):
            var out: [String: JSONValue] = [:]
            for (k, v) in obj where k != "additionalProperties" {
                out[k] = sanitizeToolSchemaForGemini(v)
            }
            return .object(out)
        case .array(let arr):
            return .array(arr.map { sanitizeToolSchemaForGemini($0) })
        default:
            return value
        }
    }

    private func mapToolChoice(_ choice: ToolChoice) -> JSONValue {
        switch choice.mode {
        case .auto:
            return .object(["mode": .string("AUTO")])
        case .none:
            return .object(["mode": .string("NONE")])
        case .required:
            return .object(["mode": .string("ANY")])
        case .named:
            return .object([
                "mode": .string("ANY"),
                "allowedFunctionNames": .array([.string(choice.toolName ?? "")]),
            ])
        }
    }

    private func parseResponse(json: JSONValue, headers: HTTPHeaders, requestedModel: String) throws -> Response {
        let candidates = json["candidates"]?.arrayValue ?? []
        let first = candidates.first

        let finishRaw = first?["finishReason"]?.stringValue

        var parts: [ContentPart] = []
        if let content = first?["content"], let p = content["parts"]?.arrayValue {
            for part in p {
                let isThought = part["thought"]?.boolValue == true
                let sig = part["thoughtSignature"]?.stringValue
                if isThought, let t = part["text"]?.stringValue, !t.isEmpty {
                    // Thought part: the boolean flag marks this as reasoning content.
                    parts.append(.thinking(ThinkingData(text: t, signature: sig, redacted: false)))
                } else if let t = part["text"]?.stringValue, !t.isEmpty {
                    parts.append(.text(t))
                } else if sig != nil, part["text"] != nil {
                    // Empty text with thoughtSignature — attach to last thinking part.
                    if let lastIdx = parts.lastIndex(where: { $0.kind.rawValue == ContentKind.thinking.rawValue }),
                       let existing = parts[lastIdx].thinking {
                        parts[lastIdx] = .thinking(ThinkingData(text: existing.text, signature: sig, redacted: false))
                    }
                }
                if let fc = part["functionCall"] {
                    let name = fc["name"]?.stringValue ?? ""
                    let args = fc["args"]?.objectValue ?? [:]
                    let callId = fc["id"]?.stringValue ?? "call_\(UUID().uuidString)"
                    parts.append(.toolCall(ToolCall(id: callId, name: name, arguments: args, rawArguments: nil, thoughtSignature: sig)))
                }
            }
        }

        let usage = parseUsage(json["usageMetadata"])
        let finish = FinishReason(reason: mapFinishReason(finishRaw, hasToolCalls: parts.contains(where: { $0.kind.rawValue == ContentKind.toolCall.rawValue })), raw: finishRaw)

        return Response(
            id: "gemini_\(UUID().uuidString)",
            model: requestedModel,
            provider: name,
            message: Message(role: .assistant, content: parts),
            finishReason: finish,
            usage: usage,
            raw: json,
            warnings: [],
            rateLimit: _ProviderHTTP.parseRateLimitInfo(headers)
        )
    }

    private func mapFinishReason(_ raw: String?, hasToolCalls: Bool) -> String {
        if hasToolCalls { return "tool_calls" }
        switch raw {
        case "STOP": return "stop"
        case "MAX_TOKENS": return "length"
        case "SAFETY", "RECITATION": return "content_filter"
        case nil: return "other"
        default: return "other"
        }
    }

    private func parseUsage(_ usage: JSONValue?) -> Usage {
        guard let usage, let obj = usage.objectValue else {
            return Usage(inputTokens: 0, outputTokens: 0, raw: usage)
        }
        func int(_ v: JSONValue?) -> Int? {
            if let n = v?.doubleValue { return Int(n) }
            return nil
        }
        let input = int(obj["promptTokenCount"]) ?? 0
        let output = int(obj["candidatesTokenCount"]) ?? 0
        let cached = int(obj["cachedContentTokenCount"])
        let reasoning = int(obj["thoughtsTokenCount"])
        return Usage(
            inputTokens: input,
            outputTokens: output,
            reasoningTokens: reasoning,
            cacheReadTokens: cached,
            cacheWriteTokens: nil,
            raw: usage
        )
    }

    private func fallbackStreamViaComplete(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let response = try await complete(request: request)

        return AsyncThrowingStream { continuation in
            continuation.yield(StreamEvent(type: .standard(.streamStart)))

            if !response.text.isEmpty {
                let textId = "text_0"
                continuation.yield(StreamEvent(type: .standard(.textStart), textId: textId))
                continuation.yield(StreamEvent(type: .standard(.textDelta), delta: response.text, textId: textId))
                continuation.yield(StreamEvent(type: .standard(.textEnd), textId: textId))
            }

            if let reasoning = response.reasoning, !reasoning.isEmpty {
                continuation.yield(StreamEvent(type: .standard(.reasoningStart)))
                continuation.yield(StreamEvent(type: .standard(.reasoningDelta), reasoningDelta: reasoning))
                continuation.yield(StreamEvent(type: .standard(.reasoningEnd)))
            }

            for call in response.toolCalls {
                continuation.yield(StreamEvent(type: .standard(.toolCallStart), toolCall: ToolCall(id: call.id, name: call.name, arguments: [:], rawArguments: call.rawArguments)))
                continuation.yield(StreamEvent(type: .standard(.toolCallEnd), toolCall: call))
            }

            continuation.yield(
                StreamEvent(
                    type: .standard(.finish),
                    finishReason: response.finishReason,
                    usage: response.usage,
                    response: response
                )
            )
            continuation.finish()
        }
    }
}
