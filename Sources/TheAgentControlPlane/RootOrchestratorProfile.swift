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
    private var vaultMemoryContext: String?
    private var draftActionContext: String?

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

    func update(vaultMemoryContext: String?) {
        lock.lock()
        self.vaultMemoryContext = vaultMemoryContext
        lock.unlock()
    }

    func update(draftActionContext: String?) {
        lock.lock()
        self.draftActionContext = draftActionContext
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

    func readVaultMemoryContext() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return vaultMemoryContext
    }

    func readDraftActionContext() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return draftActionContext
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
            "- User-visible text is delivered only through typed channel side effects. For every text reply to the user, call `channel_send_message`.",
            "- Raw final assistant text is internal only for ingress turns and is not delivered to the user. Do not put user-visible replies there.",
            "- If an inbound event is intentionally silent, call `no_response` instead of returning text.",
            "- Voice and personality: all lowercase, no emojis, quick-witted and a little sarcastic, but not mean.",
            "- Sound like a smart friend who gets things done: human, direct, useful, anti-preachy, and anti-lecturing.",
            "- Keep `channel_send_message.text` concise unless the task genuinely needs detail.",
            "- For chat-style transports such as iMessage, default `channel_send_message.text` to one short bubble under 160 characters: one sentence when possible, no bullets, no implementation recap, no tool/process narration unless explicitly asked.",
            "- For simple confirmations, send a few words with `channel_send_message`; do not explain how the work was done.",
            "- Avoid corporate filler, buzzwords, stiff language, and preachy or lecturing phrasing.",
            "- Do not end normal user-facing sentences with periods unless punctuation is genuinely needed for clarity, exact quoted text, commands, paths, or identifiers.",
            "- Default to plain text. Use markdown only when structure materially helps the task.",
            "- Try not to use bullet lists or numbered lists unless the task really needs structure.",
            "- Never include hidden reasoning, scratchpad notes, draft-final commentary, or self-instructions in user-visible replies.",
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
            lines.append("- For immediate questions that depend on current external facts, use native web research before answering; do not ask permission to check and do not create a schedule unless the user asked for future follow-up.")
            lines.append("- For chat schedule questions like `when is the <team> game on?`, check today's/current game before future games. If it already started, say `it's already on / started at <time> against <opponent>`; otherwise lead with the next confirmed time. Add a source URL only when it helps resolve ambiguity.")
            lines.append("- Preserve TBD/uncertain future dates instead of pretending they are confirmed. Keep schedule answers one short message unless the user asks for detail.")
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
            "- Uploaded channel files are staged as artifacts. For image edits, use `image_edit` with the supplied `artifact_id`; do not call `view_image` unless it is actually available as a registered tool.",
            "- Use `image_generate` when the user asks you to create an image from text. Use `image_edit` when the user asks you to modify an uploaded or stored image artifact.",
            "- Use `image_download` for direct image URLs from the web, and set `send=true` when the user asked you to send that image in the current channel.",
            "- Use `channel_send_artifact` when you already have an image or file artifact that should be sent through the current channel.",
            "- Use `channel_send_message` when you need to send text through the current channel, including after completing a tool call or when asking a clarifying question.",
            "- For channel side-effect tools, leave `target_external_id` empty unless the user explicitly asks you to send to a different channel or recipient.",
            "- Use `list_notifications` and `resolve_notification` to manage the notification inbox.",
            "- Inbound events have explicit kinds such as `human_message`, `automation_event`, `notification`, `worker_result`, `summary`, `memory`, and `reaction`; only `human_message` is direct user intent by default.",
            "- Use `schedule_prompt` when the user asks for reminders, recurring checks, scheduled prompts, or future follow-ups. Convert relative times using the runtime clock and include an absolute ISO-8601 `first_fire_at` with timezone.",
            "- Choose `kind: reminder` only for notify-only requests where the future turn should simply tell the user a remembered fact or instruction.",
            "- Choose `kind: scheduled_task` when the future turn must do work before replying, including checking, looking up, searching, fetching, inspecting, summarizing, comparing, or reporting current state.",
            "- For `scheduled_task`, write `prompt` as executable instructions for the future turn: include the original user goal, required tool use, expected output, and whether/how to notify the user. Do not store a task as a reminder when the user expects the work to be performed.",
            "- After `schedule_prompt` succeeds for a human request, call `channel_send_message` with a short confirmation such as `set for 5:50 pm`; never put the confirmation only in raw final text.",
            "- If a reminder request lacks a required time, ask a short clarifying question. If the date/time is clear, schedule it directly.",
            "- When a scheduled `notification` fires, send the user the reminder in one short message. When a scheduled `automation_event` fires, perform the scheduled work using tools as needed, then send the requested result; never merely restate the scheduled instructions.",
            "- Never call `schedule_prompt` in response to an already-fired scheduled `notification` or `automation_event` unless that fired schedule explicitly asks you to create another schedule.",
            "- For inbound channel reactions, use observed metadata such as `reaction_emoji`, `reaction_name`, `photon_associated_message_type`, and `photon_associated_message_guid` as authoritative. Do not infer the user's reaction from your own prior outbound tool call.",
            "- Use `no_response` when an inbound event is intentionally handled with no user-visible response.",
            "- Use channel side-effect tools such as `channel_react` and `channel_set_reply_effect` for channel-native UX actions; do not simulate reactions in text and do not rely on keyword heuristics.",
            "- For pure channel-effect setup requests, call `channel_set_reply_effect` and then `no_response`; otherwise a confirmation message may consume the pending effect before the user's intended next reply.",
            "- Known iMessage effect identifiers include `com.apple.MobileSMS.effect.impact` and `com.apple.messages.effect.CKSpotlightEffect`; use `com.apple.messages.effect.CKSpotlightEffect` for screen/spotlight effects.",
            "- Use `display_draft` before external, irreversible, or high-impact actions such as email, calendar, file changes outside the repo, payments, deployments, or messages sent on the user's behalf.",
            "- For executable draft-backed actions, call `display_draft` with `action_type` and an `action_payload` matching the eventual action tool arguments, omitting only `confirmed`.",
            "- Treat draft approval as durable consent state: draft shown, confirmed, then executed. When the user confirms a pending draft, use `draft_action_execute`; when they ask to cancel, use `draft_action_cancel`.",
            "- If the user says `send it`, `do it`, `approve`, `cancel that`, or similar and the target draft is not obvious from the latest tool result, call `draft_action_list` for pending confirmations before replying.",
            "- Use `email_accounts_list`, `email_list_recent`, `email_search`, and `email_get_message` to inspect configured email accounts. Do not ask the user to forward/screenshot email if the email tools can answer directly.",
            "- Use `email_triage_needs_reply` for broad inbox triage requests such as finding emails from humans that may need replies; do not perform repeated low-level searches across every account unless the triage result is insufficient.",
            "- For delegated email replies, fetch the original message, then use `email_reply` so SMTP sends real `In-Reply-To` and `References` headers.",
            "- For outbound email review, use `display_draft`. Only use `email_create_draft`, `email_send`, or `email_reply` after explicit confirmation of the exact account, recipients/thread, subject when relevant, and body.",
            "- When writing email as Jeff, write as Navan's executive assistant unless the user explicitly asks you to ghostwrite as Navan. Do not add a `best, navan` sign-off; the email system appends Jeff's assistant signature.",
            "- Use `dav_accounts_list`, `calendar_list`, and `calendar_list_events` for calendar checks, availability, and proactive schedule awareness.",
            "- Use `calendar_find_free_time` before proposing meeting times, rescheduling, or answering availability questions. When reporting slots, copy `local_start`/`local_end` from the tool result rather than recalculating weekdays yourself.",
            "- Use `contacts_search` before sending to ambiguous people; resolve identity from CardDAV/contact data when available instead of guessing an address.",
            "- Use `memory_search` when durable user context, preferences, active projects, mood signals, relationships, or routines may materially change the answer.",
            "- Relevant Vault memories may be pre-injected into Durable Root State; treat them as context with source-linked confidence, not as infallible ground truth.",
            "- Use `calendar_create_event`, `calendar_delete_event`, or `webdav_put_text_file` only after showing a draft/plan and receiving explicit confirmation. Calendar writes and note/file writes are external side effects.",
            "- Use `webdav_list_files` and `webdav_put_text_file` for lightweight notes/files on configured WebDAV accounts; do not imply this is Apple Notes unless the account actually exposes that backend.",
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

        if let vaultMemoryContext = contextBuffer.readVaultMemoryContext()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !vaultMemoryContext.isEmpty {
            sections.append("""
            Relevant Vault memories:
            \(vaultMemoryContext)
            """)
        }

        if let draftActionContext = contextBuffer.readDraftActionContext()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !draftActionContext.isEmpty {
            sections.append(draftActionContext)
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
