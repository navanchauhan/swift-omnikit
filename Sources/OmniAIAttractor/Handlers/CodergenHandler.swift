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
    /// The raw outcome string from the JSON block (e.g. "needs_dod").
    /// Preserved for edge-condition evaluation when custom outcomes are used.
    public var rawOutcome: String?
    public var contextUpdates: [String: String]
    public var preferredLabel: String
    public var suggestedNextIds: [String]
    public var notes: String

    public init(
        response: String,
        status: OutcomeStatus = .success,
        rawOutcome: String? = nil,
        contextUpdates: [String: String] = [:],
        preferredLabel: String = "",
        suggestedNextIds: [String] = [],
        notes: String = ""
    ) {
        self.response = response
        self.status = status
        self.rawOutcome = rawOutcome
        self.contextUpdates = contextUpdates
        self.preferredLabel = preferredLabel
        self.suggestedNextIds = suggestedNextIds
        self.notes = notes
    }
}

// MARK: - Codergen Handler

public final class CodergenHandler: NodeHandler, Sendable {
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
        var prompt = node.prompt.isEmpty ? node.label : node.prompt
        let activeSkillIDs = context.getString("task.active_skill_ids")
        let skillPromptOverlay = context.getString("task.skill_prompt_overlay")
        let skillCodergenOverlay = context.getString("task.skill_codergen_overlay")
        let modelRouteTier = context.getString("task.model_route_tier")
        let modelRouteModel = context.getString("task.model_route_model")
        let modelRouteProvider = context.getString("task.model_route_provider")
        if !activeSkillIDs.isEmpty ||
            !skillPromptOverlay.isEmpty ||
            !skillCodergenOverlay.isEmpty ||
            !modelRouteTier.isEmpty {
            var sections: [String] = []
            if !activeSkillIDs.isEmpty {
                sections.append("Active skills: \(activeSkillIDs)")
            }
            if !skillPromptOverlay.isEmpty {
                sections.append("Skill overlay:\n\(skillPromptOverlay)")
            }
            if !skillCodergenOverlay.isEmpty {
                sections.append("Codergen skill guidance:\n\(skillCodergenOverlay)")
            }
            if !modelRouteTier.isEmpty {
                var routeSection = "Model route tier: \(modelRouteTier)"
                if !modelRouteProvider.isEmpty || !modelRouteModel.isEmpty {
                    routeSection += "\nPreferred route: \(modelRouteProvider)/\(modelRouteModel)"
                }
                sections.append(routeSection)
            }
            sections.append(prompt)
            prompt = sections.joined(separator: "\n\n")
        }

        // 2. Create stage directory
        let stageDir = logsRoot.appendingPathComponent(node.id)
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
        context.set("_current_node_id", node.id)
        context.set("_current_stage_dir", stageDir.path)

        // 3. Write prompt
        let promptFile = stageDir.appendingPathComponent("prompt.md")
        try Data(prompt.utf8).write(to: promptFile)

        // 4. Execute pre-hooks (spec §9.7: exit code 0 means proceed; non-zero skips the tool call)
        if !graph.attributes.toolHooksPre.isEmpty {
            do {
                let hookResult = try await runShellHook(graph.attributes.toolHooksPre, nodeId: node.id)
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
                let hookResult = try await runShellHook(nodePreHook, nodeId: node.id)
                context.set("hook_pre_output", hookResult)
            } catch {
                context.set("hook_pre_output", "FAILED: \(error)")
                return Outcome.fail(reason: "Node pre-hook blocked execution for node \(node.id): \(error)")
            }
        }

        // 5. Call LLM backend
        let model = node.llmModel.isEmpty
            ? (context.getString("task.model_route_model").isEmpty ? "claude-sonnet-4-5-20250929" : context.getString("task.model_route_model"))
            : node.llmModel
        let provider = node.llmProvider.isEmpty
            ? (context.getString("task.model_route_provider").isEmpty ? "anthropic" : context.getString("task.model_route_provider"))
            : node.llmProvider
        let reasoningEffort = node.reasoningEffort.isEmpty
            ? (context.getString("task.model_route_reasoning_effort").isEmpty ? "high" : context.getString("task.model_route_reasoning_effort"))
            : node.reasoningEffort

