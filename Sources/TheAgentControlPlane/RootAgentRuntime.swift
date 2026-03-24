import Foundation
import OmniAIAgent
import OmniAICore
import OmniAgentMesh

public struct RootAgentRuntimeOptions: Sendable {
    public var provider: RootAgentProvider
    public var model: String?
    public var workingDirectory: String?
    public var sessionID: String
    public var sessionConfig: SessionConfig
    public var autoRestoreFromStorage: Bool

    public init(
        provider: RootAgentProvider = .openai,
        model: String? = nil,
        workingDirectory: String? = nil,
        sessionID: String = "root",
        sessionConfig: SessionConfig = SessionConfig(),
        autoRestoreFromStorage: Bool = true
    ) {
        self.provider = provider
        self.model = model
        self.workingDirectory = workingDirectory
        self.sessionID = sessionID
        self.sessionConfig = sessionConfig
        self.autoRestoreFromStorage = autoRestoreFromStorage
    }
}

public struct RootAgentTurnResult: Sendable, Equatable {
    public var assistantText: String
    public var snapshot: RootConversationSnapshot

    public init(assistantText: String, snapshot: RootConversationSnapshot) {
        self.assistantText = assistantText
        self.snapshot = snapshot
    }
}

public final class RootAgentRuntime: @unchecked Sendable {
    public let server: RootAgentServer
    public let session: Session

    private let contextBuffer: RootPromptContextBuffer

    init(
        server: RootAgentServer,
        session: Session,
        contextBuffer: RootPromptContextBuffer
    ) {
        self.server = server
        self.session = session
        self.contextBuffer = contextBuffer
    }

    public static func make(
        server: RootAgentServer,
        stateRoot: AgentFabricStateRoot,
        options: RootAgentRuntimeOptions = RootAgentRuntimeOptions(),
        client: Client? = nil,
        baseProfile: (any ProviderProfile)? = nil
    ) async throws -> RootAgentRuntime {
        let contextBuffer = RootPromptContextBuffer()
        let toolbox = RootAgentToolbox(server: server)
        let additionalTools = await toolbox.registeredTools()
        let wrappedProfile = baseProfile ?? options.provider.makeProfile(model: options.model)
        let profile = RootOrchestratorProfile(
            wrapping: wrappedProfile,
            contextBuffer: contextBuffer,
            additionalTools: additionalTools
        )

        let workingDirectory = options.workingDirectory ?? FileManager.default.currentDirectoryPath
        let environment = LocalExecutionEnvironment(workingDir: workingDirectory)
        try await environment.initialize()

        let sessionStorageRoot = stateRoot.checkpointsDirectoryURL.appending(
            path: "root-session-\(safeDirectoryName(options.sessionID))",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: sessionStorageRoot, withIntermediateDirectories: true)
        let storageBackend = FileSessionStorageBackend(rootDirectory: sessionStorageRoot)

        let resolvedClient: Client
        if let client {
            resolvedClient = client
        } else {
            resolvedClient = try Client.fromEnv()
        }

        let session = try Session(
            profile: profile,
            environment: environment,
            client: resolvedClient,
            config: options.sessionConfig,
            sessionID: options.sessionID,
            storageBackend: storageBackend,
            autoRestoreFromStorage: options.autoRestoreFromStorage
        )

        let runtime = RootAgentRuntime(
            server: server,
            session: session,
            contextBuffer: contextBuffer
        )
        try await runtime.refreshPromptContext()
        return runtime
    }

    public func restoreState() async throws -> RootConversationSnapshot {
        try await refreshPromptContext()
        return try await server.restoreState()
    }

    public func submitUserText(
        _ text: String,
        actorID: ActorID? = nil,
        metadata: [String: String] = [:]
    ) async throws -> RootAgentTurnResult {
        _ = try await server.refreshTaskNotifications()
        _ = try await server.handleUserText(text, actorID: actorID, metadata: metadata)
        try await refreshPromptContext()

        _ = try? await session.restoreFromStorage()
        let historyBefore = await session.getHistory()
        await session.submit(text)

        let historyAfter = await session.getHistory()
        let assistantText = newestAssistantText(from: historyAfter, afterTurnCount: historyBefore.count)

        if !assistantText.isEmpty {
            _ = try await server.recordAssistantText(assistantText)
        }

        _ = try await server.refreshTaskNotifications()
        let snapshot = try await server.restoreState()
        contextBuffer.update(snapshot: snapshot)
        return RootAgentTurnResult(assistantText: assistantText, snapshot: snapshot)
    }

    public func close() async {
        await session.close()
    }

    private func refreshPromptContext() async throws {
        let snapshot = try await server.restoreState()
        contextBuffer.update(snapshot: snapshot)
    }

    private func newestAssistantText(from history: [Turn], afterTurnCount: Int) -> String {
        let newTurns = history.dropFirst(afterTurnCount)
        for turn in newTurns.reversed() {
            guard case .assistant(let assistant) = turn else {
                continue
            }
            let trimmed = assistant.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return assistant.content
            }
        }
        return ""
    }

    private static func safeDirectoryName(_ rawValue: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let sanitized = String(rawValue.map { allowed.contains($0) ? $0 : "_" })
        return sanitized.isEmpty ? "root" : sanitized
    }
}
