import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - read_file

public func codexReadFileTool() -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "read_file",
            description: "Reads a local file with 1-indexed line numbers, supporting slice and indentation-aware block modes.",
            parameters: [
                "type": "object",
                "properties": [
                    "file_path": ["type": "string", "description": "Absolute path to the file"],
                    "offset": ["type": "number", "description": "The line number to start reading from. Must be 1 or greater."],
                    "limit": ["type": "number", "description": "The maximum number of lines to return."],
                    "mode": ["type": "string", "description": "Optional mode selector: \"slice\" for simple ranges (default) or \"indentation\" to expand around an anchor line."],
                    "indentation": [
                        "type": "object",
                        "description": "Indentation mode options",
                        "properties": [
                            "anchor_line": ["type": "number", "description": "Anchor line to center the indentation lookup on (defaults to offset)."],
                            "max_levels": ["type": "number", "description": "How many parent indentation levels (smaller indents) to include."],
                            "include_siblings": ["type": "boolean", "description": "When true, include additional blocks that share the anchor indentation."],
                            "include_header": ["type": "boolean", "description": "Include doc comments or attributes directly above the selected block."],
                            "max_lines": ["type": "number", "description": "Hard cap on the number of lines returned when using indentation mode."],
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["file_path"],
            ] as [String: Any]
        ),
        executor: { args, env in
            guard let filePath = args["file_path"] as? String else {
                throw ToolError.validationError("file_path is required")
            }
            let resolvedPath = codexResolvePath(filePath, env: env)
            let offset = max(1, Int((args["offset"] as? Double) ?? Double(codexIntValue(args["offset"]) ?? 1)))
            let limit = max(1, Int((args["limit"] as? Double) ?? Double(codexIntValue(args["limit"]) ?? 2000)))
            let content = try await env.readFile(path: resolvedPath, offset: offset, limit: limit)
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "File is empty or requested range is out of range."
            }
            return content
        }
    )
}

// MARK: - shell

public func codexShellTool(defaultTimeoutMs: Int = 10_000, maxTimeoutMs: Int = 600_000) -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "shell",
            description: """
Runs a shell command and returns its output.
- The arguments to `shell` will be passed to execvp(). Most terminal commands should be prefixed with ["bash", "-lc"].
- Always set the `workdir` param when using the shell function. Do not use `cd` unless absolutely necessary.
""",
            parameters: [
                "type": "object",
                "properties": [
                    "command": [
                        "type": "array",
                        "description": "The command to execute",
                        "items": ["type": "string"],
                    ] as [String: Any],
                    "workdir": ["type": "string", "description": "The working directory to execute the command in"],
                    "timeout_ms": ["type": "number", "description": "The timeout for the command in milliseconds"],
                    "sandbox_permissions": ["type": "string", "description": "Sandbox permissions for the command. Set to \"require_escalated\" to request running without sandbox restrictions; defaults to \"use_default\"."],
                    "justification": ["type": "string", "description": "Only set if sandbox_permissions is \"require_escalated\". 1-sentence explanation of why we want to run this command."],
                ] as [String: Any],
                "required": ["command"],
            ] as [String: Any]
        ),
        executor: { args, env in
            guard let commandArray = codexStringArray(args["command"]), !commandArray.isEmpty else {
                throw ToolError.validationError("command is required")
            }
            let command = codexShellJoin(commandArray)
            var timeoutMs = defaultTimeoutMs
            if let override = codexIntValue(args["timeout_ms"]) {
                timeoutMs = min(override, maxTimeoutMs)
            }
            let workdir = args["workdir"] as? String
            return try await codexExecuteCommand(
                env: env,
                command: command,
                timeoutMs: timeoutMs,
                workdir: workdir,
                emitOutputDelta: { _ in }
            )
        },
        streamingExecutor: { args, env, emitOutputDelta in
            guard let commandArray = codexStringArray(args["command"]), !commandArray.isEmpty else {
                throw ToolError.validationError("command is required")
            }
            let command = codexShellJoin(commandArray)
            var timeoutMs = defaultTimeoutMs
            if let override = codexIntValue(args["timeout_ms"]) {
                timeoutMs = min(override, maxTimeoutMs)
            }
            let workdir = args["workdir"] as? String
            return try await codexExecuteCommand(
                env: env,
                command: command,
                timeoutMs: timeoutMs,
                workdir: workdir,
                emitOutputDelta: emitOutputDelta
            )
        }
    )
}

// MARK: - list_dir

public func codexListDirTool() -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "list_dir",
            description: "Lists entries in a local directory with 1-indexed entry numbers and simple type labels.",
            parameters: [
                "type": "object",
                "properties": [
                    "dir_path": ["type": "string", "description": "Absolute path to the directory to list."],
                    "offset": ["type": "number", "description": "The entry number to start listing from. Must be 1 or greater."],
                    "limit": ["type": "number", "description": "The maximum number of entries to return."],
                    "depth": ["type": "number", "description": "The maximum directory depth to traverse. Must be 1 or greater."],
                ] as [String: Any],
                "required": ["dir_path"],
            ] as [String: Any]
        ),
        executor: { args, env in
            guard let dirPath = args["dir_path"] as? String else {
                throw ToolError.validationError("dir_path is required")
            }
            let resolvedPath = codexResolvePath(dirPath, env: env)

            let offset = max(1, Int((args["offset"] as? Double) ?? Double(codexIntValue(args["offset"]) ?? 1)))
            let limit = max(1, Int((args["limit"] as? Double) ?? Double(codexIntValue(args["limit"]) ?? 100)))
            let depth = max(1, Int((args["depth"] as? Double) ?? Double(codexIntValue(args["depth"]) ?? 1)))

            var entries: [(path: String, type: String)] = []
            try await codexCollectEntries(
                at: resolvedPath,
                basePath: "",
                depth: depth,
                env: env,
                entries: &entries
            )
            entries.sort { $0.path < $1.path }

            guard !entries.isEmpty else {
                return "Directory is empty."
            }

            let startIndex = offset - 1
            let endIndex = min(startIndex + limit, entries.count)
            guard startIndex < entries.count else {
                return "Directory has \(entries.count) entries, requested offset \(offset) is out of range."
            }

            var output = ""
            for index in startIndex..<endIndex {
                output += "\(index + 1)\t\(entries[index].type)\t\(entries[index].path)\n"
            }
            if endIndex < entries.count {
                output += "\n... (\(entries.count - endIndex) more entries)"
            }
            return output
        }
    )
}

