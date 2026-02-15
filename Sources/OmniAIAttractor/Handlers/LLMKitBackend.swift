import Foundation
import OmniAICore

// MARK: - LLMKit Backend

public final class LLMKitBackend: CodergenBackend, @unchecked Sendable {
    private let client: Client?

    public init(client: Client? = nil) {
        self.client = client
    }

    public func run(
        prompt: String,
        model: String,
        provider: String,
        reasoningEffort: String,
        context: PipelineContext
    ) async throws -> CodergenResult {
        let resolvedClient = try (client ?? Client.fromEnv())
        let goal = context.getString("_graph_goal")
        let systemPrompt = buildSystemPrompt(goal: goal, context: context)
        let timeout = resolveTimeout(from: context)

        let result = try await generate(
            model: model,
            prompt: prompt,
            system: systemPrompt,
            reasoningEffort: reasoningEffort,
            provider: provider,
            timeout: timeout,
            client: resolvedClient
        )

        let response = result.text
        return try parseResponse(response)
    }

    private func buildSystemPrompt(goal: String, context: PipelineContext) -> String {
        var parts: [String] = []
        parts.append("You are a stage in an AI pipeline.")

        if !goal.isEmpty {
            parts.append("The pipeline goal is: \(goal)")
        }

        let lastStage = context.getString("last_stage")
        let lastResponse = context.getString("last_response")
        if !lastStage.isEmpty && !lastResponse.isEmpty {
            parts.append("The previous stage (\(lastStage)) produced this output:\n\n\(lastResponse)")
        }

        parts.append("""
        After completing your task, include a JSON status block at the end of your response \
        in the following format:

        ```json
        {
          "outcome": "success",
          "preferred_next_label": "",
          "context_updates": {},
          "notes": ""
        }
        ```

        Valid outcome values: "success", "partial_success", "retry", "fail"
        - preferred_next_label: label of the preferred next edge/node (optional)
        - context_updates: key-value pairs to pass to subsequent stages (optional)
        - notes: any notes about the result (optional)
        """)

        return parts.joined(separator: "\n\n")
    }

    private func resolveTimeout(from context: PipelineContext) -> Timeout {
        if let nodeTimeoutSeconds = Double(context.getString("_current_node_timeout")),
           nodeTimeoutSeconds > 0
        {
            return .seconds(nodeTimeoutSeconds)
        }

        // URLSession's default request timeout can be too short for reasoning-heavy LLM calls.
        // Use a conservative default for attractor codergen stages unless overridden per-node.
        return .seconds(300)
    }

    private func parseResponse(_ response: String) throws -> CodergenResult {
        // Try to find a JSON block in the response
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

        // No JSON block found - default to partialSuccess (safest; we cannot
        // confirm the goal was met without structured output)
        return CodergenResult(
            response: response,
            status: .partialSuccess,
            notes: "WARNING: No structured status block found in LLM response; defaulting to partial_success"
        )
    }

    private func extractJSONBlock(from text: String) -> String? {
        // Look for ```json ... ``` blocks from the end of the response
        let pattern = "```json\\s*\\n([\\s\\S]*?)\\n\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        // Use the last match (the status block is expected at the end)
        guard let lastMatch = matches.last, lastMatch.numberOfRanges >= 2 else {
            return nil
        }
        return nsText.substring(with: lastMatch.range(at: 1))
    }
}

