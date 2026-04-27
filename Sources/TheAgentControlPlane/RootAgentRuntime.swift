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
    public var enableNativeWebSearch: Bool
    public var nativeWebSearchExternalWebAccess: Bool?
    public var enableSubagentTools: Bool
    public var forceCodexSystemPrompt: Bool
    public var yoloMode: Bool

    public init(
        provider: RootAgentProvider = .openai,
        model: String? = nil,
        workingDirectory: String? = nil,
        sessionID: String = "root",
        sessionConfig: SessionConfig = SessionConfig(),
        autoRestoreFromStorage: Bool = true,
        enableNativeWebSearch: Bool = true,
        nativeWebSearchExternalWebAccess: Bool? = true,
        enableSubagentTools: Bool = true,
        forceCodexSystemPrompt: Bool = false,
        yoloMode: Bool = false
    ) {
        self.provider = provider
        self.model = model
        self.workingDirectory = workingDirectory
        self.sessionID = sessionID
        self.sessionConfig = sessionConfig
        self.autoRestoreFromStorage = autoRestoreFromStorage
        self.enableNativeWebSearch = enableNativeWebSearch
        self.nativeWebSearchExternalWebAccess = nativeWebSearchExternalWebAccess
        self.enableSubagentTools = enableSubagentTools
        self.forceCodexSystemPrompt = forceCodexSystemPrompt
        self.yoloMode = yoloMode
    }
}

public struct RootAgentTurnResult: Sendable, Equatable {
    public var assistantText: String
    public var generatedImageArtifacts: [ArtifactRecord]
    public var snapshot: RootConversationSnapshot

    public init(
        assistantText: String,
        generatedImageArtifacts: [ArtifactRecord] = [],
        snapshot: RootConversationSnapshot
    ) {
        self.assistantText = assistantText
        self.generatedImageArtifacts = generatedImageArtifacts
        self.snapshot = snapshot
    }
}

public final class RootAgentRuntime: @unchecked Sendable {
    public let server: RootAgentServer
    public let session: Session
    public let profile: RootOrchestratorProfile

    private let contextBuffer: RootPromptContextBuffer
    private let ownedClient: Client?

    init(
        server: RootAgentServer,
        session: Session,
        profile: RootOrchestratorProfile,
        contextBuffer: RootPromptContextBuffer,
        ownedClient: Client?
    ) {
        self.server = server
        self.session = session
        self.profile = profile
        self.contextBuffer = contextBuffer
        self.ownedClient = ownedClient
    }