// MARK: - web_search

public func codexWebSearchTool() -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "web_search",
            description: "Search the web for information. Returns search results with titles, URLs, and snippets.",
            parameters: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "The search query."],
                    "num_results": ["type": "number", "description": "Maximum number of results to return. Defaults to 10."],
                ] as [String: Any],
                "required": ["query"],
            ] as [String: Any]
        ),
        executor: { args, _ in
            guard let query = args["query"] as? String else {
                throw ToolError.validationError("query is required")
            }
            let maxResults = max(1, Int((args["num_results"] as? Double) ?? Double(codexIntValue(args["num_results"]) ?? 10)))
            let results = try await WebSearchClient.search(query: query, maxResults: maxResults)
            guard !results.isEmpty else {
                return "Search results for: \(query)\n\nNo results found for this query."
            }
            var output = "Search results for: \(query)\n\n"
            for (index, result) in results.enumerated() {
                output += "\(index + 1). \(result.title)\n"
                output += "   \(result.url)\n"
                if !result.snippet.isEmpty {
                    output += "   \(result.snippet)\n"
                }
                output += "\n"
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    )
}

// MARK: - update_plan

public func updatePlanTool() -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "update_plan",
            description: """
Updates the task plan.
Provide an optional explanation and a list of plan items, each with a step and status.
At most one step can be in_progress at a time.
""",
            parameters: [
                "type": "object",
                "properties": [
                    "explanation": ["type": "string"],
                    "plan": [
                        "type": "array",
                        "description": "The list of steps",
                        "items": [
                            "type": "object",
                            "properties": [
                                "step": ["type": "string"],
                                "status": [
                                    "type": "string",
                                    "description": "One of: pending, in_progress, completed",
                                ],
                            ] as [String: Any],
                            "required": ["step", "status"],
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["plan"],
            ] as [String: Any]
        ),
        executor: { args, _ in
            guard let rawPlan = args["plan"] as? [Any], !rawPlan.isEmpty else {
                throw ToolError.validationError("plan is required")
            }
            var inProgressCount = 0
            for item in rawPlan {
                guard let step = item as? [String: Any] else { continue }
                if (step["status"] as? String) == "in_progress" {
                    inProgressCount += 1
                }
            }
            if inProgressCount > 1 {
                throw ToolError.validationError("At most one step can be in_progress")
            }
            return "Plan updated"
        }
    )
}

// MARK: - view_image

public func viewImageTool() -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "view_image",
            description: "View a local image from the filesystem (only use if given a full filepath by the user, and the image isn't already attached to the thread context within <image ...> tags).",
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Local filesystem path to an image file"],
                ] as [String: Any],
                "required": ["path"],
            ] as [String: Any]
        ),
        executor: { args, env in
            guard let path = args["path"] as? String else {
                throw ToolError.validationError("path is required")
            }

            let resolvedPath: String
            if path.hasPrefix("/") {
                resolvedPath = path
            } else {
                resolvedPath = (env.workingDirectory() as NSString).appendingPathComponent(path)
            }

            guard FileManager.default.fileExists(atPath: resolvedPath) else {
                throw ToolError.fileNotFound(resolvedPath)
            }

            let ext = URL(fileURLWithPath: resolvedPath).pathExtension.lowercased()
            let supported = Set(["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff"])
            guard supported.contains(ext) else {
                throw ToolError.validationError("unsupported image format: \(ext)")
            }

            let attrs = try FileManager.default.attributesOfItem(atPath: resolvedPath)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "Image attached: \(resolvedPath) (\(formatter.string(fromByteCount: size)))"
        }
    )
}

// MARK: - shell_command

public func shellCommandTool(defaultTimeoutMs: Int = 10_000, maxTimeoutMs: Int = 600_000) -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "shell_command",
            description: """
Runs a shell command and returns its output.
- Always set the `workdir` param when using the shell_command function. Do not use `cd` unless absolutely necessary.
""",
            parameters: [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "The shell script to execute in the user's default shell"],
                    "workdir": ["type": "string", "description": "The working directory to execute the command in"],
                    "login": ["type": "boolean", "description": "Whether to run the shell with login shell semantics. Defaults to true."],
                    "timeout_ms": ["type": "number", "description": "The timeout for the command in milliseconds"],
                    "sandbox_permissions": ["type": "string", "description": "Sandbox permissions for the command. Set to \"require_escalated\" to request running without sandbox restrictions; defaults to \"use_default\"."],
                    "justification": ["type": "string", "description": "Only set if sandbox_permissions is \"require_escalated\". 1-sentence explanation of why we want to run this command."],
                ] as [String: Any],
                "required": ["command"],
            ] as [String: Any]
        ),
        executor: { args, env in
            guard let command = args["command"] as? String else {
                throw ToolError.validationError("command is required")
            }
            var timeoutMs = defaultTimeoutMs
            if let override = codexIntValue(args["timeout_ms"]) {
                timeoutMs = min(override, maxTimeoutMs)
            }
            let workdir = args["workdir"] as? String
            return try await codexExecuteCommand(
                env: env,
                command: command,
                timeoutMs: timeoutMs,
                workdir: workdir,
                emitOutputDelta: { _ in }
            )
        },
        streamingExecutor: { args, env, emitOutputDelta in
            guard let command = args["command"] as? String else {
                throw ToolError.validationError("command is required")
            }
            var timeoutMs = defaultTimeoutMs
            if let override = codexIntValue(args["timeout_ms"]) {
                timeoutMs = min(override, maxTimeoutMs)
            }
            let workdir = args["workdir"] as? String
            return try await codexExecuteCommand(
                env: env,
                command: command,
                timeoutMs: timeoutMs,
                workdir: workdir,
                emitOutputDelta: emitOutputDelta
            )
        }
    )
}

// MARK: - grep_files

