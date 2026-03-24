import Foundation
import OmniAIAgent
import OmniAICore
import OmniAgentMesh

public enum RootAgentProvider: String, CaseIterable, Sendable {
    case openai
    case anthropic
    case gemini

    public var defaultModel: String {
        switch self {
        case .openai:
            return "gpt-5.2"
        case .anthropic:
            return "claude-opus-4-6"
        case .gemini:
            return "gemini-3.1-pro-preview-customtools"
        }
    }

    public func makeProfile(model: String? = nil) -> any ProviderProfile {
        let resolvedModel = model ?? defaultModel
        switch self {
        case .openai:
            return OpenAIProfile(model: resolvedModel)
        case .anthropic:
            return AnthropicProfile(model: resolvedModel, enableInteractiveTools: false)
        case .gemini:
            return GeminiProfile(
                model: resolvedModel,
                interactiveMode: false,
                enablePlanTools: false
            )
        }
    }
}

final class RootPromptContextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = RootConversationSnapshot(
        summary: nil,
        hotContext: [],
        unresolvedNotifications: []
    )

    func update(snapshot: RootConversationSnapshot) {
        lock.lock()
        self.snapshot = snapshot
        lock.unlock()
    }

    func read() -> RootConversationSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}

public final class RootOrchestratorProfile: ProviderProfile, @unchecked Sendable {
    private let wrapped: any ProviderProfile
    private let contextBuffer: RootPromptContextBuffer

    public let toolRegistry: ToolRegistry

    public var id: String { wrapped.id }
    public var model: String { wrapped.model }
    public var supportsReasoning: Bool { wrapped.supportsReasoning }
    public var supportsStreaming: Bool { wrapped.supportsStreaming }
    public var supportsParallelToolCalls: Bool { wrapped.supportsParallelToolCalls }
    public var contextWindowSize: Int { wrapped.contextWindowSize }

    init(
        wrapping profile: any ProviderProfile,
        contextBuffer: RootPromptContextBuffer,
        additionalTools: [RegisteredTool]
    ) {
        self.wrapped = profile
        self.contextBuffer = contextBuffer

        let registry = ToolRegistry()
        for name in profile.toolRegistry.names() {
            guard let tool = profile.toolRegistry.get(name) else {
                continue
            }
            registry.register(tool)
        }
        for tool in additionalTools {
            registry.register(tool)
        }
        self.toolRegistry = registry
    }

    public func providerOptions() -> [String: JSONValue]? {
        wrapped.providerOptions()
    }

    public func buildSystemPrompt(
        environment: ExecutionEnvironment,
        projectDocs: String?,
        userInstructions: String?,
        gitContext: GitContext?
    ) -> String {
        let rootInstructions = buildRootInstructions()
        let mergedInstructions: String
        if let userInstructions, !userInstructions.isEmpty {
            mergedInstructions = userInstructions + "\n\n" + rootInstructions
        } else {
            mergedInstructions = rootInstructions
        }

        let basePrompt = wrapped.buildSystemPrompt(
            environment: environment,
            projectDocs: projectDocs,
            userInstructions: mergedInstructions,
            gitContext: gitContext
        )
        let durableState = buildDurableStateSection()
        guard !durableState.isEmpty else {
            return basePrompt
        }
        return basePrompt + "\n\n" + durableState
    }
}

private extension RootOrchestratorProfile {
    func buildRootInstructions() -> String {
        """
        # Root Orchestrator

        You are the root orchestrator for a durable worker fabric.

        - You are the only user-facing agent persona.
        - Default to `start_mission` for non-trivial work so planning, delegation, validation, approvals, and recovery remain durable.
        - Use `mission_status`, `wait_for_mission`, and `list_inbox` to manage active missions and blocking interactions.
        - Use `approve_request` and `answer_question` when a worker or mission is waiting on human input.
        - Handle only straightforward local work directly with your normal coding tools when that is clearly faster and sufficient.
        - Use raw task tools such as `delegate_task` only for fallback/debug flows or very bounded background work.
        - Use `list_workers` before delegation when capability placement is unclear.
        - Use `list_tasks`, `get_task_status`, and `wait_for_task` to manage delegated work.
        - Use `list_notifications` and `resolve_notification` to manage the notification inbox.
        - Be explicit about capability requirements, expected outputs, and constraints when starting missions or delegating.
        - Never claim a worker task finished unless a task-management tool proves it.
        - If no suitable worker exists, say that clearly instead of pretending delegation succeeded.
        """
    }

    func buildDurableStateSection() -> String {
        let snapshot = contextBuffer.read()
        var sections: [String] = []

        if let summary = snapshot.summary?.summaryText.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            sections.append("""
            Conversation summary:
            \(summary)
            """)
        }

        if !snapshot.unresolvedNotifications.isEmpty {
            let lines = snapshot.unresolvedNotifications.map { notification in
                "- [\(notification.notificationID)] \(notification.title): \(notification.body) (importance: \(notification.importance.rawValue), status: \(notification.status.rawValue))"
            }
            sections.append("""
            Unresolved notifications:
            \(lines.joined(separator: "\n"))
            """)
        }

        guard !sections.isEmpty else {
            return ""
        }

        return """
        # Durable Root State

        \(sections.joined(separator: "\n\n"))
        """
    }
}
