import Foundation
import OmniAILLMClient

public struct GitContext: Sendable {
    public var branch: String?
    public var modifiedFileCount: Int = 0
    public var recentCommits: String?
}

public actor Session {
    public let id: String
    public let providerProfile: ProviderProfile
    public let executionEnv: ExecutionEnvironment
    public private(set) var history: [Turn] = []
    public let eventEmitter: EventEmitter
    public var config: SessionConfig
    public private(set) var state: SessionState = .idle
    public let llmClient: LLMClient
    private var steeringQueue: [String] = []
    private var followupQueue: [String] = []
    private var subagents: [String: SubAgentHandle] = [:]
    public private(set) var abortSignaled: Bool = false
    private let depth: Int
    private var processingTask: Task<Void, Never>?

    public init(
        profile: ProviderProfile,
        environment: ExecutionEnvironment,
        client: LLMClient? = nil,
        config: SessionConfig = SessionConfig(),
        depth: Int = 0
    ) {
        self.id = UUID().uuidString
        self.providerProfile = profile
        self.executionEnv = environment
        self.config = config
        self.eventEmitter = EventEmitter()
        self.depth = depth

        if let client = client {
            self.llmClient = client
        } else {
            self.llmClient = LLMClient.fromEnv()
        }
    }

    // MARK: - Public API

    public func submit(_ input: String) async {
        let task = Task {
            await self.processInput(input)
        }
        processingTask = task
        await task.value
        processingTask = nil
    }

    public func updateConfig(_ mutator: (inout SessionConfig) -> Void) {
        mutator(&config)
    }

    public func steer(_ message: String) {
        steeringQueue.append(message)
    }

    public func followUp(_ message: String) {
        followupQueue.append(message)
    }

    public func abort() {
        abortSignaled = true
        state = .closed
        processingTask?.cancel()
    }

    public func close() async {
        abortSignaled = true
        state = .closed
        processingTask?.cancel()
        for (_, handle) in subagents {
            await handle.session.abort()
        }
        await eventEmitter.emit(SessionEvent(kind: .sessionEnd, sessionId: id, data: ["state": "closed"]))
        await eventEmitter.flush()
    }

    public func getState() -> SessionState {
        state
    }

    public func getHistory() -> [Turn] {
        history
    }

    // MARK: - Core Agentic Loop

    private func processInput(_ userInput: String) async {
        // Emit SESSION_START on first input
        if history.isEmpty {
            await eventEmitter.emit(SessionEvent(kind: .sessionStart, sessionId: id))
        }
        state = .processing
        history.append(.user(UserTurn(content: userInput)))
        await eventEmitter.emit(SessionEvent(kind: .userInput, sessionId: id, data: ["content": userInput]))

        drainSteering()

        var roundCount = 0

        while true {
            // 1. Check limits
            if config.maxToolRoundsPerInput > 0 && roundCount >= config.maxToolRoundsPerInput {
                await eventEmitter.emit(SessionEvent(kind: .turnLimit, sessionId: id, data: ["round": "\(roundCount)"]))
                break
            }

            if config.maxTurns > 0 && countTurns() >= config.maxTurns {
                await eventEmitter.emit(SessionEvent(kind: .turnLimit, sessionId: id, data: ["total_turns": "\(countTurns())"]))
                break
            }

            if abortSignaled {
                break
            }

            // 2. Build LLM request
            let projectDocs = await discoverProjectDocs(workingDir: executionEnv.workingDirectory())
            let gitCtx = await gatherGitContext()
            let systemPrompt = providerProfile.buildSystemPrompt(
                environment: executionEnv,
                projectDocs: projectDocs,
                userInstructions: config.userInstructions,
                gitContext: gitCtx
            )
            let messages = convertHistoryToMessages(systemPrompt: systemPrompt)
            let toolDefs = providerProfile.tools()

            let request = Request(
                model: providerProfile.model,
                messages: messages,
                provider: providerProfile.id,
                tools: toolDefs.isEmpty ? nil : toolDefs,
                toolChoice: toolDefs.isEmpty ? nil : ToolChoice.auto,
                reasoningEffort: config.reasoningEffort,
                providerOptions: providerProfile.providerOptions()
            )

            // 3. Call LLM
            let response: Response
            do {
                response = try await llmClient.complete(request: request)
            } catch {
                await eventEmitter.emit(SessionEvent(kind: .error, sessionId: id, data: ["error": "\(error)"]))
                if error is AuthenticationError || error is ContextLengthError {
                    state = .closed
                    await eventEmitter.emit(SessionEvent(kind: .sessionEnd, sessionId: id, data: ["state": "closed", "error": "\(error)"]))
                    return
                }
                break
            }

            // 4. Record assistant turn
            let assistantTurn = AssistantTurn(
                content: response.text,
                toolCalls: response.toolCalls,
                reasoning: response.reasoning,
                usage: response.usage,
                responseId: response.id
            )
            history.append(.assistant(assistantTurn))
            await eventEmitter.emit(SessionEvent(
                kind: .assistantTextEnd,
                sessionId: id,
                data: [
                    "text": response.text,
                    "reasoning": response.reasoning ?? "",
                    "tool_call_count": "\(response.toolCalls.count)",
                ]
            ))

            // 5. If no tool calls, natural completion
            if response.toolCalls.isEmpty {
                break
            }

            // 6. Execute tool calls
            roundCount += 1
            let results = await executeToolCalls(response.toolCalls)
            history.append(.toolResults(ToolResultsTurn(results: results)))

            // 7. Drain steering
            drainSteering()

            // 8. Loop detection
            if config.enableLoopDetection {
                if detectLoop(window: config.loopDetectionWindow) {
                    let warning = "Loop detected: the last \(config.loopDetectionWindow) tool calls follow a repeating pattern. Try a different approach."
                    history.append(.steering(SteeringTurn(content: warning)))
                    await eventEmitter.emit(SessionEvent(kind: .loopDetection, sessionId: id, data: ["message": warning]))
                }
            }

            // Context window awareness
            checkContextUsage()
        }

        // Process follow-up messages
        if !followupQueue.isEmpty {
            let nextInput = followupQueue.removeFirst()
            await processInput(nextInput)
            return
        }

        state = .idle
        await eventEmitter.emit(SessionEvent(kind: .sessionEnd, sessionId: id))
    }

    // MARK: - Steering

    private func drainSteering() {
        while !steeringQueue.isEmpty {
            let msg = steeringQueue.removeFirst()
            history.append(.steering(SteeringTurn(content: msg)))
            Task {
                await eventEmitter.emit(SessionEvent(kind: .steeringInjected, sessionId: id, data: ["content": msg]))
            }
        }
    }

    // MARK: - Tool Execution

    private func executeToolCalls(_ toolCalls: [ToolCall]) async -> [ToolResult] {
        if providerProfile.supportsParallelToolCalls && toolCalls.count > 1 {
            return await withTaskGroup(of: ToolResult.self) { group in
                for tc in toolCalls {
                    group.addTask {
                        await self.executeSingleTool(tc)
                    }
                }
                var results: [ToolResult] = []
                for await result in group {
                    results.append(result)
                }
                // Maintain order matching tool calls
                return results.sorted { a, b in
                    let aIdx = toolCalls.firstIndex(where: { $0.id == a.toolCallId }) ?? 0
                    let bIdx = toolCalls.firstIndex(where: { $0.id == b.toolCallId }) ?? 0
                    return aIdx < bIdx
                }
            }
        } else {
            var results: [ToolResult] = []
            for tc in toolCalls {
                let result = await executeSingleTool(tc)
                results.append(result)
            }
            return results
        }
    }

    private func executeSingleTool(_ toolCall: ToolCall) async -> ToolResult {
        await eventEmitter.emit(SessionEvent(
            kind: .toolCallStart,
            sessionId: id,
            data: ["tool_name": toolCall.name, "call_id": toolCall.id]
        ))

        guard let registered = providerProfile.toolRegistry.get(toolCall.name) else {
            let errorMsg = "Unknown tool: \(toolCall.name)"
            await eventEmitter.emit(SessionEvent(
                kind: .toolCallEnd,
                sessionId: id,
                data: ["call_id": toolCall.id, "error": errorMsg]
            ))
            return ToolResult(toolCallId: toolCall.id, content: errorMsg, isError: true)
        }

        // Validate arguments against tool parameter schema
        if let validationError = validateToolArguments(toolCall.arguments, against: registered.definition.parameters) {
            await eventEmitter.emit(SessionEvent(
                kind: .toolCallEnd,
                sessionId: id,
                data: ["call_id": toolCall.id, "error": validationError]
            ))
            return ToolResult(toolCallId: toolCall.id, content: validationError, isError: true)
        }

        do {
            let rawOutput = try await registered.executor(toolCall.arguments, executionEnv)
            let truncatedOutput = truncateToolOutput(rawOutput, toolName: toolCall.name, config: config)

            await eventEmitter.emit(SessionEvent(
                kind: .toolCallEnd,
                sessionId: id,
                data: ["call_id": toolCall.id, "output": rawOutput, "truncated": "\(rawOutput.count != truncatedOutput.count)"]
            ))

            return ToolResult(toolCallId: toolCall.id, content: truncatedOutput, isError: false)
        } catch {
            let errorMsg = "Tool error (\(toolCall.name)): \(error)"
            await eventEmitter.emit(SessionEvent(
                kind: .toolCallEnd,
                sessionId: id,
                data: ["call_id": toolCall.id, "error": errorMsg]
            ))
            return ToolResult(toolCallId: toolCall.id, content: errorMsg, isError: true)
        }
    }

    // MARK: - History Conversion

    private func convertHistoryToMessages(systemPrompt: String) -> [Message] {
        var messages: [Message] = [.system(systemPrompt)]

        for turn in history {
            switch turn {
            case .user(let t):
                messages.append(.user(t.content))
            case .assistant(let t):
                var parts: [ContentPart] = []
                if !t.content.isEmpty {
                    parts.append(.text(t.content))
                }
                for tc in t.toolCalls {
                    parts.append(.toolCall(ToolCallData(
                        id: tc.id,
                        name: tc.name,
                        arguments: AnyCodable(tc.arguments)
                    )))
                }
                if parts.isEmpty {
                    parts.append(.text(""))
                }
                messages.append(Message(role: .assistant, content: parts))
            case .toolResults(let t):
                for result in t.results {
                    messages.append(.toolResult(
                        toolCallId: result.toolCallId,
                        content: result.contentString,
                        isError: result.isError
                    ))
                }
            case .system(let t):
                messages.append(.user("[System] \(t.content)"))
            case .steering(let t):
                messages.append(.user(t.content))
            }
        }

        return messages
    }

    // MARK: - Loop Detection

    private func detectLoop(window: Int) -> Bool {
        let recentSignatures = extractToolCallSignatures(last: window)
        guard recentSignatures.count >= window else { return false }

        for patternLen in [1, 2, 3] {
            guard window % patternLen == 0 else { continue }
            let pattern = Array(recentSignatures[0..<patternLen])
            var allMatch = true
            for i in stride(from: patternLen, to: window, by: patternLen) {
                let chunk = Array(recentSignatures[i..<min(i + patternLen, recentSignatures.count)])
                if chunk != pattern {
                    allMatch = false
                    break
                }
            }
            if allMatch { return true }
        }
        return false
    }

    private func extractToolCallSignatures(last count: Int) -> [String] {
        var signatures: [String] = []
        for turn in history.reversed() {
            if case .assistant(let t) = turn {
                for tc in t.toolCalls.reversed() {
                    let argsHash = stableHash(tc.arguments)
                    signatures.insert("\(tc.name):\(argsHash)", at: 0)
                    if signatures.count >= count { return signatures }
                }
            }
        }
        return signatures
    }

    private func stableHash(_ dict: [String: Any]) -> String {
        let sorted = dict.sorted(by: { $0.key < $1.key })
        let desc = sorted.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        var hasher = Hasher()
        hasher.combine(desc)
        return "\(hasher.finalize())"
    }

    // MARK: - Tool Argument Validation

    private func validateToolArguments(_ args: [String: Any], against schema: [String: Any]) -> String? {
        // Check required fields
        if let required = schema["required"] as? [String] {
            for field in required {
                if args[field] == nil {
                    return "Missing required field: \(field)"
                }
            }
        }

        // Check type constraints for properties
        if let properties = schema["properties"] as? [String: Any] {
            for (key, value) in args {
                if let propSchema = properties[key] as? [String: Any],
                   let expectedType = propSchema["type"] as? String {
                    switch expectedType {
                    case "string":
                        if !(value is String) { return "Field '\(key)' must be string" }
                    case "integer":
                        if !(value is Int) && !(value is Int64) && !(value is Int32) {
                            // JSON numbers may come as Double; accept whole numbers
                            if let d = value as? Double, d == d.rounded() {
                                // acceptable integer value
                            } else {
                                return "Field '\(key)' must be integer"
                            }
                        }
                    case "number":
                        if !(value is Int) && !(value is Int64) && !(value is Double) && !(value is Float) {
                            return "Field '\(key)' must be number"
                        }
                    case "boolean":
                        if !(value is Bool) { return "Field '\(key)' must be boolean" }
                    case "array":
                        if !(value is [Any]) { return "Field '\(key)' must be array" }
                    case "object":
                        if !(value is [String: Any]) { return "Field '\(key)' must be object" }
                    default:
                        break
                    }
                }
            }
        }

        return nil // valid
    }

    // MARK: - Context Window Awareness

    private func checkContextUsage() {
        let approxTokens = totalCharsInHistory() / 4
        let threshold = providerProfile.contextWindowSize * 80 / 100
        if approxTokens > threshold {
            let pct = approxTokens * 100 / providerProfile.contextWindowSize
            Task {
                await eventEmitter.emit(SessionEvent(
                    kind: .warning,
                    sessionId: id,
                    data: ["message": "Context usage at ~\(pct)% of context window"]
                ))
            }
        }
    }

    private func totalCharsInHistory() -> Int {
        var total = 0
        for turn in history {
            switch turn {
            case .user(let t): total += t.content.count
            case .assistant(let t): total += t.content.count + (t.reasoning?.count ?? 0)
            case .toolResults(let t): total += t.results.reduce(0) { $0 + $1.contentString.count }
            case .system(let t): total += t.content.count
            case .steering(let t): total += t.content.count
            }
        }
        return total
    }

    private func countTurns() -> Int {
        history.count
    }

    // MARK: - Project Doc Discovery

    private func discoverProjectDocs(workingDir: String) async -> String? {
        let providerFiles: [String]
        switch providerProfile.id {
        case "openai":
            providerFiles = ["AGENTS.md", ".codex/instructions.md"]
        case "anthropic":
            providerFiles = ["AGENTS.md", "CLAUDE.md"]
        case "gemini":
            providerFiles = ["AGENTS.md", "GEMINI.md"]
        default:
            providerFiles = ["AGENTS.md"]
        }

        var docs: [String] = []
        var totalBytes = 0
        let budget = 32 * 1024

        // Try git root first
        let gitRoot = await findGitRoot(workingDir: workingDir)
        let searchDirs = gitRoot != nil && gitRoot != workingDir
            ? [gitRoot!, workingDir]
            : [workingDir]

        for dir in searchDirs {
            for fileName in providerFiles {
                let path = (dir as NSString).appendingPathComponent(fileName)
                if await executionEnv.fileExists(path: path) {
                    do {
                        let content = try await executionEnv.readFile(path: path, offset: nil, limit: nil)
                        if totalBytes + content.count <= budget {
                            docs.append("# \(fileName)\n\(content)")
                            totalBytes += content.count
                        } else {
                            let remaining = budget - totalBytes
                            if remaining > 0 {
                                docs.append("# \(fileName)\n\(String(content.prefix(remaining)))\n[Project instructions truncated at 32KB]")
                            }
                            return docs.joined(separator: "\n\n")
                        }
                    } catch {
                        continue
                    }
                }
            }
        }

        return docs.isEmpty ? nil : docs.joined(separator: "\n\n")
    }

    private func findGitRoot(workingDir: String) async -> String? {
        do {
            let result = try await executionEnv.execCommand(
                command: "git rev-parse --show-toplevel",
                timeoutMs: 5000,
                workingDir: workingDir,
                envVars: nil
            )
            if result.exitCode == 0 {
                return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {}
        return nil
    }

    // MARK: - Git Context

    public func gatherGitContext() async -> GitContext? {
        let workingDir = executionEnv.workingDirectory()

        // Check if we're in a git repo
        guard let _ = await findGitRoot(workingDir: workingDir) else {
            return nil
        }

        var context = GitContext()

        // Branch name
        if let result = try? await executionEnv.execCommand(
            command: "git rev-parse --abbrev-ref HEAD",
            timeoutMs: 5000, workingDir: workingDir, envVars: nil
        ), result.exitCode == 0 {
            context.branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Modified file count
        if let result = try? await executionEnv.execCommand(
            command: "git status --porcelain | wc -l",
            timeoutMs: 5000, workingDir: workingDir, envVars: nil
        ), result.exitCode == 0 {
            context.modifiedFileCount = Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }

        // Recent commits
        if let result = try? await executionEnv.execCommand(
            command: "git log --oneline -5",
            timeoutMs: 5000, workingDir: workingDir, envVars: nil
        ), result.exitCode == 0 {
            context.recentCommits = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return context
    }

    // MARK: - Subagents

    public func registerSubagent(_ handle: SubAgentHandle) {
        subagents[handle.id] = handle
    }

    public func getSubagent(_ agentId: String) -> SubAgentHandle? {
        subagents[agentId]
    }

    public func removeSubagent(_ agentId: String) {
        subagents.removeValue(forKey: agentId)
    }

    public func currentDepth() -> Int {
        depth
    }
}