public func grepFilesTool() -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "grep_files",
            description: "Finds files whose contents match the pattern and lists them by modification time.",
            parameters: [
                "type": "object",
                "properties": [
                    "pattern": ["type": "string", "description": "Regular expression pattern to search for."],
                    "include": ["type": "string", "description": "Optional glob that limits which files are searched (e.g. \"*.rs\" or \"*.{ts,tsx}\")."],
                    "path": ["type": "string", "description": "Directory or file path to search. Defaults to the session's working directory."],
                    "limit": ["type": "number", "description": "Maximum number of file paths to return (defaults to 100)."],
                ] as [String: Any],
                "required": ["pattern"],
            ] as [String: Any]
        ),
        executor: { args, env in
            guard let pattern = args["pattern"] as? String else {
                throw ToolError.validationError("pattern is required")
            }
            let searchPath = (args["path"] as? String) ?? env.workingDirectory()
            let include = args["include"] as? String
            let limit = max(1, codexIntValue(args["limit"]) ?? 100)
            let grepOutput = try await env.grep(
                pattern: pattern,
                path: searchPath,
                options: GrepOptions(
                    globFilter: include,
                    caseInsensitive: false,
                    maxResults: max(limit * 20, limit)
                )
            )
            let matchingFiles = codexUniqueMatchedFiles(from: grepOutput, limit: limit)
            return matchingFiles.isEmpty ? "No matching files found." : matchingFiles.joined(separator: "\n")
        }
    )
}

private func codexResolveShellPath(requestedShell: String?) -> String {
    if let requestedShell, FileManager.default.isExecutableFile(atPath: requestedShell) {
        return requestedShell
    }
    if let envShell = ProcessInfo.processInfo.environment["SHELL"],
       FileManager.default.isExecutableFile(atPath: envShell) {
        return envShell
    }
    if FileManager.default.isExecutableFile(atPath: "/bin/bash") {
        return "/bin/bash"
    }
    return "/bin/sh"
}

private func codexRunExecSession(
    args: [String: Any],
    env: ExecutionEnvironment,
    onChunk: StreamingToolOutputEmitter
) async throws -> String {
    guard let cmd = args["cmd"] as? String else {
        throw ToolError.validationError("cmd is required")
    }

    let workdir = (args["workdir"] as? String) ?? env.workingDirectory()
    let login = codexBoolValue(args["login"]) ?? true
    let tty = codexBoolValue(args["tty"]) ?? false
    let yieldMs = max(0, codexIntValue(args["yield_time_ms"]) ?? 5_000)
    let maxChars = codexIntValue(args["max_output_tokens"]).map { max(500, $0 * 4) }
    let shellPath = codexResolveShellPath(requestedShell: args["shell"] as? String)

    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    _ = shellPath
    _ = login
    let sessionId = try await CodexInteractiveExecSessionStore.shared.create(
        env: env,
        command: cmd,
        workingDirectory: workdir,
        tty: tty
    )
    let snapshot = try await CodexInteractiveExecSessionStore.shared.read(
        sessionId: sessionId,
        waitMs: yieldMs,
        maxChars: maxChars,
        onChunk: onChunk
    )
    return codexExecSnapshotText(sessionId: sessionId, snapshot: snapshot)
    #else
    let sessionId = try await CodexExecSessionStore.shared.create(
        command: cmd,
        shell: shellPath,
        login: login,
        workingDirectory: workdir,
        tty: tty
    )
    let snapshot = try await CodexExecSessionStore.shared.read(
        sessionId: sessionId,
        waitMs: yieldMs,
        maxChars: maxChars,
        onChunk: onChunk
    )
    return codexExecSnapshotText(sessionId: sessionId, snapshot: snapshot)
    #endif
}

private func codexWriteExecSession(
    args: [String: Any],
    onChunk: StreamingToolOutputEmitter
) async throws -> String {
    guard let sessionId = codexIntValue(args["session_id"]) else {
        throw ToolError.validationError("session_id is required")
    }
    let chars = (args["chars"] as? String) ?? ""
    let yieldMs = max(0, codexIntValue(args["yield_time_ms"]) ?? 1_000)
    let maxChars = codexIntValue(args["max_output_tokens"]).map { max(500, $0 * 4) }

    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    if !chars.isEmpty {
        try await CodexInteractiveExecSessionStore.shared.write(sessionId: sessionId, chars: chars)
    }

    let snapshot = try await CodexInteractiveExecSessionStore.shared.read(
        sessionId: sessionId,
        waitMs: yieldMs,
        maxChars: maxChars,
        onChunk: onChunk
    )
    return codexExecSnapshotText(sessionId: sessionId, snapshot: snapshot)
    #else
    if !chars.isEmpty {
        try await CodexExecSessionStore.shared.write(sessionId: sessionId, chars: chars)
    }

    let snapshot = try await CodexExecSessionStore.shared.read(
        sessionId: sessionId,
        waitMs: yieldMs,
        maxChars: maxChars,
        onChunk: onChunk
    )
    return codexExecSnapshotText(sessionId: sessionId, snapshot: snapshot)
    #endif
}

// MARK: - exec_command / write_stdin

public func execCommandTool() -> RegisteredTool {
    let description = "Runs a command in a PTY, returning output or a session ID for ongoing interaction."
    return RegisteredTool(
        definition: AgentToolDefinition(
            name: "exec_command",
            description: description,
            parameters: [
                "type": "object",
                "properties": [
                    "cmd": ["type": "string", "description": "Shell command to execute."],
                    "workdir": ["type": "string", "description": "Optional working directory to run the command in; defaults to the turn cwd."],
                    "shell": ["type": "string", "description": "Shell binary to launch. Defaults to the user's default shell."],
                    "login": ["type": "boolean", "description": "Whether to run the shell with -l/-i semantics. Defaults to true."],
                    "tty": [
                        "type": "boolean",
                        "description": "Whether to allocate a TTY for the command. Defaults to false (plain pipes); set to true to open a PTY and access TTY process.",
                    ],
                    "yield_time_ms": ["type": "number", "description": "How long to wait (in milliseconds) for output before yielding."],
                    "max_output_tokens": ["type": "number", "description": "Maximum number of tokens to return. Excess output will be truncated."],
                    "sandbox_permissions": ["type": "string", "description": "Sandbox permissions for the command. Set to \"require_escalated\" to request running without sandbox restrictions; defaults to \"use_default\"."],
                    "justification": ["type": "string", "description": "Only set if sandbox_permissions is \"require_escalated\". 1-sentence explanation of why we want to run this command."],
                    "prefix_rule": [
                        "type": "array",
                        "description": """
Only specify when sandbox_permissions is `require_escalated`.
Suggest a prefix command pattern that will allow you to fulfill similar requests from the user in the future.
Should be a short but reasonable prefix, e.g. [\"git\", \"pull\"] or [\"uv\", \"run\"] or [\"pytest\"].
""",
                        "items": ["type": "string"],
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["cmd"],
            ] as [String: Any]
        ),
        executor: { args, env in
            try await codexRunExecSession(args: args, env: env, onChunk: { _ in })
        },
        streamingExecutor: { args, env, emitOutputDelta in
            try await codexRunExecSession(args: args, env: env, onChunk: emitOutputDelta)
        }
    )
}

public func writeStdinTool() -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "write_stdin",
            description: "Writes characters to an existing unified exec session and returns recent output.",
            parameters: [
                "type": "object",
                "properties": [
                    "session_id": ["type": "number", "description": "Identifier of the running unified exec session."],
                    "chars": ["type": "string", "description": "Bytes to write to stdin (may be empty to poll)."],
                    "yield_time_ms": ["type": "number", "description": "How long to wait (in milliseconds) for output before yielding."],
                    "max_output_tokens": ["type": "number", "description": "Maximum number of tokens to return. Excess output will be truncated."],
                ] as [String: Any],
                "required": ["session_id"],
            ] as [String: Any]
        ),
        executor: { args, _ in
            try await codexWriteExecSession(args: args, onChunk: { _ in })
        },
        streamingExecutor: { args, _, emitOutputDelta in
            try await codexWriteExecSession(args: args, onChunk: emitOutputDelta)
        }
    )
}