    public static func make(
        server: RootAgentServer,
        stateRoot: AgentFabricStateRoot,
        options: RootAgentRuntimeOptions = RootAgentRuntimeOptions(),
        client: Client? = nil,
        baseProfile: (any ProviderProfile)? = nil
    ) async throws -> RootAgentRuntime {
        let contextBuffer = RootPromptContextBuffer()
        let scheduledPromptStore = FileScheduledPromptStore(
            fileURL: stateRoot.runtimeDirectoryURL.appending(path: "scheduled-prompts.json")
        )
        let toolbox = RootAgentToolbox(server: server, scheduledPromptStore: scheduledPromptStore)
        let additionalTools = await toolbox.registeredTools()
        let wrappedProfile = baseProfile ?? options.provider.makeProfile(
            model: options.model,
            enableNativeWebSearch: options.effectiveEnableNativeWebSearch,
            nativeWebSearchExternalWebAccess: options.effectiveNativeWebSearchExternalWebAccess,
            forceCodexSystemPrompt: options.effectiveForceCodexSystemPrompt
        )
        let profile = RootOrchestratorProfile(
            wrapping: wrappedProfile,
            contextBuffer: contextBuffer,
            additionalTools: additionalTools,
            enableNativeWebSearch: options.effectiveEnableNativeWebSearch && wrappedProfile.id == "openai",
            enableSubagentTools: options.effectiveEnableSubagentTools
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
        let ownedClient: Client?
        if let client {
            resolvedClient = client
            ownedClient = nil
        } else {
            resolvedClient = try await Client.fromEnvAsync()
            ownedClient = resolvedClient
        }

        let session = try Session(
            profile: profile,
            environment: environment,
            client: resolvedClient,
            config: options.effectiveSessionConfig(),
            sessionID: options.sessionID,
            storageBackend: storageBackend,
            autoRestoreFromStorage: options.autoRestoreFromStorage
        )
        if options.effectiveEnableSubagentTools && profile.allowsDynamicToolRegistration {
            profile.toolRegistry.register(codexSpawnAgentTool(parentSession: session))
            profile.toolRegistry.register(codexSendInputTool(parentSession: session))
            profile.toolRegistry.register(codexWaitTool(parentSession: session))
            profile.toolRegistry.register(codexCloseAgentTool(parentSession: session))
        }

        let runtime = RootAgentRuntime(
            server: server,
            session: session,
            profile: profile,
            contextBuffer: contextBuffer,
            ownedClient: ownedClient
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
        metadata: [String: String] = [:],
        recordAssistantText: Bool = true
    ) async throws -> RootAgentTurnResult {
        _ = try await server.refreshTaskNotifications()
        _ = try await server.handleUserText(text, actorID: actorID, metadata: metadata)
        try await refreshPromptContext()

        _ = try? await session.restoreFromStorage()
        let historyBefore = await session.getHistory()
        await session.submit(text)

        let historyAfter = await session.getHistory()
        let assistantText = newestAssistantText(from: historyAfter, afterTurnCount: historyBefore.count)
        let generatedImageArtifacts = try await saveGeneratedImages(
            from: historyAfter,
            afterTurnCount: historyBefore.count
        )

        if recordAssistantText && !assistantText.isEmpty {
            _ = try await server.recordAssistantText(assistantText)
        }

        _ = try await server.refreshTaskNotifications()
        let snapshot = try await server.restoreState()
        contextBuffer.update(snapshot: snapshot)
        return RootAgentTurnResult(
            assistantText: assistantText,
            generatedImageArtifacts: generatedImageArtifacts,
            snapshot: snapshot
        )
    }

    public func close() async {
        await session.close()
        if let ownedClient {
            await ownedClient.close()
        }
    }

    private func refreshPromptContext() async throws {
        let snapshot = try await server.restoreState()
        contextBuffer.update(snapshot: snapshot)
        contextBuffer.update(skillContext: try await server.activeSkillPromptContext())
    }

    private func newestAssistantText(from history: [Turn], afterTurnCount: Int) -> String {
        let newTurns = history.dropFirst(afterTurnCount)
        for turn in newTurns.reversed() {
            guard case .assistant(let assistant) = turn else {
                continue
            }
            let sanitized = sanitizeAssistantText(assistant.content)
            if !sanitized.isEmpty {
                return sanitized
            }
        }
        return ""
    }

    private func saveGeneratedImages(
        from history: [Turn],
        afterTurnCount: Int
    ) async throws -> [ArtifactRecord] {
        let newTurns = history.dropFirst(afterTurnCount)
        var artifacts: [ArtifactRecord] = []
        for turn in newTurns {
            guard case .assistant(let assistant) = turn,
                  let rawParts = assistant.rawContentParts else {
                continue
            }
            for part in rawParts {
                guard let item = part.data,
                      item["type"]?.stringValue == "image_generation_call",
                      item["status"]?.stringValue != "failed",
                      let rawResult = item["result"]?.stringValue,
                      let imageData = Self.decodeImageGenerationResult(rawResult) else {
                    continue
                }
                let callID = item["id"]?.stringValue ?? UUID().uuidString
                let safeCallID = Self.safeDirectoryName(callID)
                let record = try await server.storeArtifact(
                    name: "\(safeCallID).png",
                    contentType: "image/png",
                    data: imageData
                )
                artifacts.append(record)
            }
        }
        return artifacts
    }

    private static func decodeImageGenerationResult(_ rawResult: String) -> Data? {
        let trimmed = rawResult.trimmingCharacters(in: .whitespacesAndNewlines)
        if let commaIndex = trimmed.firstIndex(of: ","),
           trimmed[..<commaIndex].lowercased().contains("base64") {
            return Data(base64Encoded: String(trimmed[trimmed.index(after: commaIndex)...]))
        }
        return Data(base64Encoded: trimmed)
    }

    private func sanitizeAssistantText(_ text: String) -> String {
        var candidate = text

        if let thinkRange = candidate.range(of: "</think>", options: .backwards) {
            candidate = String(candidate[thinkRange.upperBound...])
        }

        candidate = candidate
            .replacingOccurrences(of: "<response>", with: "")
            .replacingOccurrences(of: "</response>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !candidate.isEmpty {
            return candidate
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func safeDirectoryName(_ rawValue: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let sanitized = String(rawValue.map { allowed.contains($0) ? $0 : "_" })
        return sanitized.isEmpty ? "root" : sanitized
    }
}

private extension RootAgentRuntimeOptions {
    static let defaultLLMInactivityTimeoutSeconds = 180.0

    var effectiveEnableNativeWebSearch: Bool {
        provider == .openai && (enableNativeWebSearch || yoloMode)
    }

    var effectiveNativeWebSearchExternalWebAccess: Bool? {
        guard provider == .openai else {
            return nil
        }
        return nativeWebSearchExternalWebAccess
    }

    var effectiveEnableSubagentTools: Bool {
        enableSubagentTools || yoloMode
    }

    var effectiveForceCodexSystemPrompt: Bool {
        provider == .openai && (forceCodexSystemPrompt || yoloMode)
    }

    func effectiveSessionConfig() -> SessionConfig {
        var resolved = sessionConfig
        if resolved.llmInactivityTimeoutSeconds == nil {
            resolved.llmInactivityTimeoutSeconds = resolveLLMInactivityTimeoutSeconds()
        }
        if resolved.terminalToolNames.isEmpty {
            resolved.terminalToolNames = [
                "channel_send_message",
                "channel_send_artifact",
                "no_response",
            ]
        }
        if yoloMode {
            if resolved.reasoningEffort == nil {
                resolved.reasoningEffort = "high"
            }
            if resolved.parallelToolCalls == nil {
                resolved.parallelToolCalls = true
            }
            resolved.maxSubagentDepth = max(resolved.maxSubagentDepth, 3)
        }
        return resolved
    }

    private func resolveLLMInactivityTimeoutSeconds() -> Double {
        let env = ProcessInfo.processInfo.environment
        let keys = [
            "ATTRACTOR_AGENT_INACTIVITY_TIMEOUT_SECONDS",
            "ATTRACTOR_LLM_INACTIVITY_TIMEOUT_SECONDS",
        ]
        for key in keys {
            if let raw = env[key], let value = Double(raw), value > 0 {
                return value
            }
        }
        return Self.defaultLLMInactivityTimeoutSeconds
    }
}
