import Foundation

// MARK: - Codergen Backend Protocol

public protocol CodergenBackend: Sendable {
    func run(
        prompt: String,
        model: String,
        provider: String,
        reasoningEffort: String,
        context: PipelineContext
    ) async throws -> CodergenResult
}

// MARK: - Codergen Result

public struct CodergenResult: Sendable {
    public var response: String
    public var status: OutcomeStatus
    public var contextUpdates: [String: String]
    public var preferredLabel: String
    public var suggestedNextIds: [String]
    public var notes: String

    public init(
        response: String,
        status: OutcomeStatus = .success,
        contextUpdates: [String: String] = [:],
        preferredLabel: String = "",
        suggestedNextIds: [String] = [],
        notes: String = ""
    ) {
        self.response = response
        self.status = status
        self.contextUpdates = contextUpdates
        self.preferredLabel = preferredLabel
        self.suggestedNextIds = suggestedNextIds
        self.notes = notes
    }
}

// MARK: - Codergen Handler

public final class CodergenHandler: NodeHandler, @unchecked Sendable {
    public let handlerType: HandlerType = .codergen
    private let llmBackend: CodergenBackend

    public init(backend: CodergenBackend) {
        self.llmBackend = backend
    }

    public func execute(
        node: Node,
        context: PipelineContext,
        graph: Graph,
        logsRoot: URL
    ) async throws -> Outcome {
        // 1. Build prompt
        let prompt = node.prompt.isEmpty ? node.label : node.prompt

        // 2. Create stage directory
        let stageDir = logsRoot.appendingPathComponent(node.id)
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

        // 3. Write prompt
        let promptFile = stageDir.appendingPathComponent("prompt.md")
        try Data(prompt.utf8).write(to: promptFile)

        // 4. Execute pre-hooks (spec §9.7: exit code 0 means proceed; non-zero skips the tool call)
        if !graph.attributes.toolHooksPre.isEmpty {
            do {
                let hookResult = try runShellHook(graph.attributes.toolHooksPre, nodeId: node.id)
                context.set("hook_pre_output", hookResult)
            } catch {
                // Pre-hook returned non-zero: skip the LLM call and return FAIL
                context.set("hook_pre_output", "FAILED: \(error)")
                return Outcome.fail(reason: "Pre-hook blocked execution for node \(node.id): \(error)")
            }
        }

        // Also check node-level tool_hooks.pre override
        if let nodePreHook = node.rawAttributes["tool_hooks.pre"]?.stringValue, !nodePreHook.isEmpty {
            do {
                let hookResult = try runShellHook(nodePreHook, nodeId: node.id)
                context.set("hook_pre_output", hookResult)
            } catch {
                context.set("hook_pre_output", "FAILED: \(error)")
                return Outcome.fail(reason: "Node pre-hook blocked execution for node \(node.id): \(error)")
            }
        }

        // 5. Call LLM backend
        let model = node.llmModel.isEmpty ? "claude-sonnet-4-5-20250929" : node.llmModel
        let provider = node.llmProvider.isEmpty ? "anthropic" : node.llmProvider
        let reasoningEffort = node.reasoningEffort.isEmpty ? "high" : node.reasoningEffort

        // Pass node-level agent config to context for CodingAgentBackend
        if let maxTurns = node.rawAttributes["max_agent_turns"]?.intValue {
            context.set("_current_node_max_agent_turns", String(maxTurns))
        }
        if let timeout = node.rawAttributes["timeout"]?.intValue {
            context.set("_current_node_timeout", String(timeout))
        }

        let result: CodergenResult
        do {
            result = try await llmBackend.run(
                prompt: prompt,
                model: model,
                provider: provider,
                reasoningEffort: reasoningEffort,
                context: context
            )
        } catch {
            throw AttractorError.llmError("LLM call failed for node \(node.id): \(error)")
        }

        // 6. Write response
        let responseFile = stageDir.appendingPathComponent("response.md")
        try Data(result.response.utf8).write(to: responseFile)

        // 7. Execute post-hooks (spec §9.7: post-hook failures are logged but do not block execution)
        if !graph.attributes.toolHooksPost.isEmpty {
            do {
                let hookResult = try runShellHook(graph.attributes.toolHooksPost, nodeId: node.id)
                context.set("hook_post_output", hookResult)
            } catch {
                // Post-hook failure is recorded but does not block execution
                context.set("hook_post_output", "FAILED: \(error)")
            }
        }

        // Also check node-level tool_hooks.post override
        if let nodePostHook = node.rawAttributes["tool_hooks.post"]?.stringValue, !nodePostHook.isEmpty {
            do {
                let hookResult = try runShellHook(nodePostHook, nodeId: node.id)
                context.set("hook_post_output", hookResult)
            } catch {
                context.set("hook_post_output", "FAILED: \(error)")
            }
        }

        // 8. Determine status
        var status = result.status
        if status == .fail && node.autoStatus {
            status = .success
        }

        // 9. Store response in context for downstream stages
        var updates = result.contextUpdates
        updates["last_response"] = String(result.response.prefix(8000))
        updates["last_stage"] = node.id

        // 10. Write status.json
        let outcome = Outcome(
            status: status,
            preferredLabel: result.preferredLabel,
            suggestedNextIds: result.suggestedNextIds,
            contextUpdates: updates,
            notes: result.notes
        )
        let statusJSON = outcome.toStatusJSON()
        let statusData = try JSONSerialization.data(withJSONObject: statusJSON, options: [.prettyPrinted, .sortedKeys])
        let statusFile = stageDir.appendingPathComponent("status.json")
        try statusData.write(to: statusFile)

        return outcome
    }

    // MARK: - Shell Hook Execution

    private func runShellHook(_ script: String, nodeId: String) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = stdout
        process.standardError = stderr

        // Set NODE_ID environment variable for the hook
        var env = ProcessInfo.processInfo.environment
        env["ATTRACTOR_NODE_ID"] = nodeId
        process.environment = env

        try process.run()
        // Read pipe data before waitUntilExit to avoid pipe buffer deadlock.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let outStr = String(data: outData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            throw AttractorError.executionFailed(
                "Tool hook failed for node \(nodeId) (exit \(process.terminationStatus)): \(errStr)"
            )
        }

        return outStr.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