        // Pass node-level agent config to context for CodingAgentBackend.
        if let maxTurns = node.rawAttributes["max_agent_turns"]?.intValue {
            context.set("_current_node_max_agent_turns", String(maxTurns))
        }
        if let defaultTimeout = node.rawAttributes["default_command_timeout_ms"]?.intValue {
            context.set("_current_node_default_command_timeout_ms", String(defaultTimeout))
        }
        if let maxCommandTimeout = node.rawAttributes["max_command_timeout_ms"]?.intValue {
            context.set("_current_node_max_command_timeout_ms", String(maxCommandTimeout))
        }
        if let inactivityTimeout = node.rawAttributes["llm_inactivity_timeout_seconds"] {
            context.set("_current_node_llm_inactivity_timeout_seconds", inactivityTimeout.stringValue)
        }
        if let loopWindow = node.rawAttributes["loop_detection_window"]?.intValue {
            context.set("_current_node_loop_detection_window", String(loopWindow))
        }
        if let userInstructions = node.rawAttributes["user_instructions"]?.stringValue, !userInstructions.isEmpty {
            context.set("_current_node_user_instructions", userInstructions)
        }
        if let requireStatusBlock = node.rawAttributes["require_status_block"]?.boolValue {
            context.set("_current_node_require_status_block", requireStatusBlock ? "true" : "false")
        }
        if let parallelToolCalls = node.rawAttributes["parallel_tool_calls"]?.boolValue {
            context.set("_current_node_parallel_tool_calls", parallelToolCalls ? "true" : "false")
        }
        if let excludedTools = node.rawAttributes["excluded_tools"]?.stringValue, !excludedTools.isEmpty {
            context.set("_current_node_excluded_tools", excludedTools)
        }
        if let artifactPath = node.rawAttributes["artifact_path"]?.stringValue, !artifactPath.isEmpty {
            context.set("_current_node_artifact_path", artifactPath)
        }
        if let acpAgentPath = (node.rawAttributes["acp_agent_path"]?.stringValue).flatMap({ $0.isEmpty ? nil : $0 })
            ?? (graph.rawAttributes["acp_agent_path"]?.stringValue).flatMap({ $0.isEmpty ? nil : $0 })
        {
            context.set("_current_node_acp_agent_path", acpAgentPath)
        }
        if let acpAgentArgs = (node.rawAttributes["acp_agent_args"]?.stringValue).flatMap({ $0.isEmpty ? nil : $0 })
            ?? (graph.rawAttributes["acp_agent_args"]?.stringValue).flatMap({ $0.isEmpty ? nil : $0 })
        {
            context.set("_current_node_acp_agent_args", acpAgentArgs)
        }
        if let acpWorkingDirectory = (node.rawAttributes["acp_cwd"]?.stringValue).flatMap({ $0.isEmpty ? nil : $0 })
            ?? (graph.rawAttributes["acp_cwd"]?.stringValue).flatMap({ $0.isEmpty ? nil : $0 })
        {
            context.set("_current_node_acp_cwd", acpWorkingDirectory)
        }
        if let acpTimeout = node.rawAttributes["acp_timeout_seconds"]?.stringValue
            ?? graph.rawAttributes["acp_timeout_seconds"]?.stringValue
        {
            context.set("_current_node_acp_timeout_seconds", acpTimeout)
        }
        if let acpMode = (node.rawAttributes["acp_mode"]?.stringValue).flatMap({ $0.isEmpty ? nil : $0 })
            ?? (graph.rawAttributes["acp_mode"]?.stringValue).flatMap({ $0.isEmpty ? nil : $0 })
        {
            context.set("_current_node_acp_mode", acpMode)
        }
        let resumeKey = buildNodeResumeKey(graphID: graph.id, nodeID: node.id, provider: provider, model: model, prompt: prompt)
        context.set("_current_node_resume_key", resumeKey)

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

