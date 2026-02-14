import XCTest
@testable import OmniAILLMClient

// MARK: - 8.4 Generation Tests + 8.7 Tool Calling + 8.5 Reasoning

final class HighLevelAPITests: XCTestCase {

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

    // MARK: - generate() basics

    func testGenerateWithPrompt() async throws {
        try skipUnlessAnthropic()
        let result = try await generate(
            model: "claude-haiku-4-5-20251001",
            prompt: "Say 'hello' and nothing else.",
            maxTokens: 20,
            provider: "anthropic"
        )
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertEqual(result.finishReason.reason, "stop")
        XCTAssertGreaterThan(result.usage.inputTokens, 0)
    }

    func testGenerateWithMessages() async throws {
        try skipUnlessAnthropic()
        let result = try await generate(
            model: "claude-haiku-4-5-20251001",
            messages: [
                .system("You are a math tutor."),
                .user("What is 5+5?")
            ],
            maxTokens: 50,
            provider: "anthropic"
        )
        XCTAssertFalse(result.text.isEmpty)
    }

    func testGenerateRejectsBothPromptAndMessages() async {
        do {
            _ = try await generate(
                model: "claude-haiku-4-5-20251001",
                prompt: "hello",
                messages: [.user("world")]
            )
            XCTFail("Should have thrown")
        } catch is ConfigurationError {
            // Expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - stream() basics

    func testStreamTextDeltas() async throws {
        try skipUnlessAnthropic()
        let result = try await stream(
            model: "claude-haiku-4-5-20251001",
            prompt: "Write a haiku about coding.",
            maxTokens: 500,
            provider: "anthropic"
        )
        var chunks: [String] = []
        for try await event in result {
            if event.eventType == StreamEventType.textDelta, let delta = event.delta {
                chunks.append(delta)
            }
        }
        XCTAssertFalse(chunks.isEmpty)
        let fullText = chunks.joined()
        let responseText = result.response().text
        XCTAssertEqual(fullText, responseText)
    }

    func testStreamStartAndFinish() async throws {
        try skipUnlessAnthropic()
        let result = try await stream(
            model: "claude-haiku-4-5-20251001",
            prompt: "Say 'ok'.",
            maxTokens: 50,
            provider: "anthropic"
        )
        var gotFinish = false
        for try await event in result {
            if event.eventType == StreamEventType.finish {
                gotFinish = true
                XCTAssertNotNil(event.usage)
                XCTAssertNotNil(event.finishReason)
            }
        }
        XCTAssertTrue(gotFinish)
    }

    // MARK: - Tool Calling

    func testSingleToolCallAnthropic() async throws {
        try skipUnlessAnthropic()
        let weatherTool = Tool(
            name: "get_weather",
            description: "Get the current weather for a location",
            parameters: [
                "type": "object",
                "properties": [
                    "location": ["type": "string", "description": "City name"]
                ],
                "required": ["location"]
            ],
            execute: { args in
                let location = args["location"] as? String ?? "unknown"
                return "72F and sunny in \(location)"
            }
        )

        let result = try await generate(
            model: "claude-haiku-4-5-20251001",
            prompt: "What is the weather in San Francisco?",
            tools: [weatherTool],
            maxToolRounds: 3,
            maxTokens: 500,
            provider: "anthropic"
        )
        XCTAssertTrue(result.steps.count >= 2, "Should have at least 2 steps (initial + after tool)")
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertGreaterThan(result.totalUsage.inputTokens, result.usage.inputTokens)
    }

    func testSingleToolCallOpenAI() async throws {
        try skipUnlessOpenAI()
        let weatherTool = Tool(
            name: "get_weather",
            description: "Get the current weather for a location",
            parameters: [
                "type": "object",
                "properties": [
                    "location": ["type": "string", "description": "City name"]
                ],
                "required": ["location"]
            ],
            execute: { args in
                let location = args["location"] as? String ?? "unknown"
                return "72F and sunny in \(location)"
            }
        )

        let result = try await generate(
            model: "gpt-5.2",
            prompt: "What is the weather in San Francisco?",
            tools: [weatherTool],
            maxToolRounds: 3,
            maxTokens: 500,
            provider: "openai"
        )
        XCTAssertTrue(result.steps.count >= 2)
        XCTAssertFalse(result.text.isEmpty)
    }

    func testSingleToolCallGemini() async throws {
        try skipUnlessGemini()
        let weatherTool = Tool(
            name: "get_weather",
            description: "Get the current weather for a location",
            parameters: [
                "type": "object",
                "properties": [
                    "location": ["type": "string", "description": "City name"]
                ],
                "required": ["location"]
            ],
            execute: { args in
                let location = args["location"] as? String ?? "unknown"
                return "72F and sunny in \(location)"
            }
        )

        let result = try await generate(
            model: "gemini-3-flash-preview",
            prompt: "What is the weather in San Francisco?",
            tools: [weatherTool],
            maxToolRounds: 3,
            maxTokens: 500,
            provider: "gemini"
        )
        XCTAssertTrue(result.steps.count >= 2)
        XCTAssertFalse(result.text.isEmpty)
    }

    func testMaxToolRoundsZero() async throws {
        try skipUnlessAnthropic()
        let tool = Tool(
            name: "test_tool",
            description: "A test tool",
            parameters: ["type": "object", "properties": [:]],
            execute: { _ in "result" }
        )

        let result = try await generate(
            model: "claude-haiku-4-5-20251001",
            prompt: "Call the test_tool.",
            tools: [tool],
            maxToolRounds: 0,
            maxTokens: 200,
            provider: "anthropic"
        )
        // With maxToolRounds=0, tools should NOT be auto-executed
        XCTAssertEqual(result.steps.count, 1)
    }

    func testPassiveToolsReturnCalls() async throws {
        try skipUnlessAnthropic()
        let passiveTool = Tool(
            name: "search",
            description: "Search for information",
            parameters: [
                "type": "object",
                "properties": [
                    "query": ["type": "string"]
                ],
                "required": ["query"]
            ]
            // No execute handler = passive
        )

        let result = try await generate(
            model: "claude-haiku-4-5-20251001",
            prompt: "Search for 'Swift programming'.",
            tools: [passiveTool],
            toolChoice: .named("search"),
            maxToolRounds: 0,
            maxTokens: 200,
            provider: "anthropic"
        )
        // Should have tool calls in the response but no execution
        XCTAssertFalse(result.toolCalls.isEmpty, "Should have tool calls returned")
    }

    func testToolExecutionErrors() async throws {
        try skipUnlessAnthropic()
        let failingTool = Tool(
            name: "failing_tool",
            description: "A tool that always fails",
            parameters: ["type": "object", "properties": [:]],
            execute: { _ in
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tool failed!"])
            }
        )

        // Should not throw - error should be sent to model
        let result = try await generate(
            model: "claude-haiku-4-5-20251001",
            prompt: "Call the failing_tool then explain what happened.",
            tools: [failingTool],
            toolChoice: .named("failing_tool"),
            maxToolRounds: 2,
            maxTokens: 500,
            provider: "anthropic"
        )
        XCTAssertTrue(result.steps.count >= 1, "Should have at least one step")
    }

    func testToolChoiceModes() async throws {
        try skipUnlessAnthropic()
        let tool = Tool(
            name: "calculator",
            description: "A calculator",
            parameters: [
                "type": "object",
                "properties": ["expression": ["type": "string"]],
                "required": ["expression"]
            ]
        )

        // Test "none" mode - model should NOT call tools
        let result = try await generate(
            model: "claude-haiku-4-5-20251001",
            prompt: "What is 2+2? Just answer with the number.",
            tools: [tool],
            toolChoice: .none,
            maxToolRounds: 0,
            maxTokens: 200,
            provider: "anthropic"
        )
        XCTAssertTrue(result.steps.count >= 1)
    }

    // MARK: - generate_object()

    func testGenerateObjectOpenAI() async throws {
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
        let output = result.output!.dictValue
        XCTAssertNotNil(output)
        XCTAssertEqual(output?["name"] as? String, "Alice")
        XCTAssertEqual(output?["age"] as? Int, 30)
    }

    func testGenerateObjectAnthropic() async throws {
        try skipUnlessAnthropic()
        let result = try await generateObject(
            model: "claude-haiku-4-5-20251001",
            prompt: "Extract: Bob is 25 years old",
            schema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "age": ["type": "integer"]
                ],
                "required": ["name", "age"]
            ],
            maxTokens: 200,
            provider: "anthropic"
        )
        XCTAssertNotNil(result.output)
        let output: [String: Any]? = result.output?.dictValue
        XCTAssertNotNil(output)
    }

