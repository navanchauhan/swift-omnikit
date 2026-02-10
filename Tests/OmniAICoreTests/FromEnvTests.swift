import XCTest

import OmniHTTP
@testable import OmniAICore

private actor CapturingTransport: HTTPTransport {
    private(set) var lastSendRequest: HTTPRequest?

    private let response: HTTPResponse

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(_ request: HTTPRequest, timeout: Duration?) async throws -> HTTPResponse {
        lastSendRequest = request
        return response
    }

    func openStream(_ request: HTTPRequest, timeout: Duration?) async throws -> HTTPStreamResponse {
        throw OmniHTTPError.streamingNotSupported
    }

    func shutdown() async throws {}
}

final class FromEnvTests: XCTestCase {
    func testFromEnvThrowsConfigurationErrorWhenNoProvidersConfigured() {
        XCTAssertThrowsError(
            try Client.fromEnv(environment: [:], transport: URLSessionHTTPTransport())
        ) { err in
            XCTAssertTrue(err is ConfigurationError)
        }
    }

    func testFromEnvRegistersOpenAIAndPassesOrgAndProjectHeaders() async throws {
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

        let transport = CapturingTransport(
            response: HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        )

        let client = try Client.fromEnv(
            environment: [
                "OPENAI_API_KEY": "sk-test",
                "OPENAI_ORG_ID": "org_1",
                "OPENAI_PROJECT_ID": "proj_1",
            ],
            transport: transport
        )

        let resp = try await client.complete(Request(model: "gpt-5.2", messages: [.user("hi")]))
        XCTAssertEqual(resp.provider, "openai")

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        XCTAssertEqual(sent.headers.firstValue(for: "openai-organization"), "org_1")
        XCTAssertEqual(sent.headers.firstValue(for: "openai-project"), "proj_1")
    }

    func testFromEnvRegistersAnthropic() async throws {
        let responseJSON: JSONValue = .object([
            "id": .string("msg_1"),
            "model": .string("claude-opus-4-6"),
            "content": .array([.object(["type": .string("text"), "text": .string("ok")])]),
            "stop_reason": .string("end_turn"),
            "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
        ])

        let transport = CapturingTransport(
            response: HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        )

        let client = try Client.fromEnv(
            environment: ["ANTHROPIC_API_KEY": "anthropic-test"],
            transport: transport
        )

        let resp = try await client.complete(Request(model: "claude-opus-4-6", messages: [.user("hi")]))
        XCTAssertEqual(resp.provider, "anthropic")

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        XCTAssertEqual(sent.headers.firstValue(for: "x-api-key"), "anthropic-test")
    }

    func testFromEnvRegistersGeminiUsingGeminiAPIKey() async throws {
        let responseJSON: JSONValue = .object([
            "candidates": .array([
                .object([
                    "finishReason": .string("STOP"),
                    "content": .object(["parts": .array([.object(["text": .string("ok")])])]),
                ]),
            ]),
            "usageMetadata": .object(["promptTokenCount": .number(1), "candidatesTokenCount": .number(1)]),
        ])

        let transport = CapturingTransport(
            response: HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        )

        let client = try Client.fromEnv(
            environment: ["GEMINI_API_KEY": "gemini-test"],
            transport: transport
        )

        let resp = try await client.complete(Request(model: "gemini-3-flash-preview", messages: [.user("hi")]))
        XCTAssertEqual(resp.provider, "gemini")

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        XCTAssertTrue(sent.url.absoluteString.contains("key=gemini-test"))
    }

    func testFromEnvRegistersGeminiUsingGoogleAPIKeyFallback() async throws {
        let responseJSON: JSONValue = .object([
            "candidates": .array([
                .object([
                    "finishReason": .string("STOP"),
                    "content": .object(["parts": .array([.object(["text": .string("ok")])])]),
                ]),
            ]),
            "usageMetadata": .object(["promptTokenCount": .number(1), "candidatesTokenCount": .number(1)]),
        ])

        let transport = CapturingTransport(
            response: HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: Array(try responseJSON.data()))
        )

        let client = try Client.fromEnv(
            environment: ["GOOGLE_API_KEY": "google-test"],
            transport: transport
        )

        let resp = try await client.complete(Request(model: "gemini-3-flash-preview", messages: [.user("hi")]))
        XCTAssertEqual(resp.provider, "gemini")

        let sentOpt = await transport.lastSendRequest
        let sent = try XCTUnwrap(sentOpt)
        XCTAssertTrue(sent.url.absoluteString.contains("key=google-test"))
    }
}

