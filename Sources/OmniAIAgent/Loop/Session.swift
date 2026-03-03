import Foundation
import OmniAICore

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
    public let llmClient: Client
    private var steeringQueue: [String] = []
    private var followupQueue: [String] = []
    private var subagents: [String: SubAgentHandle] = [:]
    public private(set) var abortSignaled: Bool = false
    private let depth: Int
    private var processingTask: Task<Void, Never>?
    private let storageBackend: (any SessionStorageBackend)?
    private let autoRestoreFromStorage: Bool
    private var didAttemptStorageRestore = false

    public init(
        profile: ProviderProfile,
        environment: ExecutionEnvironment,
        client: Client? = nil,
        config: SessionConfig = SessionConfig(),
        depth: Int = 0,
        sessionID: String = UUID().uuidString,
        storageBackend: (any SessionStorageBackend)? = nil,
        autoRestoreFromStorage: Bool = true
    ) throws {
        self.id = sessionID
        self.providerProfile = profile
        self.executionEnv = environment
        self.config = config
        self.eventEmitter = EventEmitter()
        self.depth = depth
        self.storageBackend = storageBackend
        self.autoRestoreFromStorage = autoRestoreFromStorage

        if let client = client {
            self.llmClient = client
        } else {
            self.llmClient = try Client.fromEnv()
        }
    }

    // MARK: - Public API

    public func submit(_ input: String) async {
        // Call processInput directly on the actor to avoid a deadlock:
        // wrapping in Task { await self.processInput() } + await task.value
        // deadlocks because the Task re-enters the same actor serial executor
        // that is already suspended waiting for task.value.
        await processInput(input)
        await persistStateIfNeeded()
    }

    public func updateConfig(_ mutator: (inout SessionConfig) -> Void) async {
        mutator(&config)
        await persistStateIfNeeded()
    }

    public func steer(_ message: String) async {
        steeringQueue.append(message)
        await persistStateIfNeeded()
    }

    public func followUp(_ message: String) async {
        followupQueue.append(message)
        await persistStateIfNeeded()
    }

    public func abort() async {
        abortSignaled = true
        state = .closed
        processingTask?.cancel()
        await persistStateIfNeeded()
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
        await persistStateIfNeeded()
    }

    public func addSystemReminder(_ reminder: String) async {
        history.append(.system(SystemTurn(content: wrapSystemReminder(reminder))))
        await persistStateIfNeeded()
    }

    public func getState() -> SessionState {
        state
    }

    public func getHistory() -> [Turn] {
        history
    }

    @discardableResult
    public func restoreFromStorage() async throws -> Bool {
        didAttemptStorageRestore = true
        guard let storageBackend else { return false }
        guard let snapshot = try await storageBackend.load(sessionID: id) else {
            return false
        }
        if snapshot.providerID != providerProfile.id || snapshot.model != providerProfile.model {
            await eventEmitter.emit(SessionEvent(
                kind: .warning,
                sessionId: id,
                data: [
                    "message": "Restored session was created for \(snapshot.providerID)/\(snapshot.model) but current session is \(providerProfile.id)/\(providerProfile.model).",
                ]
            ))
        }
        history = snapshot.history.map { $0.toTurn() }
        steeringQueue = snapshot.steeringQueue
        followupQueue = snapshot.followupQueue
        config = snapshot.config
        state = snapshot.state
        abortSignaled = snapshot.abortSignaled
        await eventEmitter.emit(SessionEvent(
            kind: .warning,
            sessionId: id,
            data: ["message": "Session restored from storage (\(history.count) turns)"]
        ))
        return true
    }

    public func persistNow() async {
        await persistStateIfNeeded()
    }

    public func clearPersistedState() async throws {
        guard let storageBackend else { return }
        try await storageBackend.delete(sessionID: id)
    }

    // MARK: - Core Agentic Loop

    private func processInput(_ userInput: String) async {
        fputs("[Session] processInput called (\(userInput.count) chars)\n", stderr)
        if autoRestoreFromStorage && !didAttemptStorageRestore {
            do {
                _ = try await restoreFromStorage()
            } catch {
                await eventEmitter.emit(SessionEvent(
                    kind: .warning,
                    sessionId: id,
                    data: ["message": "Failed to restore session from storage: \(error)"]
                ))
            }
        }
        await recoverPendingToolCallsIfNeeded()

        // Emit SESSION_START on first input
        if history.isEmpty {
            await eventEmitter.emit(SessionEvent(kind: .sessionStart, sessionId: id))
        }
        state = .processing
        history.append(.user(UserTurn(content: userInput)))
        await persistStateIfNeeded()
        await eventEmitter.emit(SessionEvent(kind: .userInput, sessionId: id, data: ["content": userInput]))

        await drainSteering()

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
            fputs("[Session] Calling LLM: \(providerProfile.model) via \(providerProfile.id) (round \(roundCount), \(messages.count) messages, \(toolDefs.count) tools)\n", stderr)
            let response: Response
            do {
                response = try await completeWithTransientRetries(request: request)
                fputs("[Session] LLM returned: \(response.text.prefix(100))... (\(response.toolCalls.count) tool calls)\n", stderr)
            } catch {
                let errorDetail: String
                if let sdkError = error as? SDKError {
                    errorDetail = "\(type(of: sdkError)): \(sdkError.message)"
                } else {
                    errorDetail = "\(error)"
                }
                await eventEmitter.emit(SessionEvent(kind: .error, sessionId: id, data: ["error": errorDetail]))
                if error is AuthenticationError || error is ContextLengthError {
                    state = .closed
                    await persistStateIfNeeded()
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
                rawContentParts: response.message.content,
                usage: response.usage,
                responseId: response.id
            )
            history.append(.assistant(assistantTurn))
            await persistStateIfNeeded()
            await eventEmitter.emit(SessionEvent(
                kind: .assistantTextStart,
                sessionId: id,
                data: [
                    "response_id": response.id,
                    "tool_call_count": "\(response.toolCalls.count)",
                ]
            ))
            if !response.text.isEmpty {
                await eventEmitter.emit(SessionEvent(
                    kind: .assistantTextDelta,
                    sessionId: id,
                    data: [
                        "delta": response.text,
                    ]
                ))
            }
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
            await persistStateIfNeeded()

            // 7. Drain steering
            await drainSteering()

            // 8. Loop detection
            if config.enableLoopDetection {
                if detectLoop(window: config.loopDetectionWindow) {
                    let warning = "Loop detected: the last \(config.loopDetectionWindow) tool calls follow a repeating pattern. Try a different approach."
                    history.append(.steering(SteeringTurn(content: warning)))
                    await persistStateIfNeeded()
                    await eventEmitter.emit(SessionEvent(kind: .loopDetection, sessionId: id, data: ["message": warning]))
                }
            }

            // Context window awareness
            await checkContextUsage()
        }

        // Process follow-up messages
        if !followupQueue.isEmpty {
            let nextInput = followupQueue.removeFirst()
            await persistStateIfNeeded()
            await processInput(nextInput)
            return
        }

        state = .idle
        await persistStateIfNeeded()
        await eventEmitter.emit(SessionEvent(kind: .sessionEnd, sessionId: id))
    }

    private func recoverPendingToolCallsIfNeeded() async {
        guard let pending = unresolvedToolCallsFromHistory() else { return }

        await eventEmitter.emit(SessionEvent(
            kind: .warning,
            sessionId: id,
            data: [
                "message": "Recovered pending tool-call round from session history (\(pending.count) call(s)).",
            ]
        ))

        let results = await executeToolCalls(pending)
        history.append(.toolResults(ToolResultsTurn(results: results)))
        await persistStateIfNeeded()
    }

    private func unresolvedToolCallsFromHistory() -> [ToolCall]? {
        guard !history.isEmpty else { return nil }
        for idx in stride(from: history.count - 1, through: 0, by: -1) {
            let turn = history[idx]
            if case .assistant(let assistant) = turn, !assistant.toolCalls.isEmpty {
                if idx + 1 >= history.count {
                    return assistant.toolCalls
                }
                let tail = history[(idx + 1)...]
                for t in tail {
                    if case .toolResults = t {
                        return nil
                    }
                }
                return assistant.toolCalls
            }
            if case .toolResults = turn {
                return nil
            }
        }
        return nil
    }

    private func persistStateIfNeeded() async {
        guard let storageBackend else { return }
        let snapshot = SessionSnapshot(
            sessionID: id,
            providerID: providerProfile.id,
            model: providerProfile.model,
            workingDirectory: executionEnv.workingDirectory(),
            state: state,
            history: history.map(PersistedTurn.init),
            steeringQueue: steeringQueue,
            followupQueue: followupQueue,
            config: config,
            abortSignaled: abortSignaled,
            updatedAt: Date()
        )
        do {
            try await storageBackend.save(snapshot)
        } catch {
            await eventEmitter.emit(SessionEvent(
                kind: .warning,
                sessionId: id,
                data: [
                    "message": "Failed to persist session state: \(error)",
                ]
            ))
        }
    }

    // MARK: - Steering

    private func drainSteering() async {
        while !steeringQueue.isEmpty {
            let msg = steeringQueue.removeFirst()
            history.append(.steering(SteeringTurn(content: msg)))
            await persistStateIfNeeded()
            await eventEmitter.emit(SessionEvent(kind: .steeringInjected, sessionId: id, data: ["content": msg]))
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
            return ToolResult(toolCallId: toolCall.id, content: .string(errorMsg), isError: true)
        }

        // Validate arguments against tool parameter schema
        if let validationError = validateToolArguments(toolCall.arguments, against: registered.definition.parameters) {
            await eventEmitter.emit(SessionEvent(
                kind: .toolCallEnd,
                sessionId: id,
                data: ["call_id": toolCall.id, "error": validationError]
            ))
            return ToolResult(toolCallId: toolCall.id, content: .string(validationError), isError: true)
        }

        let foundationArguments: [String: Any]
        do {
            foundationArguments = try toolCall.arguments.mapValues { try $0.asFoundationObject() }
        } catch {
            let conversionError = "Invalid tool arguments for \(toolCall.name): \(error)"
            await eventEmitter.emit(SessionEvent(
                kind: .toolCallEnd,
                sessionId: id,
                data: ["call_id": toolCall.id, "error": conversionError]
            ))
            return ToolResult(toolCallId: toolCall.id, content: .string(conversionError), isError: true)
        }

        do {
            let rawOutput = try await registered.executor(foundationArguments, executionEnv)
            let truncatedOutput = truncateToolOutput(rawOutput, toolName: toolCall.name, config: config)
            let imageAttachment = resolveImageAttachment(toolName: toolCall.name, arguments: foundationArguments)

            await eventEmitter.emit(SessionEvent(
                kind: .toolCallEnd,
                sessionId: id,
                data: ["call_id": toolCall.id, "output": rawOutput, "truncated": "\(rawOutput.count != truncatedOutput.count)"]
            ))

            return ToolResult(
                toolCallId: toolCall.id,
                content: .string(truncatedOutput),
                isError: false,
                imageData: imageAttachment?.data,
                imageMediaType: imageAttachment?.mediaType
            )
        } catch {
            let errorMsg = "Tool error (\(toolCall.name)): \(error)"
            await eventEmitter.emit(SessionEvent(
                kind: .toolCallEnd,
                sessionId: id,
                data: ["call_id": toolCall.id, "error": errorMsg]
            ))
            return ToolResult(toolCallId: toolCall.id, content: .string(errorMsg), isError: true)
        }
    }

    // MARK: - History Conversion

    private func convertHistoryToMessages(systemPrompt: String) -> [Message] {
        var messages: [Message] = [.system(systemPrompt)]
        if !config.interactiveMode {
            messages.append(.user("""
<system-reminder>
You are running in non-interactive (automated pipeline) mode. Complete your assigned task using the available tools, then provide your final response. Do not attempt to ask the user questions or wait for interactive input.
</system-reminder>
"""))
        }

        for turn in history {
            switch turn {
            case .user(let t):
                messages.append(.user(t.content))
            case .assistant(let t):
                // Use raw content parts when available for faithful round-tripping
                // of thinking blocks (with signatures), redacted thinking, etc.
                if let rawParts = t.rawContentParts, !rawParts.isEmpty {
                    messages.append(Message(role: .assistant, content: rawParts))
                } else {
                    var parts: [ContentPart] = []
                    if let reasoning = t.reasoning, !reasoning.isEmpty {
                        parts.append(.thinking(ThinkingData(text: reasoning)))
                    }
                    if !t.content.isEmpty {
                        parts.append(.text(t.content))
                    }
                    for tc in t.toolCalls {
                        parts.append(.toolCall(tc))
                    }
                    if parts.isEmpty {
                        parts.append(.text(""))
                    }
                    messages.append(Message(role: .assistant, content: parts))
                }
            case .toolResults(let t):
                for result in t.results {
                    messages.append(.toolResult(
                        toolCallId: result.toolCallId,
                        content: result.content,
                        isError: result.isError,
                        imageData: result.imageData,
                        imageMediaType: result.imageMediaType
                    ))
                    if let imageData = result.imageData {
                        let image = ImageData(data: imageData, mediaType: result.imageMediaType)
                        messages.append(Message(
                            role: .user,
                            content: [
                                .text("<system-reminder>Image content from the previous view_image tool call is attached below.</system-reminder>"),
                                .image(image),
                            ]
                        ))
                    }
                }
            case .system(let t):
                messages.append(.user(t.content))
            case .steering(let t):
                messages.append(.user(t.content))
            }
        }

        return messages
    }

    private func completeWithTransientRetries(request: Request) async throws -> Response {
        let maxAttempts = 3
        var attempt = 1

        while true {
            do {
                return try await llmClient.complete(request: request)
            } catch {
                if error is AuthenticationError || error is ContextLengthError {
                    throw error
                }

                let shouldRetry = isTransient(error)
                if !shouldRetry || attempt >= maxAttempts {
                    throw error
                }

                let delaySeconds = transientRetryDelaySeconds(forAttempt: attempt, error: error)
                await eventEmitter.emit(SessionEvent(
                    kind: .warning,
                    sessionId: id,
                    data: [
                        "message": "Transient LLM error; retrying attempt \(attempt + 1)/\(maxAttempts) in \(String(format: "%.2f", delaySeconds))s",
                        "error": "\(error)",
                    ]
                ))
                try await Task.sleep(for: .seconds(delaySeconds))
                attempt += 1
            }
        }
    }

    private func isTransient(_ error: any Error) -> Bool {
        if let sdkError = error as? SDKError {
            return sdkError.retryable
        }
        if error is URLError {
            return true
        }
        return false
    }

    private func transientRetryDelaySeconds(forAttempt attempt: Int, error: any Error) -> Double {
        if let sdkError = error as? SDKError,
           let retryAfter = sdkError.retryAfter,
           retryAfter > 0
        {
            return retryAfter
        }
        // Backoff sequence for attempts 1..N
        switch attempt {
        case 1: return 0.5
        case 2: return 1.5
        default: return 3.0
        }
    }

    private func resolveImageAttachment(
        toolName: String,
        arguments: [String: Any]
    ) -> (data: [UInt8], mediaType: String)? {
        guard toolName == "view_image", let rawPath = arguments["path"] as? String else {
            return nil
        }

        let resolvedPath: String = {
            if rawPath.hasPrefix("/") { return rawPath }
            return (executionEnv.workingDirectory() as NSString).appendingPathComponent(rawPath)
        }()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: resolvedPath)), !data.isEmpty else {
            return nil
        }
        let mediaType = mimeType(for: resolvedPath)
        return (Array(data), mediaType)
    }

    private func mimeType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "tif", "tiff": return "image/tiff"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        default: return "application/octet-stream"
        }
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

    private func stableHash(_ dict: [String: JSONValue]) -> String {
        let sorted = dict.sorted(by: { $0.key < $1.key })
        let desc = sorted.map { "\($0.key)=\(stableValueDescription($0.value))" }.joined(separator: ",")
        var hasher = Hasher()
        hasher.combine(desc)
        return "\(hasher.finalize())"
    }

    // MARK: - Tool Argument Validation

    private func validateToolArguments(_ args: [String: JSONValue], against schema: JSONValue) -> String? {
        do {
            try JSONSchema(schema).validate(.object(args))
            return nil
        } catch {
            return "Invalid tool arguments: \(error)"
        }
    }

    // MARK: - Context Window Awareness

    private func checkContextUsage() async {
        let approxTokens = totalCharsInHistory() / 4
        let threshold = providerProfile.contextWindowSize * 80 / 100
        if approxTokens > threshold {
            let pct = approxTokens * 100 / providerProfile.contextWindowSize
            await eventEmitter.emit(SessionEvent(
                kind: .warning,
                sessionId: id,
                data: ["message": "Context usage at ~\(pct)% of context window"]
            ))
        }
    }

    private func totalCharsInHistory() -> Int {
        var total = 0
        for turn in history {
            switch turn {
            case .user(let t): total += t.content.count
            case .assistant(let t): total += t.content.count + (t.reasoning?.count ?? 0)
            case .toolResults(let t): total += t.results.reduce(0) { $0 + stringifyJSONValue($1.content).count }
            case .system(let t): total += t.content.count
            case .steering(let t): total += t.content.count
            }
        }
        return total
    }

    private func countTurns() -> Int {
        history.count
    }

    private func stableValueDescription(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let b):
            return b ? "true" : "false"
        case .number(let n):
            return String(n)
        case .string(let s):
            return "\"\(s)\""
        case .array(let arr):
            return "[" + arr.map(stableValueDescription).joined(separator: ",") + "]"
        case .object(let obj):
            let parts = obj.keys.sorted().map { key in
                "\(key):\(stableValueDescription(obj[key]!))"
            }
            return "{\(parts.joined(separator: ","))}"
        }
    }

    private func stringifyJSONValue(_ value: JSONValue) -> String {
        if case .string(let s) = value {
            return s
        }
        return stableValueDescription(value)
    }

    private func wrapSystemReminder(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("<system-reminder>") {
            return trimmed
        }
        return """
<system-reminder>
\(trimmed)
</system-reminder>
"""
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