        // Host-owned artifact persistence for deterministic downstream handoff.
        if let artifactPath = node.rawAttributes["artifact_path"]?.stringValue, !artifactPath.isEmpty {
            let artifactURL: URL
            if artifactPath.hasPrefix("/") {
                artifactURL = URL(fileURLWithPath: artifactPath)
            } else {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                artifactURL = cwd.appendingPathComponent(artifactPath)
            }
            try FileManager.default.createDirectory(
                at: artifactURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(result.response.utf8).write(to: artifactURL)
            context.set("artifact.\(node.id).path", artifactURL.path)
        }

        // 7. Execute post-hooks (spec §9.7: post-hook failures are logged but do not block execution)
        if !graph.attributes.toolHooksPost.isEmpty {
            do {
                let hookResult = try await runShellHook(graph.attributes.toolHooksPost, nodeId: node.id)
                context.set("hook_post_output", hookResult)
            } catch {
                // Post-hook failure is recorded but does not block execution
                context.set("hook_post_output", "FAILED: \(error)")
            }
        }

        // Also check node-level tool_hooks.post override
        if let nodePostHook = node.rawAttributes["tool_hooks.post"]?.stringValue, !nodePostHook.isEmpty {
            do {
                let hookResult = try await runShellHook(nodePostHook, nodeId: node.id)
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

        var combinedNotes = result.notes
        var contractCheckOutput = ""
        if status == .success || status == .partialSuccess {
            let contractValidation = try await validateSuccessCriteriaIfNeeded(
                node: node,
                stageDir: stageDir
            )
            contractCheckOutput = contractValidation.output
            if !contractValidation.note.isEmpty {
                if combinedNotes.isEmpty {
                    combinedNotes = contractValidation.note
                } else {
                    combinedNotes += " | " + contractValidation.note
                }
            }
            if let overrideStatus = contractValidation.overrideStatus {
                status = overrideStatus
            }
        }

        // 9. Store response in context for downstream stages
        var updates = result.contextUpdates
        updates["last_response"] = String(result.response.prefix(8000))
        updates["last_stage"] = node.id
        if !contractCheckOutput.isEmpty {
            updates["contract_check_output"] = String(contractCheckOutput.prefix(4000))
        }

        // 10. Write status.json
        let outcome = Outcome(
            status: status,
            rawOutcome: result.rawOutcome,
            preferredLabel: result.preferredLabel,
            suggestedNextIds: result.suggestedNextIds,
            contextUpdates: updates,
            notes: combinedNotes,
            failureReason: status == .fail && combinedNotes.isEmpty ? "success criteria validation failed" : ""
        )
        let statusJSON = outcome.toStatusJSON()
        let statusData = try JSONSerialization.data(withJSONObject: statusJSON, options: [.prettyPrinted, .sortedKeys])
        let statusFile = stageDir.appendingPathComponent("status.json")
        try statusData.write(to: statusFile)

        return outcome
    }

    private func buildNodeResumeKey(
        graphID: String,
        nodeID: String,
        provider: String,
        model: String,
        prompt: String
    ) -> String {
        let raw = "\(graphID)|\(nodeID)|\(provider)|\(model)|\(prompt)"
        let hash = fnv1a64(raw)
        return "\(graphID).\(nodeID).\(provider).\(model).\(hash)"
    }

    private func fnv1a64(_ value: String) -> String {
        let offsetBasis: UInt64 = 14695981039346656037
        let prime: UInt64 = 1099511628211
        var hash = offsetBasis
        for b in value.utf8 {
            hash ^= UInt64(b)
            hash = hash &* prime
        }
        return String(hash, radix: 16)
    }

    private struct SuccessCriteriaValidationResult {
        let overrideStatus: OutcomeStatus?
        let note: String
        let output: String
    }

    private func validateSuccessCriteriaIfNeeded(
        node: Node,
        stageDir: URL
    ) async throws -> SuccessCriteriaValidationResult {
        let command = node.rawAttributes["success_criteria_command"]?.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.isEmpty
        else {
            return SuccessCriteriaValidationResult(overrideStatus: nil, note: "", output: "")
        }

        let validation = try await runCommandWithExitStatus(command, nodeId: node.id, stageDir: stageDir)
        let contractOutput = [validation.stdout, validation.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: validation.stdout.isEmpty || validation.stderr.isEmpty ? "" : "\n\n")

        let contractFile = stageDir.appendingPathComponent("contract-check.txt")
        let persistedOutput = contractOutput.isEmpty
            ? "exit_status=\(validation.exitStatus)\n"
            : "exit_status=\(validation.exitStatus)\n\(contractOutput)\n"
        try Data(persistedOutput.utf8).write(to: contractFile)

        guard validation.exitStatus != 0 else {
            let note = "Success criteria passed."
            return SuccessCriteriaValidationResult(
                overrideStatus: nil,
                note: note,
                output: persistedOutput
            )
        }

        let requestedFailureOutcome = node.rawAttributes["success_criteria_failure_outcome"]?.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let overrideStatus = OutcomeStatus(rawValue: requestedFailureOutcome) ?? .retry
        let summary = "Success criteria failed (exit \(validation.exitStatus))."
        let detail = contractOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = detail.isEmpty ? summary : "\(summary) \(detail)"
        return SuccessCriteriaValidationResult(
            overrideStatus: overrideStatus,
            note: note,
            output: persistedOutput
        )
    }

    // MARK: - Shell Hook Execution

    // Note: Blocks a cooperative thread while waiting for the hook process.
    // Stdout and stderr are drained concurrently to avoid pipe deadlocks.
    private func runShellHook(_ script: String, nodeId: String) async throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutData = _ShellHookDataBox()
        let stderrData = _ShellHookDataBox()

        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = stdout
        process.standardError = stderr

        var env = ProcessInfo.processInfo.environment
        env["ATTRACTOR_NODE_ID"] = nodeId
        process.environment = env

        let stdoutQueue = DispatchQueue(label: "attractor.hook.stdout")
        let stderrQueue = DispatchQueue(label: "attractor.hook.stderr")
        stdoutQueue.async {
            stdoutData.store(stdout.fileHandleForReading.readDataToEndOfFile())
        }
        stderrQueue.async {
            stderrData.store(stderr.fileHandleForReading.readDataToEndOfFile())
        }

        do {
            try process.run()
        } catch {
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            stdoutQueue.sync {}
            stderrQueue.sync {}
            throw error
        }
        await _waitForProcessExit(process)
        stdoutQueue.sync {}
        stderrQueue.sync {}

        let outStr = String(data: stdoutData.load(), encoding: .utf8) ?? ""
        let errStr = String(data: stderrData.load(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw AttractorError.executionFailed(
                "Tool hook failed for node \(nodeId) (exit \(process.terminationStatus)): \(errStr)"
            )
        }

        return outStr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private struct CommandWithExitStatusResult {
        let exitStatus: Int32
        let stdout: String
        let stderr: String
    }

    private func runCommandWithExitStatus(
        _ script: String,
        nodeId: String,
        stageDir: URL
    ) async throws -> CommandWithExitStatusResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutData = _ShellHookDataBox()
        let stderrData = _ShellHookDataBox()

        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = stdout
        process.standardError = stderr

        var env = ProcessInfo.processInfo.environment
        env["ATTRACTOR_NODE_ID"] = nodeId
        env["ATTRACTOR_STAGE_DIR"] = stageDir.path
        process.environment = env

        let stdoutQueue = DispatchQueue(label: "attractor.command.stdout")
        let stderrQueue = DispatchQueue(label: "attractor.command.stderr")
        stdoutQueue.async {
            stdoutData.store(stdout.fileHandleForReading.readDataToEndOfFile())
        }
        stderrQueue.async {
            stderrData.store(stderr.fileHandleForReading.readDataToEndOfFile())
        }

        do {
            try process.run()
        } catch {
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            stdoutQueue.sync {}
            stderrQueue.sync {}
            throw error
        }
        await _waitForProcessExit(process)
        stdoutQueue.sync {}
        stderrQueue.sync {}

        return CommandWithExitStatusResult(
            exitStatus: process.terminationStatus,
            stdout: String(data: stdoutData.load(), encoding: .utf8) ?? "",
            stderr: String(data: stderrData.load(), encoding: .utf8) ?? ""
        )
    }
}

private func _waitForProcessExit(_ process: Process) async {
    guard process.isRunning else { return }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let resumeBox = _CodergenProcessExitBox(continuation)

        process.terminationHandler = { _ in
            resumeBox.resumeOnce()
        }

        if !process.isRunning {
            resumeBox.resumeOnce()
        }
    }
    process.terminationHandler = nil
}

private final class _CodergenProcessExitBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<Void, Never>

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resumeOnce() {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume()
    }
}

private final class _ShellHookDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ data: Data) {
        lock.lock()
        self.data = data
        lock.unlock()
    }

    func load() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
