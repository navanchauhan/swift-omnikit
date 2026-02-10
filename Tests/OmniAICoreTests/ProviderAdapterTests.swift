import XCTest

import Foundation

import OmniHTTP
@testable import OmniAICore

private actor StubTransport: HTTPTransport {
    private(set) var lastSendRequest: HTTPRequest?
    private(set) var lastStreamRequest: HTTPRequest?

    private let sendHandler: @Sendable (HTTPRequest) async throws -> HTTPResponse
    private let streamHandler: @Sendable (HTTPRequest) async throws -> HTTPStreamResponse

    init(
        send: @Sendable @escaping (HTTPRequest) async throws -> HTTPResponse = { _ in HTTPResponse(statusCode: 500, headers: HTTPHeaders(), body: []) },
        stream: @Sendable @escaping (HTTPRequest) async throws -> HTTPStreamResponse = { _ in HTTPStreamResponse(statusCode: 500, headers: HTTPHeaders(), body: AsyncThrowingStream { $0.finish() }) }
    ) {
        self.sendHandler = send
        self.streamHandler = stream
    }

    func send(_ request: HTTPRequest, timeout: Duration?) async throws -> HTTPResponse {
        lastSendRequest = request
        return try await sendHandler(request)
    }

    func openStream(_ request: HTTPRequest, timeout: Duration?) async throws -> HTTPStreamResponse {
        lastStreamRequest = request
        return try await streamHandler(request)
    }

    func shutdown() async throws {}
}

private func bodyBytes(_ request: HTTPRequest) -> [UInt8] {
    switch request.body {
    case .none:
        return []
    case .bytes(let b):
        return b
    }
}

private func streamFromSSE(_ s: String) -> HTTPByteStream {
    let bytes = Array(s.utf8)
    return AsyncThrowingStream { continuation in
        continuation.yield(bytes)
        continuation.finish()
    }
}

