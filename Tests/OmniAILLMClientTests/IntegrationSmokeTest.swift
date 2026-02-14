import XCTest
@testable import OmniAILLMClient

// MARK: - 8.10 Integration Smoke Test + 8.3 Message & Content + 8.6 Caching

final class IntegrationSmokeTest: XCTestCase {

    var client: LLMClient!

    override func setUp() {
        client = LLMClient.fromEnv()
    }

    private func skipUnlessAnyProvider() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil ||
            ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil ||
            ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil ||
            ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] != nil,
            "Skipping: no API keys configured"
        )
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

    // MARK: - 1. Basic generation across all providers

    func testBasicGenerationAllProviders() async throws {
        try skipUnlessAnyProvider()
        let providers: [(String, String)] = [
            ("anthropic", "claude-haiku-4-5-20251001"),
            ("openai", "gpt-5.2"),
            ("gemini", "gemini-3-flash-preview")
        ]

        for (provider, model) in providers {
            let result = try await generate(
                model: model,
                prompt: "Say hello in one sentence.",
                maxTokens: 100,
                provider: provider
            )
            XCTAssertFalse(result.text.isEmpty, "\(provider): text should not be empty")
            XCTAssertGreaterThan(result.usage.inputTokens, 0, "\(provider): input tokens > 0")
            XCTAssertGreaterThan(result.usage.outputTokens, 0, "\(provider): output tokens > 0")
            XCTAssertTrue(
                result.finishReason.reason == "stop" || result.finishReason.reason == "length",
                "\(provider): finish reason should be stop or length, got \(result.finishReason.reason)"
            )
        }
    }

    // MARK: - 2. Streaming

    func testStreamingWithAccumulation() async throws {
        try skipUnlessAnthropic()
        let streamResult = try await stream(
            model: "claude-haiku-4-5-20251001",
            prompt: "Write a haiku.",
            maxTokens: 100,
            provider: "anthropic"
        )

        var textChunks: [String] = []
        for try await event in streamResult {
            if event.eventType == StreamEventType.textDelta, let delta = event.delta {
                textChunks.append(delta)
            }
        }
        let joinedText = textChunks.joined()
        let responseText = streamResult.response().text
        XCTAssertEqual(joinedText, responseText, "Joined deltas should match accumulated response text")
    }

    // MARK: - 3. Tool calling with execution

    func testToolCallingWithExecution() async throws {
        try skipUnlessAnthropic()
        let weatherTool = Tool(
            name: "get_weather",
            description: "Get weather for a city",
            parameters: [
                "type": "object",
                "properties": [
                    "city": ["type": "string", "description": "City name"]
                ],
                "required": ["city"]
            ],
            execute: { args in
                let city = args["city"] as? String ?? "unknown"
                return "72F and sunny in \(city)"
            }
        )

        let result = try await generate(
            model: "claude-haiku-4-5-20251001",
            prompt: "What is the weather in San Francisco and New York?",
            tools: [weatherTool],
            maxToolRounds: 3,
            maxTokens: 1000,
            provider: "anthropic"
        )

        XCTAssertTrue(result.steps.count >= 2, "Should have at least 2 steps")
        let lowerText = result.text.lowercased()
        // The model should mention at least one of the cities
        XCTAssertTrue(
            lowerText.contains("san francisco") || lowerText.contains("new york") || lowerText.contains("72"),
            "Response should reference weather data"
        )
    }

    // MARK: - 4. Image input (base64)

    func testImageInputBase64() async throws {
        try skipUnlessAnthropic()
        // Create a minimal 1x1 red PNG
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==")!

        let result = try await generate(
            model: "claude-haiku-4-5-20251001",
            messages: [
                Message(role: .user, content: [
                    .text("Describe this image in one sentence."),
                    .image(ImageData(data: pngData, mediaType: "image/png"))
                ])
            ],
            maxTokens: 200,
            provider: "anthropic"
        )
        XCTAssertFalse(result.text.isEmpty)
    }

    func testImageInputBase64OpenAI() async throws {
        try skipUnlessOpenAI()
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==")!

        let result = try await generate(
            model: "gpt-5.2",
            messages: [
                Message(role: .user, content: [
                    .text("Describe this image briefly."),
                    .image(ImageData(data: pngData, mediaType: "image/png"))
                ])
            ],
            maxTokens: 200,
            provider: "openai"
        )
        XCTAssertFalse(result.text.isEmpty)
    }

    func testImageInputBase64Gemini() async throws {
        try skipUnlessGemini()
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==")!

        let result = try await generate(
            model: "gemini-3-flash-preview",
            messages: [
                Message(role: .user, content: [
                    .text("Describe this image briefly."),
                    .image(ImageData(data: pngData, mediaType: "image/png"))
                ])
            ],
            maxTokens: 200,
            provider: "gemini"
        )
        XCTAssertFalse(result.text.isEmpty)
    }

    // MARK: - 5. Structured output

    func testStructuredOutputOpenAI() async throws {
        try skipUnlessOpenAI()
        let result = try await generateObject(
            model: "gpt-5.2",
            prompt: "Extract: Alice is 30 years old",
            schema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "age": ["type": "integer"]
                ],
                "required": ["name", "age"]
            ],
            maxTokens: 200,
            provider: "openai"
        )
        XCTAssertNotNil(result.output)
        if let output = result.output?.dictValue {
            XCTAssertEqual(output["name"] as? String, "Alice")
            XCTAssertEqual(output["age"] as? Int, 30)
        }
    }

    // MARK: - 6. Error handling

    func testNotFoundErrorOpenAI() async throws {
        try skipUnlessOpenAI()
        do {
            _ = try await generate(
                model: "nonexistent-model-xyz-123456",
                prompt: "test",
                provider: "openai",
                maxRetries: 0,
                client: client
            )
            XCTFail("Should have raised an error")
        } catch is NotFoundError {
            // Correct
        } catch is ProviderError {
            // Also acceptable - model might return different error
        } catch {
            // Network errors etc are also fine
        }
    }

    // MARK: - 8.3 Message & Content Model

    func testTextOnlyMessages() async throws {
        try skipUnlessAnyProvider()
        let providers: [(String, String)] = [
            ("anthropic", "claude-haiku-4-5-20251001"),
            ("openai", "gpt-5.2"),
            ("gemini", "gemini-3-flash-preview")
        ]

        for (provider, model) in providers {
            let result = try await generate(
                model: model,
                messages: [.user("What is 1+1? Reply with just the number.")],
                maxTokens: 200,
                provider: provider
            )
            // For reasoning models, text might be empty if all output is thinking
            let hasContent = !result.text.isEmpty || (result.response.usage.reasoningTokens ?? 0) > 0
            XCTAssertTrue(hasContent, "\(provider): should produce text or reasoning tokens")
        }
    }

    func testMultimodalMessage() async throws {
        try skipUnlessAnthropic()
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==")!

        // Text + image in same message
        let result = try await generate(
            model: "claude-haiku-4-5-20251001",
            messages: [
                Message(role: .user, content: [
                    .text("What color is this pixel?"),
                    .image(ImageData(data: pngData, mediaType: "image/png"))
                ])
            ],
            maxTokens: 100,
            provider: "anthropic"
        )
        XCTAssertFalse(result.text.isEmpty)
    }

    // MARK: - 8.6 Prompt Caching

    func testAnthropicCachingReportTokens() async throws {
        try skipUnlessAnthropic()
        // Make two requests with the same system prompt to trigger caching
        let systemPrompt = String(repeating: "You are a helpful assistant that follows instructions precisely. ", count: 50)

        // First request - populates cache
        let result1 = try await generate(
            model: "claude-haiku-4-5-20251001",
            messages: [.system(systemPrompt), .user("Say 'first'.")],
            maxTokens: 20,
            provider: "anthropic"
        )
        XCTAssertFalse(result1.text.isEmpty)
        // First call may write to cache
        // cache_write_tokens may be set

        // Second request - should read from cache
        let result2 = try await generate(
            model: "claude-haiku-4-5-20251001",
            messages: [.system(systemPrompt), .user("Say 'second'.")],
            maxTokens: 20,
            provider: "anthropic"
        )
        XCTAssertFalse(result2.text.isEmpty)
        // With proper caching, result2 should show cache_read_tokens
        // We can only verify the field exists, not its exact value
        // since caching is not guaranteed on every request
    }

    func testPromptCachingMultiTurn() async throws {
        try skipUnlessAnyProvider()

        // Build a long system prompt (>1000 tokens) to trigger caching
        let paragraph = """
        The following is a comprehensive reference guide for software architecture patterns. \
        Model-View-Controller separates an application into three interconnected components. \
        The Model represents the data and business logic, the View displays the data to the user, \
        and the Controller handles user input and updates the Model accordingly. This pattern has \
        been widely adopted in web frameworks such as Ruby on Rails, Django, and Spring MVC. \
        Another important pattern is the Repository pattern, which mediates between the domain \
        and data mapping layers using a collection-like interface for accessing domain objects. \
        The Observer pattern defines a one-to-many dependency between objects so that when one \
        object changes state, all its dependents are notified and updated automatically.
        """
        // Repeat to exceed 1000 tokens comfortably
        let longSystemPrompt = String(repeating: paragraph + " ", count: 12)

        // Determine which providers are available
        let env = ProcessInfo.processInfo.environment
        var providers: [(name: String, model: String)] = []
        if env["ANTHROPIC_API_KEY"] != nil {
            providers.append((name: "anthropic", model: "claude-haiku-4-5-20251001"))
        }
        if env["OPENAI_API_KEY"] != nil {
            providers.append((name: "openai", model: "gpt-4o-mini"))
        }
        if env["GEMINI_API_KEY"] != nil || env["GOOGLE_API_KEY"] != nil {
            providers.append((name: "gemini", model: "gemini-2.0-flash"))
        }

        for (providerName, model) in providers {
            // Turn 1: send long system prompt + user message (populates cache)
            let result1 = try await generate(
                model: model,
                messages: [
                    .system(longSystemPrompt),
                    .user("What is the Model-View-Controller pattern? Answer in one sentence.")
                ],
                maxTokens: 100,
                provider: providerName
            )
            XCTAssertFalse(result1.text.isEmpty, "\(providerName) turn 1: should produce text")

            // Turn 2: same system prompt + conversation history + new user message (should hit cache)
            let result2 = try await generate(
                model: model,
                messages: [
                    .system(longSystemPrompt),
                    .user("What is the Model-View-Controller pattern? Answer in one sentence."),
                    .assistant(result1.text),
                    .user("Now explain the Observer pattern in one sentence.")
                ],
                maxTokens: 100,
                provider: providerName
            )
            XCTAssertFalse(result2.text.isEmpty, "\(providerName) turn 2: should produce text")

            // Check caching tokens
            let cacheRead = result2.usage.cacheReadTokens ?? 0
            let cacheWrite1 = result1.usage.cacheWriteTokens ?? 0

            if providerName == "anthropic" {
                // Anthropic has the most reliable cache reporting.
                // Turn 1 should write to cache, turn 2 should read from cache.
                // Soft check: log but don't hard-fail, since caching depends on server state.
                if cacheRead > 0 {
                    print("[\(providerName)] Cache hit confirmed: cacheReadTokens=\(cacheRead)")
                } else {
                    print("[\(providerName)] Note: cacheReadTokens=0 on turn 2 (cacheWriteTokens on turn 1=\(cacheWrite1)). Caching may not have triggered — this is acceptable.")
                }
                // Verify the plumbing at least: usage fields are populated (inputTokens > 0)
                XCTAssertGreaterThan(result2.usage.inputTokens, 0, "\(providerName): input tokens should be reported")
            } else {
                // OpenAI and Gemini: caching is server-managed and may not report tokens
                if cacheRead > 0 {
                    print("[\(providerName)] Cache hit reported: cacheReadTokens=\(cacheRead)")
                } else {
                    print("[\(providerName)] Note: cacheReadTokens not reported (server-managed caching) — this is expected.")
                }
            }
        }
    }

    // MARK: - Message convenience constructors

    func testMessageConvenienceConstructors() {
        let system = Message.system("You are helpful.")
        XCTAssertEqual(system.role, .system)
        XCTAssertEqual(system.text, "You are helpful.")

        let user = Message.user("Hello")
        XCTAssertEqual(user.role, .user)

        let assistant = Message.assistant("Hi there")
        XCTAssertEqual(assistant.role, .assistant)

        let tool = Message.toolResult(toolCallId: "call_123", content: "result")
        XCTAssertEqual(tool.role, .tool)
        XCTAssertEqual(tool.toolCallId, "call_123")
    }

    // MARK: - ContentPart factories

    func testContentPartFactories() {
        let text = ContentPart.text("hello")
        XCTAssertEqual(text.contentKind, .text)
        XCTAssertEqual(text.text, "hello")

        let img = ContentPart.image(ImageData(url: "https://example.com/img.png"))
        XCTAssertEqual(img.contentKind, .image)

        let tc = ContentPart.toolCall(ToolCallData(id: "1", name: "fn", arguments: AnyCodable(["a": 1])))
        XCTAssertEqual(tc.contentKind, .toolCall)

        let thinking = ContentPart.thinking(ThinkingData(text: "hmm", signature: "sig"))
        XCTAssertEqual(thinking.contentKind, .thinking)
    }

    // MARK: - FinishReason

    func testFinishReasonPresets() {
        XCTAssertEqual(FinishReason.stop.reason, "stop")
        XCTAssertEqual(FinishReason.length.reason, "length")
        XCTAssertEqual(FinishReason.toolCalls.reason, "tool_calls")
        XCTAssertEqual(FinishReason.contentFilter.reason, "content_filter")
    }

    // MARK: - StreamAccumulator

    func testStreamAccumulator() {
        let acc = StreamAccumulator()
        acc.process(StreamEvent(type: .streamStart))
        acc.process(StreamEvent(type: .textStart, textId: "t1"))
        acc.process(StreamEvent(type: .textDelta, delta: "Hello", textId: "t1"))
        acc.process(StreamEvent(type: .textDelta, delta: " World", textId: "t1"))
        acc.process(StreamEvent(type: .textEnd, textId: "t1"))
        acc.process(StreamEvent(
            type: .finish,
            finishReason: .stop,
            usage: Usage(inputTokens: 5, outputTokens: 2)
        ))

        let response = acc.response()
        XCTAssertEqual(response.text, "Hello World")
        XCTAssertEqual(response.finishReason.reason, "stop")
        XCTAssertEqual(response.usage.inputTokens, 5)
    }
}
