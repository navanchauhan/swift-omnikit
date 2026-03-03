import Foundation
import OmniAICore
import OmniAIAgent

// MARK: - Coding Agent Backend

/// A CodergenBackend that uses CodingAgentLoop sessions instead of raw LLM text generation.
/// Each pipeline node gets a full coding agent with file read/write, shell execution, grep, glob, etc.
public final class CodingAgentBackend: CodergenBackend, @unchecked Sendable {
    private let client: Client?
    private let workingDirectory: String

    public init(client: Client? = nil, workingDirectory: String? = nil) {
        self.client = client
        self.workingDirectory = workingDirectory ?? FileManager.default.currentDirectoryPath
    }

    public func run(
        prompt: String,
        model: String,
        provider: String,
        reasoningEffort: String,
        context: PipelineContext
    ) async throws -> CodergenResult {
        let resolvedClient = try (client ?? Client.fromEnv())
        // 1. Build the enriched prompt with pipeline context
        let enrichedPrompt = buildEnrichedPrompt(prompt: prompt, context: context)

        // 2. Create the provider profile
        let profile = createProfile(provider: provider, model: model)

        // 3. Read max_agent_turns from context (set by node attributes)
        let maxTurns = context.getInt("_current_node_max_agent_turns")

        // 4. Configure the session
        let sessionConfig = SessionConfig(
            maxTurns: 0,  // No limit — natural completion only
            maxToolRoundsPerInput: 0,  // No limit — let the model run until it returns text with no tool calls
            defaultCommandTimeoutMs: 120_000,
            maxCommandTimeoutMs: 600_000,
            reasoningEffort: reasoningEffort,
            enableLoopDetection: true,
            loopDetectionWindow: 10,
            userInstructions: buildUserInstructions(context: context)
        )

        // 5. Create execution environment
        let env = LocalExecutionEnvironment(workingDir: workingDirectory)

        // 6. Create the session
        let session = try Session(
            profile: profile,
            environment: env,
            client: resolvedClient,
            config: sessionConfig
        )

        // 7. Track tool calls and errors via events
        let tracker = ToolCallTracker()
        let errorTracker = ErrorTracker()
        await session.eventEmitter.on { event in
            Task { await tracker.process(event) }
            Task { await errorTracker.process(event) }
        }

        // 8. Submit the prompt and wait for completion
        fputs("[CodingAgentBackend] Submitting prompt (\(enrichedPrompt.count) chars) to \(provider)/\(model)...\n", stderr)
        await session.submit(enrichedPrompt)
        fputs("[CodingAgentBackend] Submit returned.\n", stderr)

        // 9. Check response quality and request follow-ups if needed
        let initialHistory = await session.getHistory()
        let initialResponse = buildFinalResponse(from: initialHistory, tracker: tracker)

        // Follow-up: If no JSON status block, ask for summary + block (single follow-up only)
        if extractJSONBlock(from: initialResponse) == nil {
            await session.submit(
                "Summarize everything you did: files read, changes made, findings. " +
                "Then end with the JSON status block:\n\n" +
                "```json\n{\n  \"outcome\": \"success\",\n  \"preferred_next_label\": \"\",\n  " +
                "\"context_updates\": {},\n  \"notes\": \"what you accomplished\"\n}\n```"
            )
        }

        // 10. Extract the final response from session history (including all follow-ups)
        let history = await session.getHistory()
        let finalResponse = buildFinalResponse(from: history, tracker: tracker)

        // Log errors if agent produced no output
        let errors = await errorTracker.errors
        if !errors.isEmpty {
            fputs("[CodingAgentBackend] Session errors:\n", stderr)
            for err in errors {
                fputs("  - \(err)\n", stderr)
            }
        }

        await session.close()

        return parseResponse(finalResponse)
    }

    // MARK: - Response Extraction

    private func buildFinalResponse(from history: [Turn], tracker: ToolCallTracker) -> String {
        // Collect ALL non-empty assistant text from every turn
        var allAssistantTexts: [String] = []
        var totalToolCalls = 0

        for turn in history {
            if case .assistant(let t) = turn {
                totalToolCalls += t.toolCalls.count
                if !t.content.isEmpty {
                    allAssistantTexts.append(t.content)
                }
            }
        }

        var parts: [String] = []

        // Concatenate text from ALL assistant turns (not just the last one)
        // This ensures findings from intermediate turns are preserved
        if !allAssistantTexts.isEmpty {
            parts.append(allAssistantTexts.joined(separator: "\n\n---\n\n"))
        }

        // Add summary line showing tool call count
        parts.append("\n\n[Agent completed \(allAssistantTexts.count) assistant turns, \(totalToolCalls) tool calls]")

        return parts.joined()
    }

    // MARK: - Profile Factory

    private func createProfile(provider: String, model: String) -> ProviderProfile {
        // Pipeline agents run non-interactively — skip interactive tools to avoid
        // schema validation issues and reduce token overhead.
        switch provider.lowercased() {
        case "anthropic":
            return AnthropicProfile(model: model.isEmpty ? "claude-opus-4-6" : model, enableInteractiveTools: false)
        case "openai":
            return OpenAIProfile(model: model.isEmpty ? "gpt-5.2-codex" : model)
        case "gemini":
            return GeminiProfile(model: model.isEmpty ? "gemini-3-flash-preview" : model)
        default:
            return AnthropicProfile(model: model.isEmpty ? "claude-opus-4-6" : model, enableInteractiveTools: false)
        }
    }

    // MARK: - Prompt Building