// MARK: - spawn_agent / send_input / wait / close_agent

public func codexSpawnAgentTool(parentSession: Session) -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "spawn_agent",
            description: "Spawn a new agent and return its id.",
            parameters: [
                "type": "object",
                "properties": [
                    "message": ["type": "string", "description": "Initial message to send to the new agent."],
                ] as [String: Any],
                "required": ["message"],
            ] as [String: Any]
        ),
        executor: { args, env in
            guard let message = args["message"] as? String else {
                throw ToolError.validationError("message is required")
            }

            let currentDepth = await parentSession.currentDepth()
            let maxDepth = await parentSession.config.maxSubagentDepth
            guard currentDepth < maxDepth else {
                throw ToolError.validationError("Maximum subagent depth (\(maxDepth)) reached")
            }

            let profile = parentSession.providerProfile
            let client = parentSession.llmClient
            var subConfig = SessionConfig(maxTurns: 50)
            subConfig.reasoningEffort = await parentSession.config.reasoningEffort

            let subSession = try Session(
                profile: profile,
                environment: env,
                client: client,
                config: subConfig,
                depth: currentDepth + 1
            )

            let handle = SubAgentHandle(id: UUID().uuidString, session: subSession)
            await parentSession.registerSubagent(handle)

            // Safety: spawned subagents are owned by the parent session registry and intentionally
            // continue independently after this tool returns.
            Task {
                await subSession.submit(message)
            }

            return """
Agent spawned successfully.
Agent ID: \(handle.id)
Initial message delivered.
"""
        }
    )
}

public func codexSendInputTool(parentSession: Session) -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "send_input",
            description: "Send a message to an existing agent.",
            parameters: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Identifier of the agent to message."],
                    "message": ["type": "string", "description": "Message to send to the agent."],
                ] as [String: Any],
                "required": ["id", "message"],
            ] as [String: Any]
        ),
        executor: { args, _ in
            guard let agentID = args["id"] as? String else {
                throw ToolError.validationError("id is required")
            }
            guard let message = args["message"] as? String else {
                throw ToolError.validationError("message is required")
            }

            guard let handle = await parentSession.getSubagent(agentID) else {
                throw ToolError.validationError("Agent \(agentID) not found")
            }

            await handle.session.followUp(message)
            return "Message sent to agent \(agentID)"
        }
    )
}

public func codexWaitTool(parentSession: Session, defaultTimeoutMs: Int = 30_000, maxTimeoutMs: Int = 300_000) -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "wait",
            description: "Wait for an agent and return its status.",
            parameters: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Identifier of the agent to wait on."],
                    "timeout_ms": ["type": "number", "description": "Optional timeout in milliseconds. Defaults to \(defaultTimeoutMs) and max \(maxTimeoutMs)."],
                ] as [String: Any],
                "required": ["id"],
            ] as [String: Any]
        ),
        executor: { args, _ in
            guard let agentID = args["id"] as? String else {
                throw ToolError.validationError("id is required")
            }
            let requestedTimeout = codexIntValue(args["timeout_ms"]) ?? defaultTimeoutMs
            let timeoutMs = min(max(1, requestedTimeout), maxTimeoutMs)

            guard let handle = await parentSession.getSubagent(agentID) else {
                throw ToolError.validationError("Agent \(agentID) not found")
            }

            let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
            while Date() < deadline {
                let state = await handle.session.getState()
                if state == .idle || state == .closed {
                    break
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }

            let state = await handle.session.getState()
            let status: String
            switch state {
            case .idle:
                status = "completed"
            case .closed:
                status = "closed"
            default:
                status = "running"
            }

            return """
Agent ID: \(agentID)
Status: \(status)
Timeout: \(timeoutMs)ms
"""
        }
    )
}

public func codexCloseAgentTool(parentSession: Session) -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "close_agent",
            description: "Close an agent and return its last known status.",
            parameters: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Identifier of the agent to close."],
                ] as [String: Any],
                "required": ["id"],
            ] as [String: Any]
        ),
        executor: { args, _ in
            guard let agentID = args["id"] as? String else {
                throw ToolError.validationError("id is required")
            }
            guard let handle = await parentSession.getSubagent(agentID) else {
                throw ToolError.validationError("Agent \(agentID) not found")
            }

            let state = await handle.session.getState()
            await handle.session.close()
            await parentSession.removeSubagent(agentID)

            let status: String
            switch state {
            case .idle:
                status = "completed"
            case .closed:
                status = "closed"
            default:
                status = "running"
            }

            return """
Agent closed.
Agent ID: \(agentID)
Status: \(status)
"""
        }
    )
}

private func codexCollectEntries(
    at path: String,
    basePath: String,
    depth: Int,
    env: ExecutionEnvironment,
    entries: inout [(path: String, type: String)]
) async throws {
    guard depth > 0 else { return }
    let items = try await env.listDirectory(path: path, depth: 1)
    for item in items.sorted(by: { $0.name < $1.name }) {
        let relativePath = basePath.isEmpty ? item.name : "\(basePath)/\(item.name)"
        let type = item.isDir ? "dir" : "file"
        entries.append((path: relativePath, type: type))
        if item.isDir && depth > 1 {
            let childPath = (path as NSString).appendingPathComponent(item.name)
            try await codexCollectEntries(
                at: childPath,
                basePath: relativePath,
                depth: depth - 1,
                env: env,
                entries: &entries
            )
        }
    }
}

