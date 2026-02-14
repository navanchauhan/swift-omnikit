import XCTest
@testable import OmniAILLMClient

// MARK: - 8.2 Provider Adapter Tests + 8.9 Cross-Provider Parity

final class ProviderAdapterTests: XCTestCase {
    var client: LLMClient!

    override func setUp() {
        client = LLMClient.fromEnv()
    }

    private func skipUnlessAnthropic() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil,
            "ANTHROPIC_API_KEY not set"
        )
    }

    private func skipUnlessOpenAI() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil,
            "OPENAI_API_KEY not set"
        )
    }

    private func skipUnlessGemini() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil ||
            ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] != nil,
            "GEMINI_API_KEY not set"
        )
    }

    private func skipUnlessAnyProvider() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil ||
            ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil ||
            ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil ||
            ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] != nil,
            "No API keys available"
        )
    }

    // MARK: - Simple Text Generation (per provider)

    func testAnthropicSimpleGeneration() async throws {
        try skipUnlessAnthropic()
        let request = Request(
            model: "claude-haiku-4-5-20251001",
            messages: [.user("Say 'hello world' exactly.")],
            provider: "anthropic",
            maxTokens: 50
        )
        let response = try await client.complete(request: request)
        XCTAssertFalse(response.text.isEmpty)
        XCTAssertEqual(response.provider, "anthropic")
        XCTAssertEqual(response.finishReason.reason, "stop")
        XCTAssertGreaterThan(response.usage.inputTokens, 0)
        XCTAssertGreaterThan(response.usage.outputTokens, 0)
    }

    func testOpenAISimpleGeneration() async throws {
        try skipUnlessOpenAI()
        let request = Request(
            model: "gpt-5.2",
            messages: [.user("Say 'hello world' exactly.")],
            provider: "openai",
            maxTokens: 50
        )
        let response = try await client.complete(request: request)
        XCTAssertFalse(response.text.isEmpty)
        XCTAssertEqual(response.provider, "openai")
        XCTAssertGreaterThan(response.usage.inputTokens, 0)
        XCTAssertGreaterThan(response.usage.outputTokens, 0)
    }

    func testGeminiSimpleGeneration() async throws {
        try skipUnlessGemini()
        let request = Request(
            model: "gemini-3-flash-preview",
            messages: [.user("Say 'hello world' exactly.")],
            provider: "gemini",
            maxTokens: 200
        )
        let response = try await client.complete(request: request)
        XCTAssertFalse(response.text.isEmpty)
        XCTAssertEqual(response.provider, "gemini")
        XCTAssertGreaterThan(response.usage.inputTokens, 0)
        // For reasoning models, output may include thinking tokens
        let totalOutput = response.usage.outputTokens + (response.usage.reasoningTokens ?? 0)
        XCTAssertGreaterThan(totalOutput, 0)
    }

    // MARK: - Streaming (per provider)

    func testAnthropicStreaming() async throws {
        try skipUnlessAnthropic()
        let request = Request(
            model: "claude-haiku-4-5-20251001",
            messages: [.user("Count from 1 to 3.")],
            provider: "anthropic",
            maxTokens: 500
        )
        let stream = try await client.stream(request: request)
        var textChunks: [String] = []
        var gotStart = false
        var gotFinish = false

        for try await event in stream {
            if event.eventType == StreamEventType.streamStart || event.eventType == StreamEventType.textStart {
                gotStart = true
            }
            if event.eventType == StreamEventType.textDelta, let delta = event.delta {
                textChunks.append(delta)
            }
            if event.eventType == StreamEventType.finish {
                gotFinish = true
                XCTAssertNotNil(event.usage)
            }
        }
        XCTAssertTrue(gotStart)
        XCTAssertTrue(gotFinish)
        XCTAssertFalse(textChunks.isEmpty)
    }

    func testOpenAIStreaming() async throws {
        try skipUnlessOpenAI()
        let request = Request(
            model: "gpt-5.2",
            messages: [.user("Count from 1 to 3.")],
            provider: "openai",
            maxTokens: 500
        )
        let stream = try await client.stream(request: request)
        var textChunks: [String] = []
        var gotFinish = false

        for try await event in stream {
            if event.eventType == StreamEventType.textDelta, let delta = event.delta {
                textChunks.append(delta)
            }
            if event.eventType == StreamEventType.finish {
                gotFinish = true
            }
        }
        XCTAssertTrue(gotFinish)
        XCTAssertFalse(textChunks.isEmpty)
    }

    func testGeminiStreaming() async throws {
        try skipUnlessGemini()
        let request = Request(
            model: "gemini-3-flash-preview",
            messages: [.user("Count from 1 to 3.")],
            provider: "gemini",
            maxTokens: 500
        )
        let stream = try await client.stream(request: request)
        var textChunks: [String] = []
        var gotFinish = false

        for try await event in stream {
            if event.eventType == StreamEventType.textDelta, let delta = event.delta {
                textChunks.append(delta)
            }
            if event.eventType == StreamEventType.finish {
                gotFinish = true
            }
        }
        XCTAssertTrue(gotFinish)
        XCTAssertFalse(textChunks.isEmpty)
    }

    // MARK: - Roles (all 5)

    func testAllRolesAnthropic() async throws {
        try skipUnlessAnthropic()
        let request = Request(
            model: "claude-haiku-4-5-20251001",
            messages: [
                .system("You are a helpful assistant."),
                .developer("Always be concise."),
                .user("What is 2+2?"),
                .assistant("4"),
                .user("And 3+3?")
            ],
            provider: "anthropic",
            maxTokens: 50
        )
        let response = try await client.complete(request: request)
        XCTAssertFalse(response.text.isEmpty)
    }

    func testAllRolesOpenAI() async throws {
        try skipUnlessOpenAI()
        let request = Request(
            model: "gpt-5.2",
            messages: [
                .system("You are a helpful assistant."),
                .developer("Always be concise."),
                .user("What is 2+2?"),
                .assistant("4"),
                .user("And 3+3?")
            ],
            provider: "openai",
            maxTokens: 50
        )
        let response = try await client.complete(request: request)
        XCTAssertFalse(response.text.isEmpty)
    }

    func testAllRolesGemini() async throws {
        try skipUnlessGemini()
        let request = Request(
            model: "gemini-3-flash-preview",
            messages: [
                .system("You are a helpful assistant."),
                .developer("Always be concise."),
                .user("What is 2+2?"),
                .assistant("4"),
                .user("And 3+3?")
            ],
            provider: "gemini",
            maxTokens: 50
        )
        let response = try await client.complete(request: request)
        XCTAssertFalse(response.text.isEmpty)
    }

    // MARK: - Provider Options

    func testAnthropicProviderOptions() async throws {
        try skipUnlessAnthropic()
        let request = Request(
            model: "claude-haiku-4-5-20251001",
            messages: [.user("Say hello.")],
            provider: "anthropic",
            maxTokens: 50,
            providerOptions: [
                "anthropic": [
                    "beta_headers": AnyCodable(["interleaved-thinking-2025-05-14"])
                ]
            ]
        )
        let response = try await client.complete(request: request)
        XCTAssertFalse(response.text.isEmpty)
    }

    // MARK: - Error Handling

    func testAnthropicAuthError() async {
        let badAdapter = AnthropicAdapter(apiKey: "sk-invalid-key-12345")
        let badClient = LLMClient(providers: ["anthropic": badAdapter], defaultProvider: "anthropic")
        let request = Request(
            model: "claude-haiku-4-5-20251001",
            messages: [.user("test")],
            provider: "anthropic",
            maxTokens: 50
        )
        do {
            _ = try await badClient.complete(request: request)
            XCTFail("Should have thrown")
        } catch is AuthenticationError {
            // Expected
        } catch {
            // Any ProviderError is acceptable since different API keys
            // may produce different error codes
            XCTAssertTrue(error is ProviderError, "Expected ProviderError, got \(type(of: error))")
        }
    }

    func testOpenAIAuthError() async {
        let badAdapter = OpenAIAdapter(apiKey: "sk-invalid-key-12345")
        let badClient = LLMClient(providers: ["openai": badAdapter], defaultProvider: "openai")
        let request = Request(
            model: "gpt-5.2",
            messages: [.user("test")],
            provider: "openai",
            maxTokens: 50
        )
        do {
            _ = try await badClient.complete(request: request)
            XCTFail("Should have thrown")
        } catch is ProviderError {
            // Expected - AuthenticationError or similar
        } catch {
            XCTAssertTrue(error is ProviderError, "Expected ProviderError, got \(type(of: error))")
        }
    }

    func testGeminiAuthError() async {
        let badAdapter = GeminiAdapter(apiKey: "invalid-key-12345")
        let badClient = LLMClient(providers: ["gemini": badAdapter], defaultProvider: "gemini")
        let request = Request(
            model: "gemini-3-flash-preview",
            messages: [.user("test")],
            provider: "gemini",
            maxTokens: 50
        )
        do {
            _ = try await badClient.complete(request: request)
            XCTFail("Should have thrown")
        } catch is ProviderError {
            // Expected
        } catch {
            // Network or other errors acceptable
        }
    }

    // MARK: - Usage Token Counts

    func testUsageTokenCounts() async throws {
        try skipUnlessAnyProvider()

        let providers: [(String, String, String)] = [
            ("anthropic", "claude-haiku-4-5-20251001", "ANTHROPIC_API_KEY"),
            ("openai", "gpt-5.2", "OPENAI_API_KEY"),
            ("gemini", "gemini-3-flash-preview", "GEMINI_API_KEY")
        ]

        for (provider, model, envKey) in providers {
            guard ProcessInfo.processInfo.environment[envKey] != nil ||
                  (envKey == "GEMINI_API_KEY" && ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] != nil) else {
                continue
            }
            let request = Request(
                model: model,
                messages: [.user("What is 1+1? Answer with just the number.")],
                provider: provider,
                maxTokens: 50
            )
            let response = try await client.complete(request: request)
            XCTAssertGreaterThan(response.usage.inputTokens, 0, "\(provider) input tokens should be > 0")
            // For reasoning models, output tokens may include reasoning tokens
            let effectiveOutput = response.usage.outputTokens + (response.usage.reasoningTokens ?? 0)
            XCTAssertGreaterThan(effectiveOutput, 0, "\(provider) output+reasoning tokens should be > 0")
            XCTAssertGreaterThan(response.usage.totalTokens, 0, "\(provider) total tokens should be > 0")
        }
    }
}