    private func buildEnrichedPrompt(prompt: String, context: PipelineContext) -> String {
        var parts: [String] = []

        let goal = context.getString("_graph_goal")
        if !goal.isEmpty {
            parts.append("PIPELINE GOAL: \(goal)")
        }

        let lastStage = context.getString("last_stage")
        let lastResponse = context.getString("last_response")
        if !lastStage.isEmpty && !lastResponse.isEmpty {
            parts.append("PREVIOUS STAGE (\(lastStage)) OUTPUT:\n\(lastResponse)")
        }

        // Include tool output from previous tool nodes so LLM stages can see it
        let toolOutput = context.getString("tool.output")
        if !toolOutput.isEmpty {
            parts.append("PREVIOUS TOOL OUTPUT:\n\(toolOutput)")
        }

        parts.append("YOUR TASK:\n\(prompt)")

        parts.append("""
        CRITICAL INSTRUCTIONS - READ CAREFULLY:

        1. WRITE TEXT OUTPUT: Your text output will be passed to the next pipeline stage. \
        If you only use tools without writing text, the next stage will have NO context about what you did. \
        Always write a detailed summary of your findings, changes, and conclusions as text output.

        2. WRITE FILES: Write your findings and results to .ai/ files in the working directory \
        so downstream stages can read them even if text context is lost.

        3. JSON STATUS BLOCK (MANDATORY): When you have completed your task, you MUST output a JSON \
        status block at the very end of your final message in this EXACT format:

        ```json
        {
          "outcome": "success",
          "preferred_next_label": "",
          "context_updates": {},
          "notes": "brief summary of what you accomplished"
        }
        ```

        Valid outcome values: "success", "partial_success", "retry", "fail"
        - Use "success" only if you have fully completed the task with evidence
        - Use "partial_success" if you made progress but couldn't finish everything
        - Use "retry" if you hit a blocker that might be resolved with another attempt
        - Use "fail" if the task is fundamentally impossible

        WITHOUT this JSON block, the pipeline will treat your work as incomplete. \
        This is not optional - the JSON status block MUST appear in your response.
        """)

        return parts.joined(separator: "\n\n")
    }

    private func buildUserInstructions(context: PipelineContext) -> String {
        var instructions: [String] = []
        instructions.append("You are a coding agent executing a stage in an automated pipeline.")
        instructions.append("You have full access to the filesystem. Read files, edit code, run builds and tests.")
        instructions.append("")
        instructions.append("IMPORTANT RULES:")
        instructions.append("- You MUST write a detailed text summary of your work. Do NOT rely solely on tool calls.")
        instructions.append("- Your text output is passed to the next pipeline stage. Without it, the next stage has no context.")
        instructions.append("- Write findings and results to .ai/ files in the working directory for downstream stages.")
        instructions.append("- You MUST end your final message with a JSON status block (```json ... ```).")
        instructions.append("- The JSON block must contain: outcome, preferred_next_label, context_updates, notes.")

        let goal = context.getString("_graph_goal")
        if !goal.isEmpty {
            instructions.append("")
            instructions.append("Pipeline goal: \(goal)")
        }

        return instructions.joined(separator: "\n")
    }

    // MARK: - Response Parsing (reused from LLMKitBackend)

    private func parseResponse(_ response: String) -> CodergenResult {
        if let jsonBlock = extractJSONBlock(from: response) {
            if let data = jsonBlock.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let outcomeStr = json["outcome"] as? String ?? "success"
                let status = OutcomeStatus(rawValue: outcomeStr) ?? .success
                let preferredLabel = json["preferred_next_label"] as? String ?? ""
                let notes = json["notes"] as? String ?? ""

                var contextUpdates: [String: String] = [:]
                if let updates = json["context_updates"] as? [String: Any] {
                    for (k, v) in updates {
                        contextUpdates[k] = "\(v)"
                    }
                }

                var suggestedNextIds: [String] = []
                if let ids = json["suggested_next_ids"] as? [String] {
                    suggestedNextIds = ids
                }

                return CodergenResult(
                    response: response,
                    status: status,
                    contextUpdates: contextUpdates,
                    preferredLabel: preferredLabel,
                    suggestedNextIds: suggestedNextIds,
                    notes: notes
                )
            }
        }

        return CodergenResult(
            response: response,
            status: .partialSuccess,
            notes: "WARNING: No structured status block found in agent response; defaulting to partial_success"
        )
    }

    private func extractJSONBlock(from text: String) -> String? {
        let pattern = "```json\\s*\\n([\\s\\S]*?)\\n\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard let lastMatch = matches.last, lastMatch.numberOfRanges >= 2 else {
            return nil
        }
        return nsText.substring(with: lastMatch.range(at: 1))
    }
}

// MARK: - Tool Call Tracker

/// Tracks tool call count from session events.
private actor ToolCallTracker {
    var count: Int = 0

    func process(_ event: SessionEvent) {
        if event.kind == .toolCallEnd {
            count += 1
        }
    }
}

// MARK: - Error Tracker

/// Tracks errors from session events for debugging.
private actor ErrorTracker {
    var errors: [String] = []

    func process(_ event: SessionEvent) {
        if event.kind == .error {
            let detail = event.data["error"] ?? "unknown error"
            errors.append(detail)
            fputs("[CodingAgentBackend:ERROR] \(detail)\n", stderr)
        }
        if event.kind == .sessionEnd, let state = event.data["state"], state == "closed",
           let error = event.data["error"] {
            errors.append("Session closed with error: \(error)")
            fputs("[CodingAgentBackend:ERROR] Session closed: \(error)\n", stderr)
        }
        if event.kind == .warning {
            let msg = event.data["message"] ?? ""
            fputs("[CodingAgentBackend:WARN] \(msg)\n", stderr)
        }
    }
}