private struct CodexExecSnapshot: Sendable {
    let output: String
    let running: Bool
    let exitCode: Int32?
    let truncatedByMaxOutputTokens: Bool
    let truncatedCharCount: Int
}

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
private final class CodexInteractiveExecSession: @unchecked Sendable {
    private let session: any InteractiveExecutionSession
    private let lock = NSLock()
    private var buffer: String = ""
    private var readOffset: String.Index
    private var running = true
    private var exitCodeValue: Int32?

    private init(session: any InteractiveExecutionSession) {
        self.session = session
        self.readOffset = buffer.startIndex
    }

    static func start(
        env: ExecutionEnvironment,
        command: String,
        workingDirectory: String,
        tty: Bool
    ) async throws -> CodexInteractiveExecSession {
        let session = try await env.startInteractiveSession(
            command: command,
            workingDir: workingDirectory,
            envVars: nil,
            size: tty ? TerminalSize(columns: 120, rows: 36) : TerminalSize(columns: 120, rows: 24)
        )
        let wrapper = CodexInteractiveExecSession(session: session)
        await session.setEventHandler { event in
            wrapper.handle(event)
        }
        return wrapper
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    var exitCode: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return exitCodeValue
    }

    func write(_ chars: String) async throws {
        guard let data = chars.data(using: .utf8) else {
            throw ToolError.validationError("chars must be UTF-8 text")
        }
        try await session.write(data)
    }

    func drainNewOutput(maxChars: Int?) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard readOffset < buffer.endIndex else { return "" }
        let output = String(buffer[readOffset..<buffer.endIndex])
        readOffset = buffer.endIndex
        guard let maxChars, output.count > maxChars else {
            return output
        }
        return String(output.suffix(maxChars))
    }

    func terminate() async {
        await session.setEventHandler(nil)
        await session.terminate()
    }

    func finish() async {
        await session.setEventHandler(nil)
    }

    private func handle(_ event: InteractiveSessionEvent) {
        lock.lock()
        switch event {
        case .output(let data):
            buffer += String(decoding: data, as: UTF8.self)
        case .exit(let code):
            running = false
            exitCodeValue = code
        }
        lock.unlock()
    }
}

private actor CodexInteractiveExecSessionStore {
    static let shared = CodexInteractiveExecSessionStore()

    private var sessions: [Int: CodexInteractiveExecSession] = [:]
    private var nextSessionID: Int = 1

    func create(
        env: ExecutionEnvironment,
        command: String,
        workingDirectory: String,
        tty: Bool
    ) async throws -> Int {
        let sessionID = nextSessionID
        nextSessionID += 1
        let session = try await CodexInteractiveExecSession.start(
            env: env,
            command: command,
            workingDirectory: workingDirectory,
            tty: tty
        )
        sessions[sessionID] = session
        return sessionID
    }

    func write(sessionId: Int, chars: String) async throws {
        guard let session = sessions[sessionId] else {
            throw ToolError.validationError("Session \(sessionId) not found")
        }
        try await session.write(chars)
    }

    func read(
        sessionId: Int,
        waitMs: Int,
        maxChars: Int?,
        onChunk: StreamingToolOutputEmitter
    ) async throws -> CodexExecSnapshot {
        guard let session = sessions[sessionId] else {
            throw ToolError.validationError("Session \(sessionId) not found")
        }

        let deadline = Date().addingTimeInterval(Double(waitMs) / 1000.0)
        var output = session.drainNewOutput(maxChars: nil)
        if !output.isEmpty {
            await onChunk(output)
        }

        while session.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let chunk = session.drainNewOutput(maxChars: nil)
            if !chunk.isEmpty {
                output += chunk
                await onChunk(chunk)
            }
        }

        if !session.isRunning {
            let chunk = session.drainNewOutput(maxChars: nil)
            if !chunk.isEmpty {
                output += chunk
                await onChunk(chunk)
            }
        }

        var truncatedByMaxOutputTokens = false
        var truncatedCharCount = 0
        if let maxChars, output.count > maxChars {
            truncatedByMaxOutputTokens = true
            truncatedCharCount = output.count - maxChars
            output = String(output.suffix(maxChars))
        }

        let snapshot = CodexExecSnapshot(
            output: output,
            running: session.isRunning,
            exitCode: session.exitCode,
            truncatedByMaxOutputTokens: truncatedByMaxOutputTokens,
            truncatedCharCount: truncatedCharCount
        )

        if !snapshot.running {
            await session.finish()
            sessions.removeValue(forKey: sessionId)
        }

        return snapshot
    }
}
#endif

#if !os(iOS) && !os(tvOS) && !os(watchOS) && !os(visionOS)
// Safety: @unchecked Sendable because all mutable state (buffer, readOffset)
// is guarded by `lock`. Process properties (isRunning, terminationStatus) are
// also accessed under the lock to avoid racing with the readabilityHandler
// callback which runs on an arbitrary dispatch queue.
private final class CodexExecSession: @unchecked Sendable {
    private let process: Process
    private let outputPipe: Pipe
    private let inputPipe: Pipe
    private let lock = NSLock()
    private var buffer: String = ""
    private var readOffset: String.Index

    init(command: String, shell: String, login: Bool, workingDirectory: String, tty: Bool) throws {
        process = Process()
        outputPipe = Pipe()
        inputPipe = Pipe()
        readOffset = buffer.startIndex

        if tty {
            guard let scriptPath = codexScriptPath() else {
                throw ToolError.validationError("tty=true requires the 'script' utility to be installed")
            }
            process.executableURL = URL(fileURLWithPath: scriptPath)
            #if os(macOS)
            process.arguments = ["-q", "/dev/null", shell, login ? "-lc" : "-c", command]
            #else
            let shellFlag = login ? "-lc" : "-c"
            let scriptCommand = "\(codexShellEscape(shell)) \(shellFlag) \(codexShellEscape(command))"
            process.arguments = ["-q", "-c", scriptCommand, "/dev/null"]
            #endif
        } else {
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = login ? ["-lc", command] : ["-c", command]
        }
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.standardInput = inputPipe
        process.environment = ProcessInfo.processInfo.environment

        try process.run()
        installReadabilityHandler()
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process.isRunning
    }

