import Foundation
import OmniAIAgent
import OmniAICore
import OmniAgentMesh
import OmniSkills

public enum RootAgentProvider: String, CaseIterable, Sendable {
    case openai
    case anthropic
    case gemini

    public var defaultModel: String {
        switch self {
        case .openai:
            return "gpt-5.4"
        case .anthropic:
            return "claude-opus-4-6"
        case .gemini:
            return "gemini-3.1-pro-preview-customtools"
        }
    }

    public func makeProfile(
        model: String? = nil,
        enableNativeWebSearch: Bool = true,
        nativeWebSearchExternalWebAccess: Bool? = true,
        forceCodexSystemPrompt: Bool = false
    ) -> any ProviderProfile {
        let resolvedModel = model ?? defaultModel
        switch self {
        case .openai:
            return OpenAIProfile(
                model: resolvedModel,
                includeWebSearch: enableNativeWebSearch,
                webSearchExternalWebAccess: nativeWebSearchExternalWebAccess,
                forceCodexSystemPrompt: forceCodexSystemPrompt
            )
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
    private var skillContext: [String: String] = [:]

    func update(snapshot: RootConversationSnapshot) {
        lock.lock()
        self.snapshot = snapshot
        lock.unlock()
    }

    func update(skillContext: [String: String]) {
        lock.lock()
        self.skillContext = skillContext
        lock.unlock()
    }

    func read() -> RootConversationSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func readSkillContext() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return skillContext
    }
}

public final class RootOrchestratorProfile: ProviderProfile, @unchecked Sendable {
    private let wrapped: any ProviderProfile
    private let contextBuffer: RootPromptContextBuffer
    private let enableNativeWebSearch: Bool
    private let enableSubagentTools: Bool
    private let compatibilityDirectReplyMode: Bool

    public let toolRegistry: ToolRegistry

    public var id: String { wrapped.id }
    public var model: String { wrapped.model }
    public var supportsReasoning: Bool { wrapped.supportsReasoning }
    public var supportsStreaming: Bool { wrapped.supportsStreaming }
    public var supportsPreviousResponseId: Bool { wrapped.supportsPreviousResponseId }
    public var supportsParallelToolCalls: Bool { wrapped.supportsParallelToolCalls }
    public var contextWindowSize: Int { wrapped.contextWindowSize }
    var allowsDynamicToolRegistration: Bool { !compatibilityDirectReplyMode }

    init(
        wrapping profile: any ProviderProfile,
        contextBuffer: RootPromptContextBuffer,
        additionalTools: [RegisteredTool],
        enableNativeWebSearch: Bool = false,
        enableSubagentTools: Bool = false
    ) {
        self.wrapped = profile
        self.contextBuffer = contextBuffer
        self.enableNativeWebSearch = enableNativeWebSearch
        self.enableSubagentTools = enableSubagentTools
        self.compatibilityDirectReplyMode = Self.shouldUseCompatibilityDirectReplyMode(for: profile)

        let registry = ToolRegistry()
        if !compatibilityDirectReplyMode {
            for name in profile.toolRegistry.names() {
                guard let tool = profile.toolRegistry.get(name) else {
                    continue
                }
                registry.register(tool)
            }
            for tool in additionalTools {
                registry.register(tool)
            }
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

        var sections = [basePrompt, buildRuntimeClockSection()]
        let durableState = buildDurableStateSection()
        if !durableState.isEmpty {
            sections.append(durableState)
        }
        return sections.joined(separator: "\n\n")
    }
}

private extension RootOrchestratorProfile {
    static func shouldUseCompatibilityDirectReplyMode(for profile: any ProviderProfile) -> Bool {
        guard profile.id == "openai" else {
            return false
        }

        let environment = ProcessInfo.processInfo.environment
        guard let baseURL = environment["OPENAI_BASE_URL"],
              let url = URL(string: baseURL),
              let host = url.host?.lowercased(),
              !host.hasSuffix("openai.com")
        else {
            return false
        }

        let model = profile.model.lowercased()
        return model.contains("qwopus") || model.contains("qwen") || model.contains("llama")
    }

