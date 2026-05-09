import Foundation
import OmniAICore
import OmniExecution

/// High-level factory for creating coding agent sessions.
public struct CodingAgent {
    /// Create a session with a specific provider profile.
    public static func createSession(
        profile: ProviderProfile,
        workingDir: String? = nil,
        executionBackend: ExecutionBackend = .local,
        environment: (any ExecutionEnvironment)? = nil,
        config: SessionConfig = SessionConfig(),
        client: Client? = nil,
        sessionID: String = UUID().uuidString,
        storageBackend: (any SessionStorageBackend)? = nil,
        autoRestoreFromStorage: Bool = true
    ) async throws -> Session {
        let env: any ExecutionEnvironment
        if let environment {
            env = environment
        } else {
            env = try await createExecutionEnvironment(
                workingDir: workingDir,
                executionBackend: executionBackend,
                config: config
            )
        }
        try await env.initialize()

        let session = try Session(
            profile: profile,
            environment: env,
            client: client,
            config: config,
            sessionID: sessionID,
            storageBackend: storageBackend,
            autoRestoreFromStorage: autoRestoreFromStorage
        )

        await session.eventEmitter.emit(SessionEvent(kind: .sessionStart, sessionId: session.id))
        return session
    }

    /// Create an OpenAI-backed session.
    public static func openai(
        model: String = "gpt-5.4",
        workingDir: String? = nil,
        executionBackend: ExecutionBackend = .local,
        config: SessionConfig = SessionConfig(),
        client: Client? = nil,
        sessionID: String = UUID().uuidString,
        storageBackend: (any SessionStorageBackend)? = nil,
        autoRestoreFromStorage: Bool = true
    ) async throws -> Session {
        let profile = OpenAIProfile(model: model)
        let session = try await createSession(
            profile: profile,
            workingDir: workingDir,
            executionBackend: executionBackend,
            config: config,
            client: client,
            sessionID: sessionID,
            storageBackend: storageBackend,
            autoRestoreFromStorage: autoRestoreFromStorage
        )
        // Register subagent tools now that we have the session
        let fullProfile = OpenAIProfile(model: model, session: session)
        return try Session(
            profile: fullProfile,
            environment: session.executionEnv,
            client: client,
            config: config,
            sessionID: sessionID,
            storageBackend: storageBackend,
            autoRestoreFromStorage: autoRestoreFromStorage
        )
    }

    /// Create an Anthropic-backed session.
    public static func anthropic(
        model: String = "claude-haiku-4-5",
        workingDir: String? = nil,
        executionBackend: ExecutionBackend = .local,
        config: SessionConfig = SessionConfig(),
        client: Client? = nil,
        sessionID: String = UUID().uuidString,
        storageBackend: (any SessionStorageBackend)? = nil,
        autoRestoreFromStorage: Bool = true
    ) async throws -> Session {
        let profile = AnthropicProfile(model: model)
        let session = try await createSession(
            profile: profile,
            workingDir: workingDir,
            executionBackend: executionBackend,
            config: config,
            client: client,
            sessionID: sessionID,
            storageBackend: storageBackend,
            autoRestoreFromStorage: autoRestoreFromStorage
        )
        let fullProfile = AnthropicProfile(model: model, session: session)
        return try Session(
            profile: fullProfile,
            environment: session.executionEnv,
            client: client,
            config: config,
            sessionID: sessionID,
            storageBackend: storageBackend,
            autoRestoreFromStorage: autoRestoreFromStorage
        )
    }

    /// Create a Gemini-backed session.
    public static func gemini(
        model: String = "gemini-3-flash-preview",
        workingDir: String? = nil,
        executionBackend: ExecutionBackend = .local,
        config: SessionConfig = SessionConfig(),
        client: Client? = nil,
        sessionID: String = UUID().uuidString,
        storageBackend: (any SessionStorageBackend)? = nil,
        autoRestoreFromStorage: Bool = true
    ) async throws -> Session {
        let profile = GeminiProfile(model: model)
        let session = try await createSession(
            profile: profile,
            workingDir: workingDir,
            executionBackend: executionBackend,
            config: config,
            client: client,
            sessionID: sessionID,
            storageBackend: storageBackend,
            autoRestoreFromStorage: autoRestoreFromStorage
        )
        let fullProfile = GeminiProfile(model: model, session: session)
        return try Session(
            profile: fullProfile,
            environment: session.executionEnv,
            client: client,
            config: config,
            sessionID: sessionID,
            storageBackend: storageBackend,
            autoRestoreFromStorage: autoRestoreFromStorage
        )
    }

    public static func createExecutionEnvironment(
        workingDir: String?,
        executionBackend: ExecutionBackend,
        config: SessionConfig = SessionConfig()
    ) async throws -> any ExecutionEnvironment {
        try await makeExecutionEnvironment(
            workingDir: workingDir,
            executionBackend: executionBackend,
            config: config
        )
    }

    private static func makeExecutionEnvironment(
        workingDir: String?,
        executionBackend: ExecutionBackend,
        config: SessionConfig
    ) async throws -> any ExecutionEnvironment {
        switch executionBackend {
        case .local:
            return LocalExecutionEnvironment(workingDir: workingDir)
        case .swiftBash(let backendConfig):
            return SwiftBashExecutionEnvironment(
                workingDir: workingDir,
                config: backendConfig
            )
        }
    }

}