    var exitCode: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return process.isRunning ? nil : process.terminationStatus
    }

    func write(_ chars: String) throws {
        guard let data = chars.data(using: .utf8) else {
            throw ToolError.validationError("chars must be UTF-8 text")
        }
        inputPipe.fileHandleForWriting.write(data)
    }

    func drainNewOutput(maxChars: Int?) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard readOffset < buffer.endIndex else { return "" }
        let output = String(buffer[readOffset..<buffer.endIndex])
        readOffset = buffer.endIndex
        guard let maxChars, output.count > maxChars else {
            return output
        }
        return String(output.suffix(maxChars))
    }

    func terminate() {
        lock.lock()
        let running = process.isRunning
        if running {
            process.terminate()
        }
        lock.unlock()
        outputPipe.fileHandleForReading.readabilityHandler = nil
    }

    private func installReadabilityHandler() {
        let fileHandle = outputPipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else {
                return
            }
            self?.append(chunk)
        }
    }

    private func append(_ chunk: String) {
        lock.lock()
        buffer += chunk
        lock.unlock()
    }
}
#else
private final class CodexExecSession: @unchecked Sendable {
    init(command: String, shell: String, login: Bool, workingDirectory: String, tty: Bool) throws {
        throw ToolError.validationError("Persistent exec sessions are unavailable on this platform")
    }

    var isRunning: Bool { false }
    var exitCode: Int32? { nil }

    func write(_ chars: String) throws {
        throw ToolError.validationError("Persistent exec sessions are unavailable on this platform")
    }

    func drainNewOutput(maxChars: Int?) -> String {
        ""
    }

    func terminate() {}
}
#endif

private actor CodexExecSessionStore {
    static let shared = CodexExecSessionStore()

    private var sessions: [Int: CodexExecSession] = [:]
    private var nextSessionID: Int = 1

    func create(command: String, shell: String, login: Bool, workingDirectory: String, tty: Bool) throws -> Int {
        let sessionID = nextSessionID
        nextSessionID += 1
        let session = try CodexExecSession(
            command: command,
            shell: shell,
            login: login,
            workingDirectory: workingDirectory,
            tty: tty
        )
        sessions[sessionID] = session
        return sessionID
    }

    func write(sessionId: Int, chars: String) throws {
        guard let session = sessions[sessionId] else {
            throw ToolError.validationError("Session \(sessionId) not found")
        }
        try session.write(chars)
    }

    func read(
        sessionId: Int,
        waitMs: Int,
        maxChars: Int?,
        onChunk: StreamingToolOutputEmitter
    ) async throws -> CodexExecSnapshot {
        guard let session = sessions[sessionId] else {
            throw ToolError.validationError("Session \(sessionId) not found")
        }

        let deadline = Date().addingTimeInterval(Double(waitMs) / 1000.0)
        var output = session.drainNewOutput(maxChars: nil)
        if !output.isEmpty {
            await onChunk(output)
        }

        while session.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let chunk = session.drainNewOutput(maxChars: nil)
            if !chunk.isEmpty {
                output += chunk
                await onChunk(chunk)
            }
        }

        if !session.isRunning {
            let chunk = session.drainNewOutput(maxChars: nil)
            if !chunk.isEmpty {
                output += chunk
                await onChunk(chunk)
            }
        }

        var truncatedByMaxOutputTokens = false
        var truncatedCharCount = 0
        if let maxChars, output.count > maxChars {
            truncatedByMaxOutputTokens = true
            truncatedCharCount = output.count - maxChars
            output = String(output.suffix(maxChars))
        }

        let snapshot = CodexExecSnapshot(
            output: output,
            running: session.isRunning,
            exitCode: session.exitCode,
            truncatedByMaxOutputTokens: truncatedByMaxOutputTokens,
            truncatedCharCount: truncatedCharCount
        )

        if !snapshot.running {
            session.terminate()
            sessions.removeValue(forKey: sessionId)
        }

        return snapshot
    }
}

private func codexExecSnapshotText(sessionId: Int, snapshot: CodexExecSnapshot) -> String {
    let renderedOutput = snapshot.output.isEmpty ? "(no output)" : snapshot.output
    let truncationWarning: String = snapshot.truncatedByMaxOutputTokens
        ? "\n\n[WARNING: Tool output was truncated by max_output_tokens. \(snapshot.truncatedCharCount) characters were removed from the beginning.]"
        : ""
    if snapshot.running {
        return """
        Session ID: \(sessionId)
        Status: running

        Output:
        \(renderedOutput)\(truncationWarning)
        """
    }
    return """
    Status: completed
    Exit code: \(snapshot.exitCode ?? 0)

    Output:
    \(renderedOutput)\(truncationWarning)
    """
}

private func codexFormatExecOutput(result: ExecResult, timeoutMs: Int) -> String {
    var output = result.combinedOutput
    if result.timedOut {
        output += "\n\n[ERROR: Command timed out after \(timeoutMs)ms.]"
    }
    if result.exitCode != 0 && !result.timedOut {
        output += "\n[Exit code: \(result.exitCode)]"
    }
    output += "\n[Duration: \(result.durationMs)ms]"
    return output
}

private struct CodexGitCloneRequest: Sendable {
    let url: String
    let destination: String
    let branch: String?
}

private func codexShellSplit(_ command: String) -> [String]? {
    var tokens: [String] = []
    var current = ""
    var inSingleQuote = false
    var inDoubleQuote = false
    var isEscaping = false

    for character in command {
        if isEscaping {
            current.append(character)
            isEscaping = false
            continue
        }

        switch character {
        case "\\":
            if inSingleQuote {
                current.append(character)
            } else {
                isEscaping = true
            }
        case "'":
            if inDoubleQuote {
                current.append(character)
            } else {
                inSingleQuote.toggle()
            }
        case "\"":
            if inSingleQuote {
                current.append(character)
            } else {
                inDoubleQuote.toggle()
            }
        case " ", "\t", "\n", "\r":
            if inSingleQuote || inDoubleQuote {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }
        case ";", "|", "&", ">", "<", "(", ")":
            if inSingleQuote || inDoubleQuote {
                current.append(character)
            } else {
                return nil
            }
        default:
            current.append(character)
        }
    }

    guard !isEscaping, !inSingleQuote, !inDoubleQuote else {
        return nil
    }

    if !current.isEmpty {
        tokens.append(current)
    }

    return tokens
}

