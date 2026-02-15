import XCTest

import Foundation

@testable import OmniAICore

final class IntegrationSmokeTests: XCTestCase {
    private func loadDotEnvIfPresent() -> [String: String] {
        // Best-effort dotenv loader so contributors can store keys in `.env` without exporting.
        let path = FileManager.default.currentDirectoryPath + "/.env"
        guard FileManager.default.fileExists(atPath: path) else { return [:] }
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }

        var out: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty {
                out[key] = value
            }
        }
        return out
    }

    private func integrationEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for (k, v) in loadDotEnvIfPresent() {
            // Preserve explicitly-exported env vars over `.env`.
            if let existing = env[k], !existing.isEmpty { continue }
            env[k] = v
        }
        return env
    }

    private func requireIntegration() throws {
        let env = integrationEnvironment()
        guard env["RUN_OMNIAI_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_OMNIAI_INTEGRATION_TESTS=1 to run live provider tests.")
        }
    }

    private func hasKey(_ name: String, env: [String: String]) -> Bool {
        let v = env[name] ?? ""
        return !v.isEmpty
    }

    private func integrationProviders(env: [String: String], dotEnv: [String: String]) -> [String] {
        if let raw = env["OMNIAI_INTEGRATION_PROVIDERS"], !raw.isEmpty {
            let parts = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts }
        }

        // Prefer providers explicitly configured in `.env` so local exported env vars don't
        // accidentally opt contributors into extra providers/cost/quota.
        if !dotEnv.isEmpty {
            var providers: [String] = []
            if hasKey("OPENAI_API_KEY", env: dotEnv) { providers.append("openai") }
            if hasKey("ANTHROPIC_API_KEY", env: dotEnv) { providers.append("anthropic") }
            if hasKey("GEMINI_API_KEY", env: dotEnv) || hasKey("GOOGLE_API_KEY", env: dotEnv) { providers.append("gemini") }
            if hasKey("CEREBRAS_API_KEY", env: dotEnv) { providers.append("cerebras") }
            if !providers.isEmpty { return providers }
        }

        return ["openai", "anthropic", "gemini", "cerebras"]
    }

    private func integrationModel(provider: String, client: Client, env: [String: String]) -> String? {
        // Default to cheaper models to reduce accidental spend.
        let useLatest = env["OMNIAI_INTEGRATION_USE_LATEST"] == "1"
        if useLatest {
            return client.getLatestModel(provider: provider)?.id
        }

        switch provider {
        case "openai":
            return (env["OPENAI_INTEGRATION_MODEL"]?.isEmpty == false ? env["OPENAI_INTEGRATION_MODEL"] : nil) ?? "gpt-5-nano-2025-08-07"
        case "anthropic":
            return (env["ANTHROPIC_INTEGRATION_MODEL"]?.isEmpty == false ? env["ANTHROPIC_INTEGRATION_MODEL"] : nil) ?? "claude-haiku-4-5"
        case "gemini":
            return (env["GEMINI_INTEGRATION_MODEL"]?.isEmpty == false ? env["GEMINI_INTEGRATION_MODEL"] : nil) ?? "gemini-3-flash-preview"
        case "cerebras":
            return (env["CEREBRAS_INTEGRATION_MODEL"]?.isEmpty == false ? env["CEREBRAS_INTEGRATION_MODEL"] : nil) ?? "zai-glm-4.7"
        default:
            return nil
        }
    }

    private func integrationProviderOptions(provider: String) -> [String: JSONValue]? {
        switch provider {
        case "cerebras":
            return ["cerebras": .object(["disable_reasoning": .bool(true)])]
        default:
            return nil
        }
    }

    func testBasicGenerationAcrossProviders() async throws {
        try requireIntegration()

        let dotEnv = loadDotEnvIfPresent()
        let env = integrationEnvironment()
        let client = try Client.fromEnv(environment: env)
        for provider in integrationProviders(env: env, dotEnv: dotEnv) {
            let keyName: String = {
                switch provider {
                case "openai": return "OPENAI_API_KEY"
                case "anthropic": return "ANTHROPIC_API_KEY"
                case "gemini": return (hasKey("GEMINI_API_KEY", env: env) ? "GEMINI_API_KEY" : "GOOGLE_API_KEY")
                case "cerebras": return "CEREBRAS_API_KEY"
                default: return ""
                }
            }()
            if keyName.isEmpty || !hasKey(keyName, env: env) { continue }

            guard let model = integrationModel(provider: provider, client: client, env: env) else {
                XCTFail("No integration model resolved for provider \(provider)")
                continue
            }

            let result: GenerateResult
            do {
                result = try await generate(
                    model: model,
                    prompt: "Return exactly the word hello.",
                    maxTokens: 128,
                    reasoningEffort: provider == "openai" ? "low" : nil,
                    provider: provider,
                    providerOptions: integrationProviderOptions(provider: provider),
                    maxRetries: 1,
                    client: client
                )
            } catch let e as ProviderError {
                let status = e.statusCode.map(String.init) ?? "nil"
                XCTFail("provider=\(provider) model=\(model) ProviderError status=\(status) message=\(e.message)")
                continue
            } catch let e as SDKError {
                XCTFail("provider=\(provider) model=\(model) SDKError message=\(e.message)")
                continue
            } catch {
                XCTFail("provider=\(provider) model=\(model) error=\(String(describing: error))")
                continue
            }

            XCTAssertFalse(
                result.text.isEmpty,
                "provider=\(provider) model=\(model) finish=\(result.finishReason.reason)"
            )
            XCTAssertGreaterThan(result.usage.inputTokens, 0, "provider=\(provider) model=\(model)")
            XCTAssertGreaterThan(result.usage.outputTokens, 0, "provider=\(provider) model=\(model)")
            XCTAssertEqual(result.finishReason.reason, "stop", "provider=\(provider) model=\(model)")
        }
    }

    func testStreamingTextMatchesAccumulatedResponse() async throws {
        try requireIntegration()

        let dotEnv = loadDotEnvIfPresent()
        let env = integrationEnvironment()
        let client = try Client.fromEnv(environment: env)
        for provider in integrationProviders(env: env, dotEnv: dotEnv) {
            let keyName: String = {
                switch provider {
                case "openai": return "OPENAI_API_KEY"
                case "anthropic": return "ANTHROPIC_API_KEY"
                case "gemini": return (hasKey("GEMINI_API_KEY", env: env) ? "GEMINI_API_KEY" : "GOOGLE_API_KEY")
                case "cerebras": return "CEREBRAS_API_KEY"
                default: return ""
                }
            }()
            if keyName.isEmpty || !hasKey(keyName, env: env) { continue }

            guard let model = integrationModel(provider: provider, client: client, env: env) else {
                XCTFail("No integration model resolved for provider \(provider)")
                continue
            }

            let result: StreamResult
            do {
                result = try await stream(
                    model: model,
                    prompt: "Return exactly the word hello.",
                    maxTokens: 128,
                    reasoningEffort: provider == "openai" ? "low" : nil,
                    provider: provider,
                    providerOptions: integrationProviderOptions(provider: provider),
                    maxRetries: 1,
                    client: client
                )
            } catch let e as ProviderError {
                let status = e.statusCode.map(String.init) ?? "nil"
                XCTFail("provider=\(provider) model=\(model) ProviderError status=\(status) message=\(e.message)")
                continue
            } catch let e as SDKError {
                XCTFail("provider=\(provider) model=\(model) SDKError message=\(e.message)")
                continue
            } catch {
                XCTFail("provider=\(provider) model=\(model) error=\(String(describing: error))")
                continue
            }

            var chunks: [String] = []
            for try await ev in result {
                if ev.type.rawValue == StreamEventType.textDelta.rawValue, let d = ev.delta {
                    chunks.append(d)
                }
            }

            let response = try await result.response()
            XCTAssertEqual(chunks.joined(), response.text, "provider=\(provider) model=\(model)")
        }
    }

    func testToolCallingRoundTripSingleToolAcrossProviders() async throws {
        try requireIntegration()

        let dotEnv = loadDotEnvIfPresent()
        let env = integrationEnvironment()
        let client = try Client.fromEnv(environment: env)

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "a": .object(["type": .string("integer")]),
                "b": .object(["type": .string("integer")]),
            ]),
            "required": .array([.string("a"), .string("b")]),
        ])

        let addTool = try Tool(name: "add", description: "Add two integers", parameters: schema) { args, _ in
            let a = Int(args["a"]?.doubleValue ?? 0)
            let b = Int(args["b"]?.doubleValue ?? 0)
            return .number(Double(a + b))
        }

        for provider in integrationProviders(env: env, dotEnv: dotEnv) {
            let keyName: String = {
                switch provider {
                case "openai": return "OPENAI_API_KEY"
                case "anthropic": return "ANTHROPIC_API_KEY"
                case "gemini": return (hasKey("GEMINI_API_KEY", env: env) ? "GEMINI_API_KEY" : "GOOGLE_API_KEY")
                case "cerebras": return "CEREBRAS_API_KEY"
                default: return ""
                }
            }()
            if keyName.isEmpty || !hasKey(keyName, env: env) { continue }

            guard let model = integrationModel(provider: provider, client: client, env: env) else {
                XCTFail("No integration model resolved for provider \(provider)")
                continue
            }

            let result: GenerateResult
            do {
                result = try await generate(
                    model: model,
                    prompt: "Use the add tool to compute 2+2. Then reply with just the number.",
                    tools: [addTool],
                    toolChoice: ToolChoice(mode: .named, toolName: "add"),
                    maxToolRounds: 3,
                    maxTokens: 128,
                    reasoningEffort: provider == "openai" ? "low" : nil,
                    provider: provider,
                    providerOptions: integrationProviderOptions(provider: provider),
                    // Live providers can return transient 5xx/429s; keep this smoke test resilient.
                    maxRetries: 1,
                    client: client
                )
            } catch let e as ProviderError {
                let status = e.statusCode.map(String.init) ?? "nil"
                XCTFail("provider=\(provider) model=\(model) ProviderError status=\(status) message=\(e.message)")
                continue
            } catch let e as SDKError {
                XCTFail("provider=\(provider) model=\(model) SDKError message=\(e.message)")
                continue
            } catch {
                XCTFail("provider=\(provider) model=\(model) error=\(String(describing: error))")
                continue
            }

            XCTAssertTrue(result.steps.count >= 2, "provider=\(provider) model=\(model)")
            XCTAssertTrue(result.text.contains("4"), "provider=\(provider) model=\(model) text=\(result.text)")
        }
    }

    func testCerebrasReasoningMode() async throws {
        try requireIntegration()

        let env = integrationEnvironment()
        guard hasKey("CEREBRAS_API_KEY", env: env) else {
            throw XCTSkip("CEREBRAS_API_KEY not set, skipping Cerebras reasoning integration test.")
        }

        let client = try Client.fromEnv(environment: env)
        guard let model = integrationModel(provider: "cerebras", client: client, env: env) else {
            XCTFail("No integration model resolved for provider cerebras")
            return
        }

        let result = try await generate(
            model: model,
            prompt: "Think through how to add 17 and 25, then answer with the final sum only.",
            maxTokens: 128,
            provider: "cerebras",
            providerOptions: ["cerebras": .object(["disable_reasoning": .bool(false)])],
            maxRetries: 1,
            client: client
        )

        // In reasoning mode, some responses may only emit reasoning text and terminate by token budget.
        XCTAssertTrue(
            (result.usage.reasoningTokens ?? 0) > 0 || !(result.reasoning?.isEmpty ?? true),
            "provider=cerebras model=\(model) expected reasoning tokens/text"
        )
        XCTAssertTrue(
            ["stop", "length", "other"].contains(result.finishReason.reason),
            "provider=cerebras model=\(model) finish=\(result.finishReason.reason)"
        )
    }
}
