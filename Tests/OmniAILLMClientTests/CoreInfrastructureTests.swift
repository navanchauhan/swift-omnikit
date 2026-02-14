import XCTest
@testable import OmniAILLMClient

// MARK: - 8.1 Core Infrastructure Tests

final class CoreInfrastructureTests: XCTestCase {

    func testClientFromEnv() {
        // This tests that Client.fromEnv() constructs a client with available providers
        let client = LLMClient.fromEnv()
        // Should not crash and should work
        XCTAssertNotNil(client)
    }

    func testClientProgrammatic() {
        let adapter = AnthropicAdapter(apiKey: "test-key")
        let client = LLMClient(
            providers: ["anthropic": adapter],
            defaultProvider: "anthropic"
        )
        XCTAssertNotNil(client)
    }

    func testProviderRoutingDefault() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil ||
            ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil ||
            ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil,
            "No API keys available"
        )
        let client = LLMClient.fromEnv()
        // Simple request without explicit provider should use default
        let request = Request(
            model: "claude-haiku-4-5-20251001",
            messages: [.user("Say 'hello' in one word.")],
            maxTokens: 50
        )
        let response = try await client.complete(request: request)
        XCTAssertFalse(response.text.isEmpty)
    }

    func testProviderRoutingExplicit() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil,
            "ANTHROPIC_API_KEY not set"
        )
        let client = LLMClient.fromEnv()
        let request = Request(
            model: "claude-haiku-4-5-20251001",
            messages: [.user("Say 'hi' in one word.")],
            provider: "anthropic",
            maxTokens: 50
        )
        let response = try await client.complete(request: request)
        XCTAssertEqual(response.provider, "anthropic")
    }

    func testConfigurationErrorWhenNoProvider() async {
        let client = LLMClient(providers: [:])
        let request = Request(model: "test", messages: [.user("test")])
        do {
            _ = try await client.complete(request: request)
            XCTFail("Should have thrown ConfigurationError")
        } catch is ConfigurationError {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(type(of: error))")
        }
    }

    func testMiddlewareExecutionOrder() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil,
            "ANTHROPIC_API_KEY not set"
        )
        var order: [String] = []
        let mw1: Middleware = { request, next in
            order.append("mw1_request")
            let response = try await next(request)
            order.append("mw1_response")
            return response
        }
        let mw2: Middleware = { request, next in
            order.append("mw2_request")
            let response = try await next(request)
            order.append("mw2_response")
            return response
        }

        let client = LLMClient.fromEnv()
        client.addMiddleware(mw1)
        client.addMiddleware(mw2)

        let request = Request(
            model: "claude-haiku-4-5-20251001",
            messages: [.user("Say 'test'.")],
            provider: "anthropic",
            maxTokens: 50
        )
        _ = try await client.complete(request: request)

        XCTAssertEqual(order[0], "mw1_request")
        XCTAssertEqual(order[1], "mw2_request")
        XCTAssertEqual(order[2], "mw2_response")
        XCTAssertEqual(order[3], "mw1_response")
    }

    func testDefaultClientLazyInit() {
        let client = getDefaultClient()
        XCTAssertNotNil(client)
    }

    func testSetDefaultClient() {
        let custom = LLMClient(providers: [:])
        setDefaultClient(custom)
        // Reset to env-based
        setDefaultClient(LLMClient.fromEnv())
    }

    func testModelCatalogGetInfo() {
        let info = ModelCatalog.getModelInfo("claude-opus-4-6")
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.provider, "anthropic")
        XCTAssertEqual(info?.supportsTools, true)
    }

    func testModelCatalogListModels() {
        let all = ModelCatalog.listModels()
        XCTAssertFalse(all.isEmpty)
        let anthropic = ModelCatalog.listModels(provider: "anthropic")
        XCTAssertTrue(anthropic.allSatisfy { $0.provider == "anthropic" })
    }

    func testModelCatalogGetLatest() {
        let latest = ModelCatalog.getLatestModel(provider: "anthropic")
        XCTAssertNotNil(latest)
        let reasoning = ModelCatalog.getLatestModel(provider: "openai", capability: "reasoning")
        XCTAssertNotNil(reasoning)
        XCTAssertTrue(reasoning!.supportsReasoning)
    }

    func testModelCatalogAliasLookup() {
        let info = ModelCatalog.getModelInfo("opus")
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.id, "claude-opus-4-6")
    }
}