private func codexParseGitCloneRequest(command: String, workingDirectory: String) -> CodexGitCloneRequest? {
    guard let tokens = codexShellSplit(command), !tokens.isEmpty else {
        return nil
    }

    let executable = tokens[0]
    guard executable == "git" || executable == "/usr/bin/git" || executable == "/usr/local/bin/git" else {
        return nil
    }

    var index = 1
    var sawClone = false
    while index < tokens.count {
        switch tokens[index] {
        case "clone":
            sawClone = true
            index += 1
            break
        case "-c", "--config-env", "-C", "--exec-path", "--git-dir", "--work-tree", "--namespace", "--super-prefix":
            guard index + 1 < tokens.count else { return nil }
            index += 2
        case "--bare", "--no-pager", "--paginate", "--literal-pathspecs", "--no-literal-pathspecs",
             "--glob-pathspecs", "--noglob-pathspecs", "--icase-pathspecs", "--no-optional-locks",
             "--no-replace-objects":
            index += 1
        default:
            index = tokens.count
        }

        if sawClone {
            break
        }
    }

    guard sawClone else {
        return nil
    }

    var branch: String?
    while index < tokens.count {
        switch tokens[index] {
        case "-b", "--branch":
            guard index + 1 < tokens.count else { return nil }
            branch = tokens[index + 1]
            index += 2
        case "--depth":
            guard index + 1 < tokens.count else { return nil }
            index += 2
        case "--single-branch", "--progress", "--quiet", "-q":
            index += 1
        case "--":
            index += 1
            break
        case let option where option.hasPrefix("-"):
            return nil
        default:
            let url = tokens[index]
            guard url.hasPrefix("https://github.com/") || url.hasPrefix("http://github.com/") else {
                return nil
            }

            let repoName = url
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .split(separator: "/")
                .last
                .map(String.init)?
                .replacingOccurrences(of: ".git", with: "") ?? "repo"

            let destinationToken = index + 1 < tokens.count ? tokens[index + 1] : repoName
            guard index + 2 >= tokens.count else { return nil }
            let destination = destinationToken.hasPrefix("/")
                ? destinationToken
                : (workingDirectory as NSString).appendingPathComponent(destinationToken)
            return CodexGitCloneRequest(url: url, destination: destination, branch: branch)
        }
    }

    return nil
}

private func codexResolveDefaultGitHubBranch(for url: String) async -> String? {
    guard let components = URLComponents(string: url) else {
        return nil
    }

    let pathParts = components.path.split(separator: "/").map(String.init)
    guard pathParts.count >= 2 else {
        return nil
    }

    let owner = pathParts[0]
    let repo = pathParts[1].replacingOccurrences(of: ".git", with: "")
    guard let apiURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)") else {
        return nil
    }

    do {
        let (data, response) = try await URLSession.shared.data(from: apiURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let branch = object["default_branch"] as? String,
              !branch.isEmpty
        else {
            return nil
        }
        return branch
    } catch {
        return nil
    }
}

private func codexRunGuestCommand(
    env: ExecutionEnvironment,
    command: String,
    timeoutMs: Int,
    workdir: String,
    emitOutputDelta: StreamingToolOutputEmitter
) async throws -> ExecResult {
    let result = try await env.execCommand(
        command: command,
        timeoutMs: timeoutMs,
        workingDir: workdir,
        envVars: nil
    )
    let combinedOutput = result.combinedOutput
    if !combinedOutput.isEmpty {
        await emitOutputDelta(combinedOutput)
        if !combinedOutput.hasSuffix("\n") {
            await emitOutputDelta("\n")
        }
    }
    guard result.exitCode == 0, !result.timedOut else {
        throw ToolError.validationError(codexFormatExecOutput(result: result, timeoutMs: timeoutMs))
    }
    return result
}