    func testGenerateObjectGemini() async throws {
        try skipUnlessGemini()
        let result = try await generateObject(
            model: "gemini-3-flash-preview",
            prompt: "Extract the name and age: Carol is 40 years old. Return as JSON.",
            schema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "age": ["type": "integer"]
                ],
                "required": ["name", "age"]
            ],
            maxTokens: 1000,
            provider: "gemini"
        )
        XCTAssertNotNil(result.output)
    }

    // MARK: - Reasoning/Thinking (8.5)

    func testOpenAIReasoningEffort() async throws {
        try skipUnlessOpenAI()
        let activeClient = LLMClient.fromEnv()
        let request = Request(
            model: "o4-mini",
            messages: [.user("What is 15 * 23? Think step by step.")],
            provider: "openai",
            maxTokens: 2000,
            reasoningEffort: "low"
        )
        let response = try await activeClient.complete(request: request)
        XCTAssertFalse(response.text.isEmpty)
    }

    // MARK: - Usage Addition

    func testUsageAddition() {
        let a = Usage(inputTokens: 10, outputTokens: 5, reasoningTokens: 2, cacheReadTokens: 3)
        let b = Usage(inputTokens: 20, outputTokens: 10, reasoningTokens: nil, cacheReadTokens: 7)
        let sum = a + b
        XCTAssertEqual(sum.inputTokens, 30)
        XCTAssertEqual(sum.outputTokens, 15)
        XCTAssertEqual(sum.totalTokens, 45)
        XCTAssertEqual(sum.reasoningTokens, 2) // 2 + nil(0)
        XCTAssertEqual(sum.cacheReadTokens, 10)
    }

    func testUsageAdditionBothNil() {
        let a = Usage(inputTokens: 10, outputTokens: 5)
        let b = Usage(inputTokens: 20, outputTokens: 10)
        let sum = a + b
        XCTAssertNil(sum.reasoningTokens)
        XCTAssertNil(sum.cacheReadTokens)
    }
}