final class ProviderAdapterTests: XCTestCase {
    func testOpenAIAdapterBuildsResponsesAPIRequestAndParsesUsage() async throws {
        let responseJSON: JSONValue = .object([
            "id": .string("resp_1"),
            "model": .string("gpt-5.2"),
            "output": .array([
                .object([
                    "type": .string("message"),
                    "content": .array([.object(["type": .string("output_text"), "text": .string("Hello")])]),
                ]),
            ]),
            "finish_reason": .string("stop"),
            "usage": .object([
                "prompt_tokens": .number(5),
                "completion_tokens": .number(7),
                "completion_tokens_details": .object(["reasoning_tokens": .number(2)]),
                "prompt_tokens_details": .object(["cached_tokens": .number(3)]),
            ]),
        ])

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        })

        let adapter = OpenAIAdapter(
            apiKey: "sk-test",
            baseURL: "https://api.openai.com/v1",
            organizationID: "org_1",
            projectID: "proj_1",
            transport: transport
        )

        let schema: JSONValue = .object(["type": .string("object")])
        let tool = try Tool(name: "t", description: "tool", parameters: schema)

        let req = Request(
            model: "gpt-5.2",
            messages: [.system("sys"), .developer("dev"), .user("hi")],
            tools: [tool],
            toolChoice: ToolChoice(mode: .named, toolName: "t"),
            providerOptions: ["openai": .object(["foo": .string("bar")])]
        )

        let resp = try await adapter.complete(request: req)
        XCTAssertEqual(resp.text, "Hello")
        XCTAssertEqual(resp.usage.inputTokens, 5)
        XCTAssertEqual(resp.usage.outputTokens, 7)
        XCTAssertEqual(resp.usage.reasoningTokens, 2)
        XCTAssertEqual(resp.usage.cacheReadTokens, 3)

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        XCTAssertTrue(sent.url.absoluteString.contains("/responses"))
        XCTAssertEqual(sent.headers.firstValue(for: "authorization"), "Bearer sk-test")
        XCTAssertEqual(sent.headers.firstValue(for: "openai-organization"), "org_1")
        XCTAssertEqual(sent.headers.firstValue(for: "openai-project"), "proj_1")

        let body = try JSONValue.parse(bodyBytes(sent))
        XCTAssertEqual(body["model"]?.stringValue, "gpt-5.2")
        XCTAssertTrue(body["instructions"]?.stringValue?.contains("sys") ?? false)
        XCTAssertTrue(body["instructions"]?.stringValue?.contains("dev") ?? false)
        XCTAssertEqual(body["foo"]?.stringValue, "bar")
        XCTAssertNotNil(body["tools"])
        XCTAssertNotNil(body["tool_choice"])
    }

    func testOpenAIAdapterReplaysReasoningItemsAndFunctionCallIdsForToolContinuations() async throws {
        let responseJSON: JSONValue = .object([
            "id": .string("resp_1"),
            "model": .string("gpt-5.2"),
            "output": .array([
                .object([
                    "type": .string("message"),
                    "content": .array([.object(["type": .string("output_text"), "text": .string("ok")])]),
                ]),
            ]),
            "finish_reason": .string("stop"),
            "usage": .object(["prompt_tokens": .number(1), "completion_tokens": .number(1)]),
        ])

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        })

        let adapter = OpenAIAdapter(apiKey: "sk-test", transport: transport)

        let reasoningItem: JSONValue = .object([
            "id": .string("rs_1"),
            "type": .string("reasoning"),
            "summary": .array([]),
        ])
        let toolCall = ToolCall(
            id: "call_1",
            name: "add",
            arguments: ["a": .number(2), "b": .number(2)],
            rawArguments: #"{"a":2,"b":2}"#,
            providerItemId: "fc_1"
        )

        let req = Request(
            model: "gpt-5.2",
            messages: [
                .user("Use the add tool to compute 2+2."),
                Message(role: .assistant, content: [
                    ContentPart(kind: .custom("openai_input_item"), data: reasoningItem),
                    .toolCall(toolCall),
                ]),
                .toolResult(toolCallId: "call_1", toolName: "add", content: .number(4), isError: false),
            ]
        )

        _ = try await adapter.complete(request: req)

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        let body = try JSONValue.parse(bodyBytes(sent))
        let input = body["input"]?.arrayValue ?? []

        XCTAssertEqual(input.count, 4)
        XCTAssertEqual(input[0]["type"]?.stringValue, "message")
        XCTAssertEqual(input[1]["type"]?.stringValue, "reasoning")
        XCTAssertEqual(input[1]["id"]?.stringValue, "rs_1")

        XCTAssertEqual(input[2]["type"]?.stringValue, "function_call")
        XCTAssertEqual(input[2]["id"]?.stringValue, "fc_1")
        XCTAssertEqual(input[2]["call_id"]?.stringValue, "call_1")
        XCTAssertEqual(input[2]["name"]?.stringValue, "add")

        XCTAssertEqual(input[3]["type"]?.stringValue, "function_call_output")
        XCTAssertEqual(input[3]["call_id"]?.stringValue, "call_1")
    }

    func testImageTranslationAcrossProviders() async throws {
        let pngBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47] // "\x89PNG" header prefix
        let expectedB64 = Data(pngBytes).base64EncodedString()
        let urlImage = "https://example.com/x.png"

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("omni_image_\(UUID().uuidString).png")
        try Data(pngBytes).write(to: tmpURL)
        let localPath = tmpURL.path

        // OpenAI: input_image with data: URL.
        do {
            let responseJSON: JSONValue = .object([
                "id": .string("resp_1"),
                "model": .string("gpt-5.2"),
                "output": .array([.object(["type": .string("message"), "content": .array([.object(["type": .string("output_text"), "text": .string("ok")])])])]),
                "finish_reason": .string("stop"),
                "usage": .object(["prompt_tokens": .number(1), "completion_tokens": .number(1)]),
            ])

            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })

            let adapter = OpenAIAdapter(apiKey: "sk-test", transport: transport)
            let req = Request(
                model: "gpt-5.2",
                messages: [
                    Message(role: .user, content: [
                        .text("what"),
                        .image(ImageData(data: pngBytes, mediaType: "image/png")),
                    ]),
                ]
            )
            _ = try await adapter.complete(request: req)

            let sentOpt = await transport.lastSendRequest
            let sent = try XCTUnwrap(sentOpt)
            let body = try JSONValue.parse(bodyBytes(sent))
            let input = body["input"]?.arrayValue ?? []
            let msg = input.first(where: { $0["type"]?.stringValue == "message" })
            let parts = msg?["content"]?.arrayValue ?? []
            let img = parts.first(where: { $0["type"]?.stringValue == "input_image" })
            let url = img?["image_url"]?.stringValue ?? ""
            XCTAssertTrue(url.hasPrefix("data:image/png;base64,"))
            XCTAssertTrue(url.contains(expectedB64))
        }

        // OpenAI: URL passthrough.
        do {
            let responseJSON: JSONValue = .object([
                "id": .string("resp_1"),
                "model": .string("gpt-5.2"),
                "output": .array([.object(["type": .string("message"), "content": .array([.object(["type": .string("output_text"), "text": .string("ok")])])])]),
                "finish_reason": .string("stop"),
                "usage": .object(["prompt_tokens": .number(1), "completion_tokens": .number(1)]),
            ])

            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })

            let adapter = OpenAIAdapter(apiKey: "sk-test", transport: transport)
            _ = try await adapter.complete(
                request: Request(
                    model: "gpt-5.2",
                    messages: [Message(role: .user, content: [.image(ImageData(url: urlImage, mediaType: "image/png"))])]
                )
            )

            let sentOpt = await transport.lastSendRequest
            let sent = try XCTUnwrap(sentOpt)
            let body = try JSONValue.parse(bodyBytes(sent))
            let input = body["input"]?.arrayValue ?? []
            let msg = input.first(where: { $0["type"]?.stringValue == "message" })
            let parts = msg?["content"]?.arrayValue ?? []
            let img = parts.first(where: { $0["type"]?.stringValue == "input_image" })
            XCTAssertEqual(img?["image_url"]?.stringValue, urlImage)
        }

        // OpenAI: local file path -> base64 data URL.
        do {
            let responseJSON: JSONValue = .object([
                "id": .string("resp_1"),
                "model": .string("gpt-5.2"),
                "output": .array([.object(["type": .string("message"), "content": .array([.object(["type": .string("output_text"), "text": .string("ok")])])])]),
                "finish_reason": .string("stop"),
                "usage": .object(["prompt_tokens": .number(1), "completion_tokens": .number(1)]),
            ])

            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })

            let adapter = OpenAIAdapter(apiKey: "sk-test", transport: transport)
            _ = try await adapter.complete(
                request: Request(
                    model: "gpt-5.2",
                    messages: [Message(role: .user, content: [.image(ImageData(url: localPath, mediaType: "image/png"))])]
                )
            )

            let sentOpt = await transport.lastSendRequest
            let sent = try XCTUnwrap(sentOpt)
            let body = try JSONValue.parse(bodyBytes(sent))
            let input = body["input"]?.arrayValue ?? []
            let msg = input.first(where: { $0["type"]?.stringValue == "message" })
            let parts = msg?["content"]?.arrayValue ?? []
            let img = parts.first(where: { $0["type"]?.stringValue == "input_image" })
            let url = img?["image_url"]?.stringValue ?? ""
            XCTAssertTrue(url.hasPrefix("data:image/png;base64,"))
            XCTAssertTrue(url.contains(expectedB64))
        }

        // Anthropic: image source base64.
        do {
            let responseJSON: JSONValue = .object([
                "id": .string("msg_1"),
                "model": .string("claude-opus-4-6"),
                "content": .array([.object(["type": .string("text"), "text": .string("ok")])]),
                "stop_reason": .string("end_turn"),
                "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
            ])

            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })

            let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)
            let req = Request(
                model: "claude-opus-4-6",
                messages: [
                    Message(role: .user, content: [
                        .text("what"),
                        .image(ImageData(data: pngBytes, mediaType: "image/png")),
                    ]),
                ]
            )
            _ = try await adapter.complete(request: req)

            let sentOpt = await transport.lastSendRequest
            let sent = try XCTUnwrap(sentOpt)
            let body = try JSONValue.parse(bodyBytes(sent))
            let msgs = body["messages"]?.arrayValue ?? []
            let first = msgs.first
            let content = first?["content"]?.arrayValue ?? []
            let img = content.first(where: { $0["type"]?.stringValue == "image" })
            let src = img?["source"]
            XCTAssertEqual(src?["type"]?.stringValue, "base64")
            XCTAssertEqual(src?["media_type"]?.stringValue, "image/png")
            XCTAssertEqual(src?["data"]?.stringValue, expectedB64)
        }

        // Anthropic: URL passthrough.
        do {
            let responseJSON: JSONValue = .object([
                "id": .string("msg_1"),
                "model": .string("claude-opus-4-6"),
                "content": .array([.object(["type": .string("text"), "text": .string("ok")])]),
                "stop_reason": .string("end_turn"),
                "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
            ])

            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })

            let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)
            _ = try await adapter.complete(
                request: Request(
                    model: "claude-opus-4-6",
                    messages: [Message(role: .user, content: [.image(ImageData(url: urlImage, mediaType: "image/png"))])]
                )
            )

            let sentOpt = await transport.lastSendRequest
            let sent = try XCTUnwrap(sentOpt)
            let body = try JSONValue.parse(bodyBytes(sent))
            let msgs = body["messages"]?.arrayValue ?? []
            let content = msgs.first?["content"]?.arrayValue ?? []
            let img = content.first(where: { $0["type"]?.stringValue == "image" })
            let src = img?["source"]
            XCTAssertEqual(src?["type"]?.stringValue, "url")
            XCTAssertEqual(src?["url"]?.stringValue, urlImage)
        }

        // Anthropic: local file path -> base64.
        do {
            let responseJSON: JSONValue = .object([
                "id": .string("msg_1"),
                "model": .string("claude-opus-4-6"),
                "content": .array([.object(["type": .string("text"), "text": .string("ok")])]),
                "stop_reason": .string("end_turn"),
                "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
            ])

            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })

            let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)
            _ = try await adapter.complete(
                request: Request(
                    model: "claude-opus-4-6",
                    messages: [Message(role: .user, content: [.image(ImageData(url: localPath, mediaType: "image/png"))])]
                )
            )

            let sentOpt = await transport.lastSendRequest
            let sent = try XCTUnwrap(sentOpt)
            let body = try JSONValue.parse(bodyBytes(sent))
            let msgs = body["messages"]?.arrayValue ?? []
            let content = msgs.first?["content"]?.arrayValue ?? []
            let img = content.first(where: { $0["type"]?.stringValue == "image" })
            let src = img?["source"]
            XCTAssertEqual(src?["type"]?.stringValue, "base64")
            XCTAssertEqual(src?["data"]?.stringValue, expectedB64)
        }

        // Gemini: inlineData base64.
        do {
            let responseJSON: JSONValue = .object([
                "candidates": .array([
                    .object([
                        "finishReason": .string("STOP"),
                        "content": .object(["parts": .array([.object(["text": .string("ok")])])]),
                    ]),
                ]),
                "usageMetadata": .object(["promptTokenCount": .number(1), "candidatesTokenCount": .number(1)]),
            ])

            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })

            let adapter = GeminiAdapter(apiKey: "gemini-test", transport: transport)
            let req = Request(
                model: "gemini-3-flash-preview",
                messages: [
                    Message(role: .user, content: [
                        .text("what"),
                        .image(ImageData(data: pngBytes, mediaType: "image/png")),
                    ]),
                ]
            )
            _ = try await adapter.complete(request: req)

            let sentOpt = await transport.lastSendRequest
            let sent = try XCTUnwrap(sentOpt)
            let body = try JSONValue.parse(bodyBytes(sent))
            let contents = body["contents"]?.arrayValue ?? []
            let first = contents.first
            let parts = first?["parts"]?.arrayValue ?? []
            let inline = parts.first(where: { $0["inlineData"] != nil })?["inlineData"]
            XCTAssertEqual(inline?["mimeType"]?.stringValue, "image/png")
            XCTAssertEqual(inline?["data"]?.stringValue, expectedB64)
        }

        // Gemini: URL passthrough uses fileData.
        do {
            let responseJSON: JSONValue = .object([
                "candidates": .array([
                    .object([
                        "finishReason": .string("STOP"),
                        "content": .object(["parts": .array([.object(["text": .string("ok")])])]),
                    ]),
                ]),
                "usageMetadata": .object(["promptTokenCount": .number(1), "candidatesTokenCount": .number(1)]),
            ])

            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })

            let adapter = GeminiAdapter(apiKey: "gemini-test", transport: transport)
            _ = try await adapter.complete(
                request: Request(
                    model: "gemini-3-flash-preview",
                    messages: [Message(role: .user, content: [.image(ImageData(url: urlImage, mediaType: "image/png"))])]
                )
            )

            let sentOpt = await transport.lastSendRequest
            let sent = try XCTUnwrap(sentOpt)
            let body = try JSONValue.parse(bodyBytes(sent))
            let contents = body["contents"]?.arrayValue ?? []
            let parts = contents.first?["parts"]?.arrayValue ?? []
            let file = parts.first(where: { $0["fileData"] != nil })?["fileData"]
            XCTAssertEqual(file?["mimeType"]?.stringValue, "image/png")
            XCTAssertEqual(file?["fileUri"]?.stringValue, urlImage)
        }

        // Gemini: local file path -> inlineData.
        do {
            let responseJSON: JSONValue = .object([
                "candidates": .array([
                    .object([
                        "finishReason": .string("STOP"),
                        "content": .object(["parts": .array([.object(["text": .string("ok")])])]),
                    ]),
                ]),
                "usageMetadata": .object(["promptTokenCount": .number(1), "candidatesTokenCount": .number(1)]),
            ])

            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })

            let adapter = GeminiAdapter(apiKey: "gemini-test", transport: transport)
            _ = try await adapter.complete(
                request: Request(
                    model: "gemini-3-flash-preview",
                    messages: [Message(role: .user, content: [.image(ImageData(url: localPath, mediaType: "image/png"))])]
                )
            )

            let sentOpt = await transport.lastSendRequest
            let sent = try XCTUnwrap(sentOpt)
            let body = try JSONValue.parse(bodyBytes(sent))
            let contents = body["contents"]?.arrayValue ?? []
            let parts = contents.first?["parts"]?.arrayValue ?? []
            let inline = parts.first(where: { $0["inlineData"] != nil })?["inlineData"]
            XCTAssertEqual(inline?["mimeType"]?.stringValue, "image/png")
            XCTAssertEqual(inline?["data"]?.stringValue, expectedB64)
        }
    }

    func testOpenAIAdapterMapsRetryAfterOn429() async throws {
        let errJSON: JSONValue = .object(["error": .object(["message": .string("rate limited"), "type": .string("rate_limit")])])

        let headers: HTTPHeaders = {
            var h = HTTPHeaders()
            h.set(name: "retry-after", value: "2")
            return h
        }()

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 429, headers: headers, body: Array(try errJSON.data()))
        })

        let adapter = OpenAIAdapter(apiKey: "sk-test", transport: transport)

        do {
            _ = try await adapter.complete(request: Request(model: "gpt-5.2", messages: [.user("hi")]))
            XCTFail("Expected RateLimitError")
        } catch let e as RateLimitError {
            XCTAssertEqual(e.retryAfter, 2)
        }
    }

    func testAnthropicAdapterInjectsPromptCachingAndBetaHeaders() async throws {
        let responseJSON: JSONValue = .object([
            "id": .string("msg_1"),
            "model": .string("claude-opus-4-6"),
            "content": .array([.object(["type": .string("text"), "text": .string("Hello")])]),
            "stop_reason": .string("end_turn"),
            "usage": .object([
                "input_tokens": .number(5),
                "output_tokens": .number(7),
                "cache_read_input_tokens": .number(4),
                "cache_creation_input_tokens": .number(1),
            ]),
        ])

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        })

        let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)

        let schema: JSONValue = .object(["type": .string("object")])
        let tool = try Tool(name: "t", description: "tool", parameters: schema)

        let req = Request(
            model: "claude-opus-4-6",
            messages: [.system("sys"), .developer("dev"), .user("a"), .user("b")],
            tools: [tool],
            providerOptions: [
                "anthropic": .object([
                    "beta_headers": .array([.string("interleaved-thinking-2025-05-14")]),
                ]),
            ]
        )

        let resp = try await adapter.complete(request: req)
        XCTAssertEqual(resp.text, "Hello")
        XCTAssertEqual(resp.usage.cacheReadTokens, 4)
        XCTAssertEqual(resp.usage.cacheWriteTokens, 1)

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        XCTAssertTrue(sent.url.absoluteString.contains("/v1/messages"))
        XCTAssertEqual(sent.headers.firstValue(for: "x-api-key"), "anthropic-test")

        let beta = sent.headers.firstValue(for: "anthropic-beta") ?? ""
        XCTAssertTrue(beta.contains("interleaved-thinking-2025-05-14"))
        XCTAssertTrue(beta.contains("prompt-caching-2024-07-31"))

        let body = try JSONValue.parse(bodyBytes(sent))
        XCTAssertNotNil(body["system"])
        XCTAssertNotNil(body["tools"])

        // Strict alternation merge: two consecutive user messages should be merged into one.
        let messages = body["messages"]?.arrayValue ?? []
        XCTAssertEqual(messages.count, 1)
        let firstContent = messages.first?["content"]?.arrayValue ?? []
        XCTAssertEqual(firstContent.count, 2)

        // Conversation prefix cache_control injected on first user block.
        XCTAssertNotNil(firstContent.first?["cache_control"])
    }

    func testAnthropicAutoCacheCanBeDisabledViaProviderOptions() async throws {
        let responseJSON: JSONValue = .object([
            "id": .string("msg_1"),
            "model": .string("claude-opus-4-6"),
            "content": .array([.object(["type": .string("text"), "text": .string("Hello")])]),
            "stop_reason": .string("end_turn"),
            "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
        ])

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        })

        let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)

        let schema: JSONValue = .object(["type": .string("object")])
        let tool = try Tool(name: "t", description: "tool", parameters: schema)

        _ = try await adapter.complete(
            request: Request(
                model: "claude-opus-4-6",
                messages: [.system("sys"), .user("hi")],
                tools: [tool],
                providerOptions: ["anthropic": .object(["auto_cache": .bool(false)])]
            )
        )

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)

        // No prompt-caching beta header unless explicitly provided.
        XCTAssertFalse((sent.headers.firstValue(for: "anthropic-beta") ?? "").contains("prompt-caching-2024-07-31"))

        let body = try JSONValue.parse(bodyBytes(sent))
        let sys = body["system"]?.arrayValue?.first
        XCTAssertNil(sys?["cache_control"])

        let msgs = body["messages"]?.arrayValue ?? []
        let content0 = msgs.first?["content"]?.arrayValue?.first
        XCTAssertNil(content0?["cache_control"])

        let tools = body["tools"]?.arrayValue ?? []
        let t0 = tools.first
        XCTAssertNil(t0?["cache_control"])
    }

    func testAnthropicThinkingBlocksRoundTripWithSignature() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n: Int = 0
            func next() -> Int {
                lock.lock()
                defer { lock.unlock() }
                n += 1
                return n
            }
        }
        let counter = Counter()

        let firstResponse: JSONValue = .object([
            "id": .string("msg_1"),
            "model": .string("claude-opus-4-6"),
            "content": .array([
                .object(["type": .string("thinking"), "thinking": .string("thought"), "signature": .string("sig123")]),
                .object(["type": .string("redacted_thinking"), "data": .string("REDACTED")]),
                .object(["type": .string("text"), "text": .string("Hello")]),
            ]),
            "stop_reason": .string("end_turn"),
            "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
        ])

        let secondResponse: JSONValue = .object([
            "id": .string("msg_2"),
            "model": .string("claude-opus-4-6"),
            "content": .array([.object(["type": .string("text"), "text": .string("OK")])]),
            "stop_reason": .string("end_turn"),
            "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
        ])

        let transport = StubTransport(send: { _ in
            let idx = counter.next()
            let json = (idx == 1) ? firstResponse : secondResponse
            return HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try json.data()))
        })

        let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)

        let r1 = try await adapter.complete(request: Request(model: "claude-opus-4-6", messages: [.user("hi")]))
        XCTAssertNotNil(r1.reasoning)

        _ = try await adapter.complete(request: Request(model: "claude-opus-4-6", messages: [.user("hi"), r1.message]))

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        let body = try JSONValue.parse(bodyBytes(sent))
        let msgs = body["messages"]?.arrayValue ?? []

        let assistant = msgs.first(where: { $0["role"]?.stringValue == "assistant" })
        let content = assistant?["content"]?.arrayValue ?? []
        let thinking = content.first(where: { $0["type"]?.stringValue == "thinking" })
        XCTAssertEqual(thinking?["thinking"]?.stringValue, "thought")
        XCTAssertEqual(thinking?["signature"]?.stringValue, "sig123")

        let redacted = content.first(where: { $0["type"]?.stringValue == "redacted_thinking" })
        XCTAssertEqual(redacted?["data"]?.stringValue, "REDACTED")
    }

    func testAnthropicAdapterOmitToolsWhenToolChoiceNone() async throws {
        let responseJSON: JSONValue = .object([
            "id": .string("msg_1"),
            "model": .string("claude-opus-4-6"),
            "content": .array([.object(["type": .string("text"), "text": .string("Hello")])]),
            "stop_reason": .string("end_turn"),
            "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
        ])

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        })

        let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)

        let schema: JSONValue = .object(["type": .string("object")])
        let tool = try Tool(name: "t", description: "tool", parameters: schema)

        _ = try await adapter.complete(
            request: Request(
                model: "claude-opus-4-6",
                messages: [.user("hi")],
                tools: [tool],
                toolChoice: ToolChoice(mode: .none)
            )
        )

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        let body = try JSONValue.parse(bodyBytes(sent))
        XCTAssertNil(body["tools"])
    }

    func testGeminiAdapterBuildsGenerateContentRequest() async throws {
        let responseJSON: JSONValue = .object([
            "candidates": .array([
                .object([
                    "finishReason": .string("STOP"),
                    "content": .object(["parts": .array([.object(["text": .string("Hello")])])]),
                ]),
            ]),
            "usageMetadata": .object([
                "promptTokenCount": .number(5),
                "candidatesTokenCount": .number(7),
                "cachedContentTokenCount": .number(2),
                "thoughtsTokenCount": .number(1),
            ]),
        ])

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        })

        let adapter = GeminiAdapter(apiKey: "gemini-test", baseURL: "https://generativelanguage.googleapis.com", transport: transport)

        let schema: JSONValue = .object(["type": .string("object")])
        let tool = try Tool(name: "t", description: "tool", parameters: schema)

        let req = Request(
            model: "gemini-3-flash-preview",
            messages: [.system("sys"), .developer("dev"), .user("hi")],
            tools: [tool],
            toolChoice: ToolChoice(mode: .named, toolName: "t"),
            providerOptions: ["gemini": .object(["safetySettings": .array([])])]
        )

        let resp = try await adapter.complete(request: req)
        XCTAssertEqual(resp.text, "Hello")
        XCTAssertEqual(resp.usage.cacheReadTokens, 2)
        XCTAssertEqual(resp.usage.reasoningTokens, 1)

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        XCTAssertTrue(sent.url.absoluteString.contains(":generateContent"))
        XCTAssertTrue(sent.url.absoluteString.contains("key=gemini-test"))

        let body = try JSONValue.parse(bodyBytes(sent))
        XCTAssertNotNil(body["systemInstruction"])
        XCTAssertNotNil(body["tools"])
        XCTAssertNotNil(body["toolConfig"])
        XCTAssertNotNil(body["safetySettings"])
    }

    func testOpenAIAdapterStreamingMapsTextEvents() async throws {
        let completedJSON: JSONValue = .object([
            "type": .string("response.completed"),
            "id": .string("resp_1"),
            "model": .string("gpt-5.2"),
            "output": .array([
                .object([
                    "type": .string("message"),
                    "content": .array([.object(["type": .string("output_text"), "text": .string("hello")])]),
                ]),
            ]),
            "finish_reason": .string("stop"),
            "usage": .object(["prompt_tokens": .number(1), "completion_tokens": .number(1)]),
        ])

        let sse = """
        event: response.output_text.delta
        data: {\"type\":\"response.output_text.delta\",\"delta\":\"he\"}

        event: response.output_text.delta
        data: {\"type\":\"response.output_text.delta\",\"delta\":\"llo\"}

        event: response.output_text.done
        data: {\"type\":\"response.output_text.done\"}

        event: response.completed
        data: \(String(data: try completedJSON.data(), encoding: .utf8)!)

        """

        let transport = StubTransport(stream: { _ in
            HTTPStreamResponse(statusCode: 200, headers: HTTPHeaders(), body: streamFromSSE(sse))
        })

        let adapter = OpenAIAdapter(apiKey: "sk-test", transport: transport)
        let stream = try await adapter.stream(request: Request(model: "gpt-5.2", messages: [.user("hi")]))

        var chunks: [String] = []
        var finish: Response?
        for try await ev in stream {
            if ev.type.rawValue == StreamEventType.textDelta.rawValue {
                chunks.append(ev.delta ?? "")
            }
            if ev.type.rawValue == StreamEventType.finish.rawValue {
                finish = ev.response
            }
        }

        XCTAssertEqual(chunks.joined(), "hello")
        XCTAssertEqual(finish?.text, "hello")
    }

    func testAnthropicAdapterStreamingMapsTextEvents() async throws {
        let sse = """
        event: message_start
        data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"model\":\"claude-opus-4-6\",\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}

        event: content_block_start
        data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\"}}

        event: content_block_delta
        data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"he\"}}

        event: content_block_delta
        data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"llo\"}}

        event: content_block_stop
        data: {\"type\":\"content_block_stop\",\"index\":0}

        event: message_delta
        data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"input_tokens\":5,\"output_tokens\":7}}

        event: message_stop
        data: {\"type\":\"message_stop\"}

        """

        let transport = StubTransport(stream: { _ in
            HTTPStreamResponse(statusCode: 200, headers: HTTPHeaders(), body: streamFromSSE(sse))
        })

        let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)
        let stream = try await adapter.stream(request: Request(model: "claude-opus-4-6", messages: [.user("hi")]))

        var chunks: [String] = []
        var finish: Response?
        for try await ev in stream {
            if ev.type.rawValue == StreamEventType.textDelta.rawValue {
                chunks.append(ev.delta ?? "")
            }
            if ev.type.rawValue == StreamEventType.finish.rawValue {
                finish = ev.response
            }
        }

        XCTAssertEqual(chunks.joined(), "hello")
        XCTAssertEqual(finish?.text, "hello")
        XCTAssertEqual(finish?.finishReason.reason, "stop")
    }

    func testGeminiAdapterStreamingMapsTextEvents() async throws {
        let sse = """
        data: {\"candidates\":[{\"finishReason\":\"STOP\",\"content\":{\"parts\":[{\"text\":\"he\"}]}}],\"usageMetadata\":{\"promptTokenCount\":5,\"candidatesTokenCount\":7}}

        data: {\"candidates\":[{\"finishReason\":\"STOP\",\"content\":{\"parts\":[{\"text\":\"llo\"}]}}],\"usageMetadata\":{\"promptTokenCount\":5,\"candidatesTokenCount\":7}}

        """

        let transport = StubTransport(stream: { _ in
            HTTPStreamResponse(statusCode: 200, headers: HTTPHeaders(), body: streamFromSSE(sse))
        })

        let adapter = GeminiAdapter(apiKey: "gemini-test", transport: transport)
        let stream = try await adapter.stream(request: Request(model: "gemini-3-flash-preview", messages: [.user("hi")]))

        var chunks: [String] = []
        var finish: Response?
        for try await ev in stream {
            if ev.type.rawValue == StreamEventType.textDelta.rawValue {
                chunks.append(ev.delta ?? "")
            }
            if ev.type.rawValue == StreamEventType.finish.rawValue {
                finish = ev.response
            }
        }

        XCTAssertEqual(chunks.joined(), "hello")
        XCTAssertEqual(finish?.text, "hello")
    }

    func testOpenAIAdapterTranslatesAllRolesAndToolRoundTrip() async throws {
        let responseJSON: JSONValue = .object([
            "id": .string("resp_1"),
            "model": .string("gpt-5.2"),
            "output": .array([.object(["type": .string("message"), "content": .array([.object(["type": .string("output_text"), "text": .string("ok")])])])]),
            "finish_reason": .string("stop"),
            "usage": .object(["prompt_tokens": .number(1), "completion_tokens": .number(1)]),
        ])

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        })

        let adapter = OpenAIAdapter(apiKey: "sk-test", transport: transport)

        let call = ToolCall(id: "call_1", name: "add", arguments: ["a": .number(1), "b": .number(2)], rawArguments: nil)
        let toolResultMsg = Message.toolResult(toolCallId: call.id, toolName: call.name, content: .string("4"), isError: false)

        _ = try await adapter.complete(
            request: Request(
                model: "gpt-5.2",
                messages: [
                    .system("sys"),
                    .developer("dev"),
                    Message(role: .user, content: [.text("u")]),
                    Message(role: .assistant, content: [.text("a"), .toolCall(call)]),
                    toolResultMsg,
                ]
            )
        )

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        let body = try JSONValue.parse(bodyBytes(sent))

        XCTAssertTrue(body["instructions"]?.stringValue?.contains("sys") ?? false)
        XCTAssertTrue(body["instructions"]?.stringValue?.contains("dev") ?? false)

        let input = body["input"]?.arrayValue ?? []
        let userMsg = input.first(where: { $0["type"]?.stringValue == "message" && $0["role"]?.stringValue == "user" })
        XCTAssertNotNil(userMsg)

        let assistantMsg = input.first(where: { $0["type"]?.stringValue == "message" && $0["role"]?.stringValue == "assistant" })
        let assistantParts = assistantMsg?["content"]?.arrayValue ?? []
        XCTAssertNotNil(assistantParts.first(where: { $0["type"]?.stringValue == "output_text" && $0["text"]?.stringValue == "a" }))

        let fnCall = input.first(where: { $0["type"]?.stringValue == "function_call" })
        XCTAssertEqual(fnCall?["call_id"]?.stringValue, "call_1")
        XCTAssertEqual(fnCall?["name"]?.stringValue, "add")
        XCTAssertTrue((fnCall?["arguments"]?.stringValue ?? "").contains("\"a\""))

        let fnOut = input.first(where: { $0["type"]?.stringValue == "function_call_output" })
        XCTAssertEqual(fnOut?["call_id"]?.stringValue, "call_1")
        XCTAssertEqual(fnOut?["output"]?.stringValue, "4")
    }

    func testAnthropicAdapterTranslatesAllRolesAndToolRoundTrip() async throws {
        let responseJSON: JSONValue = .object([
            "id": .string("msg_1"),
            "model": .string("claude-opus-4-6"),
            "content": .array([.object(["type": .string("text"), "text": .string("ok")])]),
            "stop_reason": .string("end_turn"),
            "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
        ])

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        })

        let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)

        let call = ToolCall(id: "tool_1", name: "add", arguments: ["a": .number(1), "b": .number(2)], rawArguments: nil)
        let toolResultMsg = Message.toolResult(toolCallId: call.id, toolName: call.name, content: .string("4"), isError: false)

        _ = try await adapter.complete(
            request: Request(
                model: "claude-opus-4-6",
                messages: [
                    .system("sys"),
                    .developer("dev"),
                    Message(role: .user, content: [.text("u")]),
                    Message(role: .assistant, content: [.text("a"), .toolCall(call)]),
                    toolResultMsg,
                ]
            )
        )

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        let body = try JSONValue.parse(bodyBytes(sent))

        let systemBlocks = body["system"]?.arrayValue ?? []
        let sysText = systemBlocks.first?["text"]?.stringValue ?? ""
        XCTAssertTrue(sysText.contains("sys"))
        XCTAssertTrue(sysText.contains("dev"))

        let messages = body["messages"]?.arrayValue ?? []
        XCTAssertEqual(messages.count, 3)

        XCTAssertEqual(messages[0]["role"]?.stringValue, "user")
        XCTAssertEqual(messages[0]["content"]?.arrayValue?.first?["type"]?.stringValue, "text")

        XCTAssertEqual(messages[1]["role"]?.stringValue, "assistant")
        let aContent = messages[1]["content"]?.arrayValue ?? []
        XCTAssertNotNil(aContent.first(where: { $0["type"]?.stringValue == "tool_use" && $0["id"]?.stringValue == "tool_1" && $0["name"]?.stringValue == "add" }))

        XCTAssertEqual(messages[2]["role"]?.stringValue, "user")
        let u2Content = messages[2]["content"]?.arrayValue ?? []
        let tr = u2Content.first(where: { $0["type"]?.stringValue == "tool_result" })
        XCTAssertEqual(tr?["tool_use_id"]?.stringValue, "tool_1")
        XCTAssertEqual(tr?["is_error"]?.boolValue, false)
    }

    func testGeminiAdapterTranslatesAllRolesAndToolRoundTrip() async throws {
        let responseJSON: JSONValue = .object([
            "candidates": .array([
                .object([
                    "finishReason": .string("STOP"),
                    "content": .object(["parts": .array([.object(["text": .string("ok")])])]),
                ]),
            ]),
            "usageMetadata": .object(["promptTokenCount": .number(1), "candidatesTokenCount": .number(1)]),
        ])

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        })

        let adapter = GeminiAdapter(apiKey: "gemini-test", transport: transport)

        let call = ToolCall(id: "tool_1", name: "add", arguments: ["a": .number(1), "b": .number(2)], rawArguments: nil)
        let toolResultMsg = Message.toolResult(toolCallId: call.id, toolName: call.name, content: .object(["sum": .number(4)]), isError: false)

        _ = try await adapter.complete(
            request: Request(
                model: "gemini-3-flash-preview",
                messages: [
                    .system("sys"),
                    .developer("dev"),
                    Message(role: .user, content: [.text("u")]),
                    Message(role: .assistant, content: [.text("a"), .toolCall(call)]),
                    toolResultMsg,
                ]
            )
        )

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        let body = try JSONValue.parse(bodyBytes(sent))

        let sysParts = body["systemInstruction"]?["parts"]?.arrayValue ?? []
        XCTAssertEqual(sysParts.count, 2)

        let contents = body["contents"]?.arrayValue ?? []
        XCTAssertEqual(contents.count, 3)

        XCTAssertEqual(contents[0]["role"]?.stringValue, "user")
        XCTAssertEqual(contents[1]["role"]?.stringValue, "model")
        XCTAssertEqual(contents[2]["role"]?.stringValue, "user")

        let modelParts = contents[1]["parts"]?.arrayValue ?? []
        let fc = modelParts.first(where: { $0["functionCall"] != nil })?["functionCall"]
        XCTAssertEqual(fc?["name"]?.stringValue, "add")
        XCTAssertEqual(fc?["args"]?["a"]?.doubleValue, 1)

        let user2Parts = contents[2]["parts"]?.arrayValue ?? []
        let fr = user2Parts.first(where: { $0["functionResponse"] != nil })?["functionResponse"]
        XCTAssertEqual(fr?["name"]?.stringValue, "add")
        XCTAssertEqual(fr?["response"]?["sum"]?.doubleValue, 4)
    }

    func testAnthropicProviderOptionsPassThrough() async throws {
        let responseJSON: JSONValue = .object([
            "id": .string("msg_1"),
            "model": .string("claude-opus-4-6"),
            "content": .array([.object(["type": .string("text"), "text": .string("ok")])]),
            "stop_reason": .string("end_turn"),
            "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
        ])

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        })

        let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)

        _ = try await adapter.complete(
            request: Request(
                model: "claude-opus-4-6",
                messages: [.user("hi")],
                providerOptions: ["anthropic": .object(["foo": .string("bar")])]
            )
        )

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        let body = try JSONValue.parse(bodyBytes(sent))
        XCTAssertEqual(body["foo"]?.stringValue, "bar")
    }

    func testToolChoiceTranslationAcrossProviders() async throws {
        let schema: JSONValue = .object(["type": .string("object")])
        let tool = try Tool(name: "t", description: "tool", parameters: schema)

        // OpenAI
        do {
            let responseJSON: JSONValue = .object([
                "id": .string("resp_1"),
                "model": .string("gpt-5.2"),
                "output": .array([.object(["type": .string("message"), "content": .array([.object(["type": .string("output_text"), "text": .string("ok")])])])]),
                "finish_reason": .string("stop"),
                "usage": .object(["prompt_tokens": .number(1), "completion_tokens": .number(1)]),
            ])
            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })
            let adapter = OpenAIAdapter(apiKey: "sk-test", transport: transport)

            func lastBody() async throws -> JSONValue {
                let sentOpt = await transport.lastSendRequest
                let sent = try XCTUnwrap(sentOpt)
                return try JSONValue.parse(bodyBytes(sent))
            }

            _ = try await adapter.complete(request: Request(model: "gpt-5.2", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .auto)))
            var body = try await lastBody()
            XCTAssertEqual(body["tool_choice"]?.stringValue, "auto")

            _ = try await adapter.complete(request: Request(model: "gpt-5.2", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .none)))
            body = try await lastBody()
            XCTAssertEqual(body["tool_choice"]?.stringValue, "none")

            _ = try await adapter.complete(request: Request(model: "gpt-5.2", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .required)))
            body = try await lastBody()
            XCTAssertEqual(body["tool_choice"]?.stringValue, "required")

            _ = try await adapter.complete(request: Request(model: "gpt-5.2", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .named, toolName: "t")))
            body = try await lastBody()
            XCTAssertEqual(body["tool_choice"]?["type"]?.stringValue, "function")
            XCTAssertEqual(body["tool_choice"]?["name"]?.stringValue, "t")
        }

        // Anthropic
        do {
            let responseJSON: JSONValue = .object([
                "id": .string("msg_1"),
                "model": .string("claude-opus-4-6"),
                "content": .array([.object(["type": .string("text"), "text": .string("ok")])]),
                "stop_reason": .string("end_turn"),
                "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
            ])
            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })
            let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)

            func lastBody() async throws -> JSONValue {
                let sentOpt = await transport.lastSendRequest
                let sent = try XCTUnwrap(sentOpt)
                return try JSONValue.parse(bodyBytes(sent))
            }

            _ = try await adapter.complete(request: Request(model: "claude-opus-4-6", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .auto)))
            var body = try await lastBody()
            XCTAssertEqual(body["tool_choice"]?["type"]?.stringValue, "auto")

            _ = try await adapter.complete(request: Request(model: "claude-opus-4-6", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .required)))
            body = try await lastBody()
            XCTAssertEqual(body["tool_choice"]?["type"]?.stringValue, "any")

            _ = try await adapter.complete(request: Request(model: "claude-opus-4-6", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .named, toolName: "t")))
            body = try await lastBody()
            XCTAssertEqual(body["tool_choice"]?["type"]?.stringValue, "tool")
            XCTAssertEqual(body["tool_choice"]?["name"]?.stringValue, "t")

            _ = try await adapter.complete(request: Request(model: "claude-opus-4-6", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .none)))
            body = try await lastBody()
            XCTAssertNil(body["tools"])
        }

        // Gemini
        do {
            let responseJSON: JSONValue = .object([
                "candidates": .array([
                    .object([
                        "finishReason": .string("STOP"),
                        "content": .object(["parts": .array([.object(["text": .string("ok")])])]),
                    ]),
                ]),
                "usageMetadata": .object(["promptTokenCount": .number(1), "candidatesTokenCount": .number(1)]),
            ])
            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
            })
            let adapter = GeminiAdapter(apiKey: "gemini-test", transport: transport)

            func lastBody() async throws -> JSONValue {
                let sentOpt = await transport.lastSendRequest
                let sent = try XCTUnwrap(sentOpt)
                return try JSONValue.parse(bodyBytes(sent))
            }

            _ = try await adapter.complete(request: Request(model: "gemini-3-flash-preview", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .auto)))
            var body = try await lastBody()
            XCTAssertEqual(body["toolConfig"]?["functionCallingConfig"]?["mode"]?.stringValue, "AUTO")

            _ = try await adapter.complete(request: Request(model: "gemini-3-flash-preview", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .none)))
            body = try await lastBody()
            XCTAssertEqual(body["toolConfig"]?["functionCallingConfig"]?["mode"]?.stringValue, "NONE")

            _ = try await adapter.complete(request: Request(model: "gemini-3-flash-preview", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .required)))
            body = try await lastBody()
            XCTAssertEqual(body["toolConfig"]?["functionCallingConfig"]?["mode"]?.stringValue, "ANY")

            _ = try await adapter.complete(request: Request(model: "gemini-3-flash-preview", messages: [.user("hi")], tools: [tool], toolChoice: ToolChoice(mode: .named, toolName: "t")))
            body = try await lastBody()
            XCTAssertEqual(body["toolConfig"]?["functionCallingConfig"]?["mode"]?.stringValue, "ANY")
            let allowed = body["toolConfig"]?["functionCallingConfig"]?["allowedFunctionNames"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            XCTAssertEqual(allowed, ["t"])
        }
    }

    func testAdaptersGracefullyRejectAudioAndDocuments() async throws {
        let transport = StubTransport(send: { _ in
            XCTFail("Transport should not be used for unsupported content kinds")
            return HTTPResponse(statusCode: 500, headers: HTTPHeaders(), body: [])
        })

        let audioPart = ContentPart(kind: .standard(.audio), audio: AudioData(data: [0x00], mediaType: "audio/wav"))
        let docPart = ContentPart(kind: .standard(.document), document: DocumentData(data: [0x00], mediaType: "application/pdf", fileName: "x.pdf"))

        let adapters: [(String, (Request) async throws -> Response)] = [
            ("openai", { req in try await OpenAIAdapter(apiKey: "sk", transport: transport).complete(request: req) }),
            ("anthropic", { req in try await AnthropicAdapter(apiKey: "ak", transport: transport).complete(request: req) }),
            ("gemini", { req in try await GeminiAdapter(apiKey: "gk", transport: transport).complete(request: req) }),
        ]

        for (name, complete) in adapters {
            do {
                _ = try await complete(Request(model: "m", messages: [Message(role: .user, content: [audioPart])]))
                XCTFail("Expected InvalidRequestError for audio (\(name))")
            } catch is InvalidRequestError {
                // ok
            }

            do {
                _ = try await complete(Request(model: "m", messages: [Message(role: .user, content: [docPart])]))
                XCTFail("Expected InvalidRequestError for document (\(name))")
            } catch is InvalidRequestError {
                // ok
            }
        }
    }

    func testRetryAfterIsParsedForAnthropicAndGeminiErrors() async throws {
        let headers: HTTPHeaders = {
            var h = HTTPHeaders()
            h.set(name: "retry-after", value: "3")
            return h
        }()

        // Anthropic 429
        do {
            let errJSON: JSONValue = .object(["error": .object(["type": .string("rate_limit_error"), "message": .string("rate limited")])])
            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 429, headers: headers, body: Array(try errJSON.data()))
            })
            let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)
            do {
                _ = try await adapter.complete(request: Request(model: "claude-opus-4-6", messages: [.user("hi")]))
                XCTFail("Expected RateLimitError")
            } catch let e as RateLimitError {
                XCTAssertEqual(e.retryAfter, 3)
            }
        }

        // Gemini 429
        do {
            let errJSON: JSONValue = .object(["error": .object(["message": .string("rate limited"), "status": .string("RESOURCE_EXHAUSTED")])])
            let transport = StubTransport(send: { _ in
                HTTPResponse(statusCode: 429, headers: headers, body: Array(try errJSON.data()))
            })
            let adapter = GeminiAdapter(apiKey: "gemini-test", transport: transport)
            do {
                _ = try await adapter.complete(request: Request(model: "gemini-3-flash-preview", messages: [.user("hi")]))
                XCTFail("Expected RateLimitError")
            } catch let e as RateLimitError {
                XCTAssertEqual(e.retryAfter, 3)
            }
        }
    }

    func testOpenAIReasoningEffortIsPassedThrough() async throws {
        let responseJSON: JSONValue = .object([
            "id": .string("resp_1"),
            "model": .string("gpt-5.2"),
            "output": .array([.object(["type": .string("message"), "content": .array([.object(["type": .string("output_text"), "text": .string("ok")])])])]),
            "finish_reason": .string("stop"),
            "usage": .object(["prompt_tokens": .number(1), "completion_tokens": .number(1)]),
        ])

        let transport = StubTransport(send: { _ in
            HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        })
        let adapter = OpenAIAdapter(apiKey: "sk-test", transport: transport)

        _ = try await adapter.complete(
            request: Request(
                model: "gpt-5.2",
                messages: [.user("hi")],
                reasoningEffort: "high"
            )
        )

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        let body = try JSONValue.parse(bodyBytes(sent))
        XCTAssertEqual(body["reasoning"]?["effort"]?.stringValue, "high")
    }

    func testOpenAIAdapterStreamingMapsToolCallEvents() async throws {
        let completedJSON: JSONValue = .object([
            "type": .string("response.completed"),
            "id": .string("resp_1"),
            "model": .string("gpt-5.2"),
            "output": .array([
                .object([
                    "type": .string("function_call"),
                    "call_id": .string("c1"),
                    "name": .string("add"),
                    "arguments": .string("{\"a\":1,\"b\":2}"),
                ]),
            ]),
            "finish_reason": .string("tool_calls"),
            "usage": .object(["prompt_tokens": .number(1), "completion_tokens": .number(1)]),
        ])

        let sse = """
        event: response.function_call_arguments.delta
        data: {\"type\":\"response.function_call_arguments.delta\",\"call_id\":\"c1\",\"name\":\"add\",\"delta\":\"{\\\"a\\\":1\"}

        event: response.function_call_arguments.delta
        data: {\"type\":\"response.function_call_arguments.delta\",\"call_id\":\"c1\",\"delta\":\",\\\"b\\\":2}\"}

        event: response.function_call_arguments.done
        data: {\"type\":\"response.function_call_arguments.done\",\"call_id\":\"c1\"}

        event: response.completed
        data: \(String(data: try completedJSON.data(), encoding: .utf8)!)

        """

        let transport = StubTransport(stream: { _ in
            HTTPStreamResponse(statusCode: 200, headers: HTTPHeaders(), body: streamFromSSE(sse))
        })

        let adapter = OpenAIAdapter(apiKey: "sk-test", transport: transport)
        let stream = try await adapter.stream(request: Request(model: "gpt-5.2", messages: [.user("hi")]))

        var seenStart = false
        var seenDelta = false
        var seenEnd = false
        var finish: Response?

        for try await ev in stream {
            if ev.type.rawValue == StreamEventType.toolCallStart.rawValue {
                seenStart = true
                XCTAssertEqual(ev.toolCall?.id, "c1")
                XCTAssertEqual(ev.toolCall?.name, "add")
            }
            if ev.type.rawValue == StreamEventType.toolCallDelta.rawValue {
                seenDelta = true
                XCTAssertEqual(ev.toolCall?.id, "c1")
                XCTAssertTrue((ev.toolCall?.rawArguments ?? "").contains("\"a\""))
            }
            if ev.type.rawValue == StreamEventType.toolCallEnd.rawValue {
                seenEnd = true
                XCTAssertEqual(ev.toolCall?.id, "c1")
                XCTAssertEqual(ev.toolCall?.arguments["a"]?.doubleValue, 1)
                XCTAssertEqual(ev.toolCall?.arguments["b"]?.doubleValue, 2)
            }
            if ev.type.rawValue == StreamEventType.finish.rawValue {
                finish = ev.response
            }
        }

        XCTAssertTrue(seenStart)
        XCTAssertTrue(seenDelta)
        XCTAssertTrue(seenEnd)
        XCTAssertEqual(finish?.finishReason.reason, "tool_calls")
        XCTAssertEqual(finish?.toolCalls.first?.name, "add")
    }

    func testAnthropicAdapterStreamingMapsToolCallEvents() async throws {
        let sse = """
        event: message_start
        data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"model\":\"claude-opus-4-6\",\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}

        event: content_block_start
        data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tool_1\",\"name\":\"add\"}}

        event: content_block_delta
        data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"a\\\":1,\\\"b\\\":2}\"}}

        event: content_block_stop
        data: {\"type\":\"content_block_stop\",\"index\":0}

        event: message_delta
        data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"input_tokens\":5,\"output_tokens\":7}}

        event: message_stop
        data: {\"type\":\"message_stop\"}

        """

        let transport = StubTransport(stream: { _ in
            HTTPStreamResponse(statusCode: 200, headers: HTTPHeaders(), body: streamFromSSE(sse))
        })

        let adapter = AnthropicAdapter(apiKey: "anthropic-test", transport: transport)
        let stream = try await adapter.stream(request: Request(model: "claude-opus-4-6", messages: [.user("hi")]))

        var seenStart = false
        var seenDelta = false
        var seenEnd = false
        var finish: Response?

        for try await ev in stream {
            if ev.type.rawValue == StreamEventType.toolCallStart.rawValue {
                seenStart = true
                XCTAssertEqual(ev.toolCall?.id, "tool_1")
                XCTAssertEqual(ev.toolCall?.name, "add")
            }
            if ev.type.rawValue == StreamEventType.toolCallDelta.rawValue {
                seenDelta = true
                XCTAssertTrue((ev.toolCall?.rawArguments ?? "").contains("\"a\""))
            }
            if ev.type.rawValue == StreamEventType.toolCallEnd.rawValue {
                seenEnd = true
                XCTAssertEqual(ev.toolCall?.arguments["a"]?.doubleValue, 1)
                XCTAssertEqual(ev.toolCall?.arguments["b"]?.doubleValue, 2)
            }
            if ev.type.rawValue == StreamEventType.finish.rawValue {
                finish = ev.response
            }
        }

        XCTAssertTrue(seenStart)
        XCTAssertTrue(seenDelta)
        XCTAssertTrue(seenEnd)
        XCTAssertEqual(finish?.finishReason.reason, "tool_calls")
        XCTAssertEqual(finish?.toolCalls.first?.name, "add")
    }
}