private func codexExecuteGitHubCloneFallback(
    request: CodexGitCloneRequest,
    env: ExecutionEnvironment,
    timeoutMs: Int,
    workdir: String,
    emitOutputDelta: StreamingToolOutputEmitter
) async throws -> String {
    let start = DispatchTime.now()
    let tempDir = "/tmp/iagentsmith-git-clone-\(UUID().uuidString)"
    let branchCandidates = Array(
        NSOrderedSet(
            array: [
                request.branch,
                await codexResolveDefaultGitHubBranch(for: request.url),
                "main",
                "master",
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        )
    ).compactMap { $0 as? String }

    let destinationEntries = try? await env.listDirectory(path: request.destination, depth: 1)
    if await env.fileExists(path: request.destination), let destinationEntries, !destinationEntries.isEmpty {
        throw ToolError.validationError("destination path '\(request.destination)' already exists and is not an empty directory.")
    }

    await emitOutputDelta("Cloning \(request.url) into \(request.destination) via GitHub snapshot fallback...\n")
    _ = try? await env.execCommand(
        command: codexShellJoin(["rm", "-rf", tempDir]),
        timeoutMs: timeoutMs,
        workingDir: workdir,
        envVars: nil
    )
    try await codexRunGuestCommand(
        env: env,
        command: codexShellJoin(["mkdir", "-p", tempDir]),
        timeoutMs: timeoutMs,
        workdir: workdir,
        emitOutputDelta: emitOutputDelta
    )

    var selectedBranch: String?
    let archivePath = "\(tempDir)/repo.tar.gz"
    for candidate in branchCandidates {
        let archiveURL = "https://codeload.github.com/\(request.url.replacingOccurrences(of: "https://github.com/", with: "").replacingOccurrences(of: "http://github.com/", with: "").replacingOccurrences(of: ".git", with: ""))/tar.gz/refs/heads/\(candidate)"
        let download = try await env.execCommand(
            command: codexShellJoin(["curl", "-L", "--fail", "--silent", "--show-error", archiveURL, "-o", archivePath]),
            timeoutMs: timeoutMs,
            workingDir: workdir,
            envVars: nil
        )
        if download.exitCode == 0 {
            if !download.combinedOutput.isEmpty {
                await emitOutputDelta(download.combinedOutput + (download.combinedOutput.hasSuffix("\n") ? "" : "\n"))
            }
            selectedBranch = candidate
            break
        }
    }

    guard let selectedBranch else {
        throw ToolError.validationError("Unable to download a GitHub snapshot for \(request.url).")
    }

    try await codexRunGuestCommand(
        env: env,
        command: codexShellJoin(["tar", "-xzf", archivePath, "-C", tempDir]),
        timeoutMs: timeoutMs,
        workdir: workdir,
        emitOutputDelta: emitOutputDelta
    )

    let extractedEntries = try await env.listDirectory(path: tempDir, depth: 1)
    guard let extractedDirName = extractedEntries.first(where: \.isDir)?.name else {
        throw ToolError.validationError("Unable to unpack repository archive for \(request.url).")
    }
    let extractedDir = "\(tempDir)/\(extractedDirName)"

    try await codexRunGuestCommand(
        env: env,
        command: codexShellJoin(["mkdir", "-p", request.destination]),
        timeoutMs: timeoutMs,
        workdir: workdir,
        emitOutputDelta: emitOutputDelta
    )
    try await codexRunGuestCommand(
        env: env,
        command: codexShellJoin(["cp", "-R", "\(extractedDir)/.", "\(request.destination)/"]),
        timeoutMs: timeoutMs,
        workdir: workdir,
        emitOutputDelta: emitOutputDelta
    )

    let gitPath = "/usr/bin/git"
    let gitCommands: [[String]] = [
        [gitPath, "-C", request.destination, "init", "-q", "--template=/tmp/iagentsmith-empty-git-template"],
        [gitPath, "-C", request.destination, "config", "user.name", "iAgentSmith"],
        [gitPath, "-C", request.destination, "config", "user.email", "local@iagentsmith.invalid"],
        [gitPath, "-C", request.destination, "add", "-A"],
        [gitPath, "-C", request.destination, "commit", "-q", "-m", "Snapshot imported from \(request.url)"],
    ]
    for gitCommand in gitCommands {
        try await codexRunGuestCommand(
            env: env,
            command: codexShellJoin(gitCommand),
            timeoutMs: timeoutMs,
            workdir: workdir,
            emitOutputDelta: emitOutputDelta
        )
    }
    _ = try? await env.execCommand(
        command: codexShellJoin([gitPath, "-C", request.destination, "branch", "-M", selectedBranch]),
        timeoutMs: timeoutMs,
        workingDir: workdir,
        envVars: nil
    )
    _ = try? await env.execCommand(
        command: codexShellJoin([gitPath, "-C", request.destination, "remote", "add", "origin", request.url]),
        timeoutMs: timeoutMs,
        workingDir: workdir,
        envVars: nil
    )
    _ = try? await env.execCommand(
        command: codexShellJoin(["rm", "-rf", tempDir]),
        timeoutMs: timeoutMs,
        workingDir: workdir,
        envVars: nil
    )

    let topLevelEntries = (try? await env.listDirectory(path: request.destination, depth: 1)) ?? []
    let topLevelListing = topLevelEntries
        .sorted { $0.name < $1.name }
        .map { $0.isDir ? "\($0.name)/" : $0.name }
        .joined(separator: "\n")
    let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
    let durationMs = Int(elapsed / 1_000_000)

    return codexFormatExecOutput(
        result: ExecResult(
            stdout: """
Cloned \(request.url) into \(request.destination) via GitHub snapshot fallback.
Branch: \(selectedBranch)
\(topLevelListing.isEmpty ? "Top-level files: (empty)" : "Top-level files:\n\(topLevelListing)")
""",
            stderr: "",
            exitCode: 0,
            timedOut: false,
            durationMs: durationMs
        ),
        timeoutMs: timeoutMs
    )
}

private func codexShouldUseGitHubCloneFallback() -> Bool {
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    #if targetEnvironment(simulator)
    false
    #else
    true
    #endif
    #else
    false
    #endif
}

private func codexExecuteCommand(
    env: ExecutionEnvironment,
    command: String,
    timeoutMs: Int,
    workdir: String?,
    emitOutputDelta: StreamingToolOutputEmitter
) async throws -> String {
    let resolvedWorkdir = workdir ?? env.workingDirectory()
    if codexShouldUseGitHubCloneFallback(),
       let gitCloneRequest = codexParseGitCloneRequest(command: command, workingDirectory: resolvedWorkdir) {
        return try await codexExecuteGitHubCloneFallback(
            request: gitCloneRequest,
            env: env,
            timeoutMs: timeoutMs,
            workdir: resolvedWorkdir,
            emitOutputDelta: emitOutputDelta
        )
    }
    let result = try await env.execCommand(command: command, timeoutMs: timeoutMs, workingDir: workdir, envVars: nil)
    let combinedOutput = result.combinedOutput
    if !combinedOutput.isEmpty {
        await emitOutputDelta(combinedOutput)
    }
    return codexFormatExecOutput(result: result, timeoutMs: timeoutMs)
}

private func codexScriptPath() -> String? {
    let candidates = ["/usr/bin/script", "/bin/script"]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

private func codexIntValue(_ raw: Any?) -> Int? {
    switch raw {
    case let value as Int:
        return value
    case let value as Double:
        return Int(value)
    case let value as NSNumber:
        return value.intValue
    default:
        return nil
    }
}

private func codexBoolValue(_ raw: Any?) -> Bool? {
    switch raw {
    case let value as Bool:
        return value
    case let value as NSNumber:
        return value.boolValue
    default:
        return nil
    }
}

private func codexStringArray(_ raw: Any?) -> [String]? {
    if let strings = raw as? [String] {
        return strings
    }
    if let array = raw as? [Any] {
        let strings = array.compactMap { $0 as? String }
        return strings.count == array.count ? strings : nil
    }
    return nil
}

private func codexShellJoin(_ argv: [String]) -> String {
    argv.map(codexShellEscape).joined(separator: " ")
}

private func codexShellEscape(_ value: String) -> String {
    if value.isEmpty {
        return "''"
    }
    return "'" + value.replacing("'", with: "'\\''") + "'"
}

private func codexResolvePath(_ path: String, env: ExecutionEnvironment) -> String {
    if path.hasPrefix("/") {
        return path
    }
    return (env.workingDirectory() as NSString).appendingPathComponent(path)
}

private func codexUniqueMatchedFiles(from grepOutput: String, limit: Int) -> [String] {
    let trimmed = grepOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != "No matches found." else {
        return []
    }

    var files: [String] = []
    var seen: Set<String> = []

    for line in trimmed.split(separator: "\n") {
        let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard let firstPart = parts.first else { continue }
        let path = String(firstPart)
        guard !path.isEmpty, seen.insert(path).inserted else { continue }
        files.append(path)
        if files.count >= limit {
            break
        }
    }

    return files
}
