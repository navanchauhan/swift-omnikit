import Foundation

import OmniHTTP

public final class OpenAIAdapter: ProviderAdapter, @unchecked Sendable {
    public let name: String = "openai"

    private let apiKey: String
    private let baseURL: String
    private let organizationID: String?
    private let projectID: String?
    private let transport: HTTPTransport
    private let responsesWebSocketTransport: OpenAIResponsesWebSocketTransport?

    public init(
        apiKey: String,
        baseURL: String? = nil,
        organizationID: String? = nil,
        projectID: String? = nil,
        transport: HTTPTransport,
        responsesWebSocketTransport: OpenAIResponsesWebSocketTransport? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? "https://api.openai.com/v1"
        self.organizationID = organizationID
        self.projectID = projectID
        self.transport = transport
        self.responsesWebSocketTransport = responsesWebSocketTransport
    }

    public func complete(request: Request) async throws -> Response {
        try await request.abortSignal?.check()

        let url = try _ProviderHTTP.makeURL(baseURL: baseURL, path: "/responses")
        let body = try buildRequestBody(request: request, stream: false)
        var headers = HTTPHeaders()
        headers.set(name: "authorization", value: "Bearer \(apiKey)")
        headers.set(name: "content-type", value: "application/json")
        if let organizationID {
            headers.set(name: "openai-organization", value: organizationID)
        }
        if let projectID {
            headers.set(name: "openai-project", value: projectID)
        }

        let timeout = request.timeout?.asConfig.total
        let http = try await transport.send(
            HTTPRequest(method: .post, url: url, headers: headers, body: .bytes(body)),
            timeout: timeout
        )
        if !(200..<300).contains(http.statusCode) {
            let json = _ProviderHTTP.parseJSONBody(http)
            let msg = _ProviderHTTP.errorMessage(from: json).message ?? "OpenAI error"
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

        let url = try _ProviderHTTP.makeURL(baseURL: baseURL, path: "/responses")
        let providerOptions = request.optionsObject(for: name)
        let body = try buildRequestBody(request: request, stream: true)
        var headers = HTTPHeaders()
        headers.set(name: "authorization", value: "Bearer \(apiKey)")
        headers.set(name: "content-type", value: "application/json")
        headers.set(name: "accept", value: "text/event-stream")
        if let organizationID {
            headers.set(name: "openai-organization", value: organizationID)
        }
        if let projectID {
            headers.set(name: "openai-project", value: projectID)
        }

        let timeout = request.timeout?.asConfig.total
        let streamTransportMode = providerOptions[OpenAIProviderOptionKeys.responsesTransport]?.stringValue?.lowercased() ?? "sse"
        if streamTransportMode == "websocket" {
            return try await streamViaWebSocket(
                request: request,
                headers: headers,
                providerOptions: providerOptions,
                body: body,
                timeout: timeout
            )
        }

        let res = try await transport.openStream(
            HTTPRequest(method: .post, url: url, headers: headers, body: .bytes(body)),
            timeout: timeout
        )

        if !(200..<300).contains(res.statusCode) {
            // Consume one chunk (best-effort) to extract JSON error.
            var bytes: [UInt8] = []
            for try await chunk in res.body {
                bytes.append(contentsOf: chunk)
                if bytes.count > 512 * 1024 { break }
            }
            let json = (try? JSONValue.parse(bytes)) ?? nil
            let msg = _ProviderHTTP.errorMessage(from: json).message ?? "OpenAI error"
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
                var didStartText = false
                let textId = "text_0"
                var accumulatedText = ""

                struct PartialToolCall {
                    var id: String
                    var name: String?
                    var rawArgs: String
                }
                var toolCalls: [String: PartialToolCall] = [:]
                var toolCallOrder: [String] = []

                continuation.yield(StreamEvent(type: .standard(.streamStart)))

                do {
                    for try await event in sse {
                        if Task.isCancelled { break }

                        // OpenAI "compat" streams sometimes send [DONE].
                        if event.data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                            continue
                        }

                        let payload: JSONValue? = {
                            guard let data = event.data.data(using: .utf8) else { return nil }
                            return try? JSONValue.parse(data)
                        }()

                        let type = payload?["type"]?.stringValue ?? event.event ?? ""

                        switch type {
                        case "response.output_text.delta":
                            let delta = payload?["delta"]?.stringValue
                                ?? payload?["text"]?.stringValue
                                ?? ""
                            if !didStartText {
                                didStartText = true
                                continuation.yield(StreamEvent(type: .standard(.textStart), textId: textId))
                            }
                            if !delta.isEmpty {
                                accumulatedText += delta
                                continuation.yield(StreamEvent(type: .standard(.textDelta), delta: delta, textId: textId, raw: payload))
                            }
                        case "response.output_text.done":
                            if didStartText {
                                continuation.yield(StreamEvent(type: .standard(.textEnd), textId: textId, raw: payload))
                            }
                        case "response.function_call_arguments.delta":
                            let callId = payload?["call_id"]?.stringValue
                                ?? payload?["id"]?.stringValue
                                ?? payload?["item_id"]?.stringValue
                                ?? UUID().uuidString
                            let delta = payload?["delta"]?.stringValue ?? ""
                            let name = payload?["name"]?.stringValue ?? payload?["tool_name"]?.stringValue
                            if toolCalls[callId] == nil {
                                toolCalls[callId] = PartialToolCall(id: callId, name: name, rawArgs: "")
                                toolCallOrder.append(callId)
                                continuation.yield(StreamEvent(type: .standard(.toolCallStart), toolCall: ToolCall(id: callId, name: name ?? "", arguments: [:], rawArguments: "")))
                            }
                            toolCalls[callId]!.rawArgs += delta
                            let partial = toolCalls[callId]!
                            continuation.yield(
                                StreamEvent(
                                    type: .standard(.toolCallDelta),
                                    toolCall: ToolCall(id: callId, name: partial.name ?? "", arguments: [:], rawArguments: partial.rawArgs),
                                    raw: payload
                                )
                            )
                        case "response.function_call_arguments.done":
                            let callId = payload?["call_id"]?.stringValue
                                ?? payload?["id"]?.stringValue
                                ?? payload?["item_id"]?.stringValue
                            if let callId, let partial = toolCalls[callId] {
                                let parsedArgs: [String: JSONValue] = {
                                    guard let data = partial.rawArgs.data(using: .utf8),
                                          let json = try? JSONValue.parse(data),
                                          let obj = json.objectValue
                                    else { return [:] }
                                    return obj
                                }()
                                continuation.yield(
                                    StreamEvent(
                                        type: .standard(.toolCallEnd),
                                        toolCall: ToolCall(id: callId, name: partial.name ?? "", arguments: parsedArgs, rawArguments: partial.rawArgs),
                                        raw: payload
                                    )
                                )
                            }
                        case "response.completed":
                            guard let payload else { break }
                            let responseJSON = payload["response"] ?? payload
                            var response = try parseResponse(json: responseJSON, headers: res.headers, requestedModel: request.model)
                            if response.text.isEmpty, !accumulatedText.isEmpty {
                                // Some Responses API streams don't include full message content in the final
                                // completed payload. Prefer the accumulated deltas as the canonical text.
                                var parts = response.message.content
                                if !parts.contains(where: { $0.kind.rawValue == ContentKind.text.rawValue }) {
                                    parts.insert(.text(accumulatedText), at: 0)
                                }
                                response = Response(
                                    id: response.id,
                                    model: response.model,
                                    provider: response.provider,
                                    message: Message(role: .assistant, content: parts),
                                    finishReason: response.finishReason,
                                    usage: response.usage,
                                    raw: response.raw,
                                    warnings: response.warnings,
                                    rateLimit: response.rateLimit
                                )
                            }
                            continuation.yield(
                                StreamEvent(
                                    type: .standard(.finish),
                                    finishReason: response.finishReason,
                                    usage: response.usage,
                                    response: response,
                                    raw: payload
                                )
                            )
                            continuation.finish()
                            return
                        default:
                            continuation.yield(StreamEvent(type: .standard(.providerEvent), raw: payload))
                        }
                    }

                    // If the stream ended without a completed payload, emit a minimal finish.
                    let message = Message(role: .assistant, content: accumulatedText.isEmpty ? [] : [.text(accumulatedText)])
                    let response = Response(
                        id: "stream_ended",
                        model: request.model,
                        provider: name,
                        message: message,
                        finishReason: FinishReason(reason: toolCallOrder.isEmpty ? "stop" : "tool_calls", raw: nil),
                        usage: Usage(inputTokens: 0, outputTokens: 0),
                        raw: nil,
                        warnings: [],
                        rateLimit: _ProviderHTTP.parseRateLimitInfo(res.headers)
                    )
                    continuation.yield(StreamEvent(type: .standard(.finish), finishReason: response.finishReason, usage: response.usage, response: response))
                    continuation.finish()
                } catch {
                    continuation.yield(StreamEvent(type: .standard(.error), error: (error as? SDKError) ?? StreamError(message: String(describing: error), cause: error)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamViaWebSocket(
        request: Request,
        headers: HTTPHeaders,
        providerOptions: [String: JSONValue],
        body: [UInt8],
        timeout: Duration?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let wsURL = try makeWebSocketURL(providerOptions: providerOptions)
        let bodyJSON = try JSONValue.parse(body)
        var frame = bodyJSON.objectValue ?? [:]
        frame["type"] = .string("response.create")
        frame["stream"] = .bool(true)

        let websocket = responsesWebSocketTransport ?? defaultWebSocketTransport()
        let payloads = try await websocket.openResponseEventStream(
            url: wsURL,
            headers: headers,
            createEvent: .object(frame),
            timeout: timeout
        )

        return AsyncThrowingStream { continuation in
            Task {
                var didStartText = false
                let textId = "text_0"
                var accumulatedText = ""

                struct PartialToolCall {
                    var id: String
                    var name: String?
                    var rawArgs: String
                }
                var toolCalls: [String: PartialToolCall] = [:]
                var toolCallOrder: [String] = []

                continuation.yield(StreamEvent(type: .standard(.streamStart)))

                do {
                    for try await payload in payloads {
                        if Task.isCancelled { break }
                        let type = payload["type"]?.stringValue ?? ""

                        switch type {
                        case "response.output_text.delta":
                            let delta = payload["delta"]?.stringValue
                                ?? payload["text"]?.stringValue
                                ?? ""
                            if !didStartText {
                                didStartText = true
                                continuation.yield(StreamEvent(type: .standard(.textStart), textId: textId))
                            }
                            if !delta.isEmpty {
                                accumulatedText += delta
                                continuation.yield(StreamEvent(type: .standard(.textDelta), delta: delta, textId: textId, raw: payload))
                            }
                        case "response.output_text.done":
                            if didStartText {
                                continuation.yield(StreamEvent(type: .standard(.textEnd), textId: textId, raw: payload))
                            }
                        case "response.output_item.added":
                            // Capture function call metadata (name, call_id) before argument deltas arrive.
                            // OpenAI uses two IDs: item.id (the item ID) and item.call_id (the call ID).
                            // Later delta events reference the call via call_id which may be EITHER of these.
                            // Register under both so deltas always find the existing entry.
                            let itemType = payload["item"]?["type"]?.stringValue
                            if itemType == "function_call" {
                                let itemCallId = payload["item"]?["call_id"]?.stringValue
                                let itemId = payload["item"]?["id"]?.stringValue
                                let primaryId = itemCallId ?? itemId ?? UUID().uuidString
                                let name = payload["item"]?["name"]?.stringValue
                                if toolCalls[primaryId] == nil {
                                    let partial = PartialToolCall(id: primaryId, name: name, rawArgs: "")
                                    toolCalls[primaryId] = partial
                                    // Also register under the alternate ID so delta events find us.
                                    if let itemId, itemId != primaryId {
                                        toolCalls[itemId] = partial
                                    }
                                    if let itemCallId, itemCallId != primaryId {
                                        toolCalls[itemCallId] = partial
                                    }
                                    toolCallOrder.append(primaryId)
                                    continuation.yield(StreamEvent(
                                        type: .standard(.toolCallStart),
                                        toolCall: ToolCall(id: primaryId, name: name ?? "", arguments: [:], rawArguments: ""),
                                        raw: payload
                                    ))
                                }
                            }
                        case "response.function_call_arguments.delta":
                            let callId = payload["call_id"]?.stringValue
                                ?? payload["id"]?.stringValue
                                ?? payload["item_id"]?.stringValue
                                ?? UUID().uuidString
                            let delta = payload["delta"]?.stringValue ?? ""
                            let name = payload["name"]?.stringValue ?? payload["tool_name"]?.stringValue
                            if toolCalls[callId] == nil {
                                toolCalls[callId] = PartialToolCall(id: callId, name: name, rawArgs: "")
                                toolCallOrder.append(callId)
                                continuation.yield(StreamEvent(type: .standard(.toolCallStart), toolCall: ToolCall(id: callId, name: name ?? "", arguments: [:], rawArguments: "")))
                            } else if let name, toolCalls[callId]?.name == nil {
                                toolCalls[callId]?.name = name
                            }
                            toolCalls[callId]!.rawArgs += delta
                            // Sync rawArgs back to any alias entries pointing to the same call.
                            let updatedPartial = toolCalls[callId]!
                            for (key, val) in toolCalls where val.id == updatedPartial.id && key != callId {
                                toolCalls[key]?.rawArgs = updatedPartial.rawArgs
                            }
                            continuation.yield(
                                StreamEvent(
                                    type: .standard(.toolCallDelta),
                                    toolCall: ToolCall(id: updatedPartial.id, name: updatedPartial.name ?? "", arguments: [:], rawArguments: updatedPartial.rawArgs),
                                    raw: payload
                                )
                            )
                        case "response.function_call_arguments.done":
                            let callId = payload["call_id"]?.stringValue
                                ?? payload["id"]?.stringValue
                                ?? payload["item_id"]?.stringValue
                            if let callId, let partial = toolCalls[callId] {
                                let parsedArgs: [String: JSONValue] = {
                                    guard let data = partial.rawArgs.data(using: .utf8),
                                          let json = try? JSONValue.parse(data),
                                          let obj = json.objectValue
                                    else { return [:] }
                                    return obj
                                }()
                                // Use the canonical ID from the partial (set by output_item.added).
                                continuation.yield(
                                    StreamEvent(
                                        type: .standard(.toolCallEnd),
                                        toolCall: ToolCall(id: partial.id, name: partial.name ?? "", arguments: parsedArgs, rawArguments: partial.rawArgs),
                                        raw: payload
                                    )
                                )
                            }
                        case "response.completed", "response.incomplete":
                            let responseJSON = payload["response"] ?? payload
                            var response = try parseResponse(json: responseJSON, headers: HTTPHeaders(), requestedModel: request.model)
                            if response.text.isEmpty, !accumulatedText.isEmpty {
                                var parts = response.message.content
                                if !parts.contains(where: { $0.kind.rawValue == ContentKind.text.rawValue }) {
                                    parts.insert(.text(accumulatedText), at: 0)
                                }
                                response = Response(
                                    id: response.id,
                                    model: response.model,
                                    provider: response.provider,
                                    message: Message(role: .assistant, content: parts),
                                    finishReason: response.finishReason,
                                    usage: response.usage,
                                    raw: response.raw,
                                    warnings: response.warnings,
                                    rateLimit: response.rateLimit
                                )
                            }
                            continuation.yield(
                                StreamEvent(
                                    type: .standard(.finish),
                                    finishReason: response.finishReason,
                                    usage: response.usage,
                                    response: response,
                                    raw: payload
                                )
                            )
                            continuation.finish()
                            return
                        case "response.error", "response.failed", "error":
                            let msg = _ProviderHTTP.errorMessage(from: payload).message ?? "OpenAI websocket error"
                            let code = _ProviderHTTP.errorMessage(from: payload).code
                            throw _ErrorMapping.sdkErrorFromHTTP(
                                provider: name,
                                statusCode: nil,
                                message: msg,
                                errorCode: code,
                                retryAfter: nil,
                                raw: payload
                            )
                        default:
                            continuation.yield(StreamEvent(type: .standard(.providerEvent), raw: payload))
                        }
                    }

                    let message = Message(role: .assistant, content: accumulatedText.isEmpty ? [] : [.text(accumulatedText)])
                    let response = Response(
                        id: "stream_ended",
                        model: request.model,
                        provider: name,
                        message: message,
                        finishReason: FinishReason(reason: toolCallOrder.isEmpty ? "stop" : "tool_calls", raw: nil),
                        usage: Usage(inputTokens: 0, outputTokens: 0),
                        raw: nil,
                        warnings: [],
                        rateLimit: nil
                    )
                    continuation.yield(StreamEvent(type: .standard(.finish), finishReason: response.finishReason, usage: response.usage, response: response))
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
        let providerOptions = request.optionsObject(for: name)
        let includeNativeWebSearch = providerOptions[OpenAIProviderOptionKeys.includeNativeWebSearch]?.boolValue ?? false
        let webSearchExternalWebAccess = providerOptions[OpenAIProviderOptionKeys.webSearchExternalWebAccess]?.boolValue

        var instructionsParts: [String] = []
        var inputItems: [JSONValue] = []

        func appendMessageItem(role: String, parts: [JSONValue]) {
            inputItems.append(
                .object([
                    "type": .string("message"),
                    "role": .string(role),
                    "content": .array(parts),
                ])
            )
        }

        for msg in request.messages {
            switch msg.role {
            case .system, .developer:
                let t = msg.text
                if !t.isEmpty {
                    instructionsParts.append(t)
                }
            case .user, .assistant:
                let role = (msg.role == .user) ? "user" : "assistant"

                // Messages are encoded as input items. Some parts (tool calls, reasoning items) are
                // top-level input items, so we need to flush message content to preserve ordering.
                var contentParts: [JSONValue] = []
                func flushMessageIfNeeded() {
                    if !contentParts.isEmpty {
                        appendMessageItem(role: role, parts: contentParts)
                        contentParts.removeAll(keepingCapacity: true)
                    }
                }

                for part in msg.content {
                    switch part.kind.rawValue {
                    case ContentKind.text.rawValue:
                        let textType = (msg.role == .user) ? "input_text" : "output_text"
                        contentParts.append(.object([
                            "type": .string(textType),
                            "text": .string(part.text ?? ""),
                        ]))
                    case ContentKind.image.rawValue:
                        guard let image = part.image else {
                            continue
                        }
                        let imageURL: String
                        if let url = image.url {
                            if _ProviderHTTP.isProbablyLocalFilePath(url) {
                                let bytes = try _ProviderHTTP.readLocalFileBytes(url)
                                let mime = image.mediaType ?? _ProviderHTTP.mimeType(forPath: url) ?? "image/png"
                                imageURL = "data:\(mime);base64,\(_ProviderHTTP.base64(bytes))"
                            } else {
                                imageURL = url
                            }
                        } else if let data = image.data {
                            let mime = image.mediaType ?? "image/png"
                            imageURL = "data:\(mime);base64,\(_ProviderHTTP.base64(data))"
                        } else {
                            throw InvalidRequestError(
                                message: "Image content part must have url or data",
                                provider: name,
                                statusCode: nil,
                                errorCode: nil,
                                retryable: false
                            )
                        }
                        contentParts.append(.object([
                            "type": .string("input_image"),
                            "image_url": .string(imageURL),
                        ]))
                    case ContentKind.toolCall.rawValue:
                        flushMessageIfNeeded()
                        if let call = part.toolCall {
                            // Tool calls are top-level input items for the Responses API.
                            let argsString: String = {
                                if let raw = call.rawArguments { return raw }
                                let obj = JSONValue.object(call.arguments)
                                return _ProviderHTTP.stringifyJSON(obj)
                            }()
                            var obj: [String: JSONValue] = [
                                "type": .string("function_call"),
                                "call_id": .string(call.id),
                                "arguments": .string(argsString),
                            ]
                            // OpenAI requires a non-empty name on function_call items.
                            if !call.name.isEmpty {
                                obj["name"] = .string(call.name)
                            }
                            if let itemId = call.providerItemId, !itemId.isEmpty {
                                obj["id"] = .string(itemId)
                            }
                            inputItems.append(.object(obj))
                        }
                    case "openai_input_item":
                        flushMessageIfNeeded()
                        if let data = part.data {
                            inputItems.append(data)
                        }
                    default:
                        // Audio/document/thinking not supported for OpenAI Responses in this implementation.
                        throw InvalidRequestError(
                            message: "Unsupported content part kind for OpenAI: \(part.kind.rawValue)",
                            provider: name,
                            statusCode: nil,
                            errorCode: nil,
                            retryable: false
                        )
                    }
                }

                flushMessageIfNeeded()
            case .tool:
                // Tool results are top-level items.
                // Prefer msg.toolCallId; fallback to ToolResultData.
                let toolCallId = msg.toolCallId ?? msg.content.first(where: { $0.kind.rawValue == ContentKind.toolResult.rawValue })?.toolResult?.toolCallId
                guard let callId = toolCallId else { continue }
                let output: String = {
                    if let tr = msg.content.first(where: { $0.kind.rawValue == ContentKind.toolResult.rawValue })?.toolResult {
                        return _ProviderHTTP.stringifyJSON(tr.content)
                    }
                    return msg.text
                }()
                inputItems.append(.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(callId),
                    "output": .string(output),
                ]))
            }
        }

        var root: [String: JSONValue] = [
            "model": .string(request.model),
            "input": .array(inputItems),
        ]

        if let previousResponseId = request.previousResponseId,
           !previousResponseId.isEmpty {
            root["previous_response_id"] = .string(previousResponseId)
        }

        if !instructionsParts.isEmpty {
            root["instructions"] = .string(instructionsParts.joined(separator: "\n"))
        }

        if stream {
            root["stream"] = .bool(true)
        }

        if let temperature = request.temperature {
            root["temperature"] = .number(temperature)
        }
        if let topP = request.topP {
            root["top_p"] = .number(topP)
        }
        if let maxTokens = request.maxTokens {
            root["max_output_tokens"] = .number(Double(maxTokens))
        }
        if let stop = request.stopSequences, !stop.isEmpty {
            root["stop"] = .array(stop.map { .string($0) })
        }

        if let effort = request.reasoningEffort {
            root["reasoning"] = .object(["effort": .string(effort)])
        }

        if let rf = request.responseFormat {
            var rfObj: [String: JSONValue] = ["type": .string(rf.type)]
            if let schema = rf.jsonSchema {
                rfObj["json_schema"] = schema
                rfObj["strict"] = .bool(rf.strict)
            }
            root["response_format"] = .object(rfObj)
        }

        var responseTools: [JSONValue] = []
        if let tools = request.tools, !tools.isEmpty {
            responseTools.append(contentsOf: tools.map { tool in
                .object([
                    "type": .string("function"),
                    // NOTE: OpenAI Responses API expects function tool definitions to have
                    // top-level name/description/parameters (not nested under "function").
                    // This differs from Chat Completions tool format.
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "parameters": tool.parameters,
                ])
            })
        }

        if includeNativeWebSearch {
            var webSearchTool: [String: JSONValue] = [
                "type": .string("web_search"),
            ]
            if let webSearchExternalWebAccess {
                webSearchTool["external_web_access"] = .bool(webSearchExternalWebAccess)
            }
            responseTools.append(.object(webSearchTool))
        }

        if let hostedTools = providerOptions[OpenAIProviderOptionKeys.hostedTools]?.arrayValue {
            responseTools.append(contentsOf: hostedTools)
        }

        if !responseTools.isEmpty {
            root["tools"] = .array(responseTools)

            if let choice = request.toolChoice {
                root["tool_choice"] = mapToolChoice(choice)
            } else {
                root["tool_choice"] = .string("auto")
            }
        }

        // Provider options escape hatch: shallow-merge into root (openai-specific).
        for (k, v) in providerOptions where !OpenAIProviderOptionKeys.internalKeys.contains(k) {
            root[k] = v
        }

        return try _ProviderHTTP.jsonBytes(.object(root))
    }

    private func mapToolChoice(_ choice: ToolChoice) -> JSONValue {
        switch choice.mode {
        case .auto:
            return .string("auto")
        case .none:
            return .string("none")
        case .required:
            return .string("required")
        case .named:
            let name = choice.toolName ?? ""
            let hostedTypes: Set<String> = [
                "file_search",
                "web_search",
                "web_search_preview",
                "computer_use_preview",
                "image_generation",
                "code_interpreter",
                "mcp",
            ]
            if hostedTypes.contains(name) {
                return .object([
                    "type": .string(name),
                ])
            }
            return .object([
                "type": .string("function"),
                "name": .string(name),
            ])
        }
    }

    private func makeWebSocketURL(providerOptions: [String: JSONValue]) throws -> URL {
        let websocketBase = providerOptions[OpenAIProviderOptionKeys.websocketBaseURL]?.stringValue ?? baseURL
        let httpURL = try _ProviderHTTP.makeURL(baseURL: websocketBase, path: "/responses")
        guard var components = URLComponents(url: httpURL, resolvingAgainstBaseURL: false) else {
            throw OmniHTTPError.invalidURL(httpURL.absoluteString)
        }

        switch components.scheme?.lowercased() {
        case "wss", "ws":
            break
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        default:
            throw OmniHTTPError.invalidURL(httpURL.absoluteString)
        }

        guard let wsURL = components.url else {
            throw OmniHTTPError.invalidURL(httpURL.absoluteString)
        }
        return wsURL
    }

    private func defaultWebSocketTransport() -> OpenAIResponsesWebSocketTransport {
        #if canImport(Darwin)
        return URLSessionOpenAIResponsesWebSocketTransport()
        #else
        return NIOOpenAIResponsesWebSocketTransport()
        #endif
    }

    private func parseResponse(json: JSONValue, headers: HTTPHeaders, requestedModel: String) throws -> Response {
        let id = json["id"]?.stringValue ?? "resp_\(UUID().uuidString)"
        let model = json["model"]?.stringValue ?? requestedModel
        let output = json["output"]?.arrayValue ?? []

        var parts: [ContentPart] = []
        var toolCalls: [ToolCall] = []

        for item in output {
            let type = item["type"]?.stringValue
            switch type {
            case "message":
                let content = item["content"]?.arrayValue ?? []
                for c in content {
                    let cType = c["type"]?.stringValue
                    switch cType {
                    case "output_text", "text":
                        let t = c["text"]?.stringValue ?? ""
                        if !t.isEmpty { parts.append(.text(t)) }
                    default:
                        break
                    }
                }
            case "reasoning":
                // Reasoning models can emit top-level reasoning items in `output`. When tool calling,
                // these must be round-tripped by including them in subsequent `input` arrays.
                parts.append(ContentPart(kind: .custom("openai_input_item"), data: item))
            case "function_call":
                let itemId = item["id"]?.stringValue
                let callId = item["call_id"]?.stringValue ?? itemId ?? UUID().uuidString
                let name = item["name"]?.stringValue ?? ""
                let rawArgs = item["arguments"]?.stringValue
                let args: [String: JSONValue] = {
                    guard let rawArgs,
                          let data = rawArgs.data(using: .utf8),
                          let parsed = try? JSONValue.parse(data),
                          let obj = parsed.objectValue
                    else { return [:] }
                    return obj
                }()
                let call = ToolCall(id: callId, name: name, arguments: args, rawArguments: rawArgs, providerItemId: itemId)
                toolCalls.append(call)
                parts.append(.toolCall(call))
            default:
                break
            }
        }

        let status = json["status"]?.stringValue
        let incompleteReason = json["incomplete_details"]?["reason"]?.stringValue
        let finishRaw = json["finish_reason"]?.stringValue
        let finishReason: FinishReason = {
            // Treat any response that includes function/tool calls as a tool-calls step, even if the
            // provider reports a different finish_reason (some payloads return "stop" here).
            if !toolCalls.isEmpty {
                return FinishReason(reason: "tool_calls", raw: finishRaw)
            }
            if let finishRaw {
                return FinishReason(reason: mapFinishReason(finishRaw), raw: finishRaw)
            }
            if status == "incomplete" {
                if incompleteReason == "max_output_tokens" {
                    return FinishReason(reason: "length", raw: incompleteReason)
                }
                return FinishReason(reason: "other", raw: incompleteReason ?? status)
            }
            return FinishReason(reason: "stop", raw: status)
        }()

        let usage = parseUsage(json["usage"])

        if parts.isEmpty, let outputText = json["output_text"]?.stringValue, !outputText.isEmpty {
            parts.append(.text(outputText))
        }

        let message = Message(role: .assistant, content: parts)

        return Response(
            id: id,
            model: model,
            provider: name,
            message: message,
            finishReason: finishReason,
            usage: usage,
            raw: json,
            warnings: [],
            rateLimit: _ProviderHTTP.parseRateLimitInfo(headers)
        )
    }

    private func mapFinishReason(_ raw: String) -> String {
        switch raw {
        case "stop": return "stop"
        case "length": return "length"
        case "tool_calls": return "tool_calls"
        case "content_filter": return "content_filter"
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

        let input = int(obj["input_tokens"]) ?? int(obj["prompt_tokens"]) ?? 0
        let output = int(obj["output_tokens"]) ?? int(obj["completion_tokens"]) ?? 0
        let reasoning = int(obj["output_tokens_details"]?["reasoning_tokens"]) ?? int(obj["completion_tokens_details"]?["reasoning_tokens"])
        let cached = int(obj["input_tokens_details"]?["cached_tokens"]) ?? int(obj["prompt_tokens_details"]?["cached_tokens"])

        return Usage(
            inputTokens: input,
            outputTokens: output,
            reasoningTokens: reasoning,
            cacheReadTokens: cached,
            cacheWriteTokens: nil,
            raw: usage
        )
    }
}
