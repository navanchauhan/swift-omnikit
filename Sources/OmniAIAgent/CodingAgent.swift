import Foundation
import OmniAILLMClient

/// High-level factory for creating coding agent sessions.
public struct CodingAgent {
    /// Create a session with a specific provider profile.
    public static func createSession(
        profile: ProviderProfile,
        workingDir: String? = nil,
        config: SessionConfig = SessionConfig(),
        client: LLMClient? = nil
    ) async throws -> Session {
        let env = LocalExecutionEnvironment(workingDir: workingDir)
        try await env.initialize()

        let session = Session(
            profile: profile,
            environment: env,
            client: client,
            config: config
        )

        await session.eventEmitter.emit(SessionEvent(kind: .sessionStart, sessionId: await session.id))
        return session
    }

    /// Create an OpenAI-backed session.
    public static func openai(
        model: String = "gpt-5.2",
        workingDir: String? = nil,
        config: SessionConfig = SessionConfig(),
        client: LLMClient? = nil
    ) async throws -> Session {
        let profile = OpenAIProfile(model: model)
        let session = try await createSession(
            profile: profile,
            workingDir: workingDir,
            config: config,
            client: client
        )
        // Register subagent tools now that we have the session
        let fullProfile = OpenAIProfile(model: model, session: session)
        return Session(
            profile: fullProfile,
            environment: session.executionEnv,
            client: client ?? LLMClient.fromEnv(),
            config: config
        )
    }

    /// Create an Anthropic-backed session.
    public static func anthropic(
        model: String = "claude-haiku-4-5-20251001",
        workingDir: String? = nil,
        config: SessionConfig = SessionConfig(),
        client: LLMClient? = nil
    ) async throws -> Session {
        let profile = AnthropicProfile(model: model)
        let session = try await createSession(
            profile: profile,
            workingDir: workingDir,
            config: config,
            client: client
        )
        let fullProfile = AnthropicProfile(model: model, session: session)
        return Session(
            profile: fullProfile,
            environment: session.executionEnv,
            client: client ?? LLMClient.fromEnv(),
            config: config
        )
    }

    /// Create a Gemini-backed session.
    public static func gemini(
        model: String = "gemini-3-flash-preview",
        workingDir: String? = nil,
        config: SessionConfig = SessionConfig(),
        client: LLMClient? = nil
    ) async throws -> Session {
        let profile = GeminiProfile(model: model)
        let session = try await createSession(
            profile: profile,
            workingDir: workingDir,
            config: config,
            client: client
        )
        let fullProfile = GeminiProfile(model: model, session: session)
        return Session(
            profile: fullProfile,
            environment: session.executionEnv,
            client: client ?? LLMClient.fromEnv(),
            config: config
        )
    }
}