    func buildRootInstructions() -> String {
        if compatibilityDirectReplyMode {
            return [
                "# Root Assistant",
                "",
                "You are the user-facing assistant.",
                "- reply directly to the user in plain text",
                "- keep replies concise and useful",
                "- do not emit tool calls, xml tags, wrapper text, or roleplay markup",
                "- answer with the final user-facing message only",
                "- if you are unsure, say so briefly instead of inventing details",
            ].joined(separator: "\n")
        }

        var lines = [
            "# Root Orchestrator",
            "",
            "You are the root orchestrator for a durable worker fabric.",
            "",
            "- You are the only user-facing agent persona.",
            "- Workers and subagents are not user-facing. They report to you, and you decide what to tell the user.",
            "- Voice and personality: all lowercase, no emojis, quick-witted and a little sarcastic, but not mean.",
            "- Sound like a smart friend who gets things done: human, direct, useful, anti-preachy, and anti-lecturing.",
            "- Keep replies concise unless the task genuinely needs detail.",
            "- Avoid corporate filler, buzzwords, stiff language, and preachy or lecturing phrasing.",
            "- Do not end normal user-facing sentences with periods unless punctuation is genuinely needed for clarity, exact quoted text, commands, paths, or identifiers.",
            "- Default to plain text. Use markdown only when structure materially helps the task.",
            "- Try not to use bullet lists or numbered lists unless the task really needs structure.",
            "- When reporting completed work, include exact identifiers and field names when relevant, such as `mission_id`, `task_id`, `worker_id`, `artifact_id`, `request_id`, `delivery_id`, or `skill_id`.",
            "- When dates matter operationally, include the day of week plus the month and day.",
            "- You have direct coding tools in this session, including `exec_command`, `write_stdin`, `read_file`, `grep`, `glob`, `list_dir`, `apply_patch`, `update_plan`, and the root mission-control tools.",
            "- You can inspect the repo, run local commands, edit files, plan work, and manage delegated missions from this session.",
            "- When the user asks whether you can run commands, inspect files, edit code, or use tools, answer from the actual registered tool surface in this runtime.",
            "- Do not claim you lack tool access unless a required tool is actually unavailable or a tool call has already failed.",
            "- Relay tool outputs faithfully and never invent facts, URLs, permissions, identifiers, or tool results.",
            "- Retry the same search or action at most three times before surfacing the failure clearly.",
            "- Use the smallest tool that can complete the task.",
            "- Prefer direct tool calls for simple work and only escalate to mission orchestration when the work is genuinely non-trivial.",
        ]

        if enableNativeWebSearch {
            lines.append("- You can use native web research when current external information matters.")
            lines.append("- Describe that capability as native web research; do not claim there is a `web.run` tool unless one is actually registered.")
        }
        if enableSubagentTools {
            lines.append("- You can spawn and supervise background subagents with `spawn_agent`, `send_input`, `wait`, and `close_agent` when direct delegation is the right tool.")
        }

        lines.append(contentsOf: [
            "- Default to `start_mission` for non-trivial work so planning, delegation, validation, approvals, and recovery remain durable.",
            "- Use `manage_tpu_experiment` when the user asks about the TPU teacher-training environment, experiment status, evaluation, validation sample export, reruns, or result-improvement work.",
            "- Use `mission_status`, `wait_for_mission`, and `list_inbox` to manage active missions and blocking interactions.",
            "- Use `approve_request` and `answer_question` when a worker or mission is waiting on human input.",
            "- Handle only straightforward local work directly with your normal coding tools when that is clearly faster and sufficient.",
            "- Use raw task tools such as `delegate_task` only for fallback/debug flows or very bounded background work.",
            "- Use `list_workers` before delegation when capability placement is unclear.",
            "- Use `list_tasks`, `get_task_status`, and `wait_for_task` to manage delegated work.",
            "- Use `list_artifacts` and `get_artifact` to inspect stored task and mission artifacts before answering follow-up questions about prior work.",
            "- Use `list_notifications` and `resolve_notification` to manage the notification inbox.",
            "- Be explicit about capability requirements, expected outputs, and constraints when starting missions or delegating.",
            "- Never claim a worker task finished unless a task-management tool proves it.",
            "- If no suitable worker exists, say that clearly instead of pretending delegation succeeded.",
        ])

        return lines.joined(separator: "\n")
    }

    func buildRuntimeClockSection(now: Date = Date()) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = isoFormatter.string(from: now)

        let displayFormatter = DateFormatter()
        displayFormatter.locale = Locale(identifier: "en_US_POSIX")
        displayFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a zzz"
        let displayTime = displayFormatter.string(from: now)

        return """
        # Runtime Clock Context

        - Current local date/time: \(displayTime)
        - Current timestamp (ISO 8601): \(timestamp)
        - Use this runtime clock context when the user asks what time or date it is right now.
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

        let skillContext = contextBuffer.readSkillContext()
        if let activeSkillIDs = skillContext["omni_skills.active_ids"],
           !activeSkillIDs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let overlay = skillContext["omni_skills.prompt_overlay"] ?? ""
            var body = "Active skills: \(activeSkillIDs)"
            if !overlay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body += "\n\nSkill overlay:\n\(overlay)"
            }
            sections.append(body)
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
