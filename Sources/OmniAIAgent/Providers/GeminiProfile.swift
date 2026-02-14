import Foundation
import OmniAICore

public final class GeminiProfile: ProviderProfile, @unchecked Sendable {
    public let id: String = "gemini"
    public let model: String
    public let toolRegistry: ToolRegistry

    public let supportsReasoning: Bool = true
    public let supportsStreaming: Bool = true
    public let supportsParallelToolCalls: Bool = true
    public let contextWindowSize: Int = 1_000_000

    public init(model: String = "gemini-3-flash-preview", session: Session? = nil) {
        self.model = model
        self.toolRegistry = ToolRegistry()

        toolRegistry.register(readFileTool())
        toolRegistry.register(readManyFilesTool())
        toolRegistry.register(writeFileTool())
        toolRegistry.register(editFileTool())
        toolRegistry.register(shellTool(defaultTimeoutMs: 10_000))
        toolRegistry.register(grepTool())
        toolRegistry.register(globTool())
        toolRegistry.register(listDirTool())
        toolRegistry.register(webSearchTool())
        toolRegistry.register(webFetchTool())

        if let session = session {
            toolRegistry.register(spawnAgentTool(parentSession: session))
            toolRegistry.register(sendInputTool(parentSession: session))
            toolRegistry.register(waitTool(parentSession: session))
            toolRegistry.register(closeAgentTool(parentSession: session))
        }
    }

    public func buildSystemPrompt(environment: ExecutionEnvironment, projectDocs: String?, userInstructions: String? = nil, gitContext: GitContext? = nil) -> String {
        let toolNames = toolRegistry.names().sorted().joined(separator: ", ")

        var parts: [String] = []

        // Gemini-specific identity and guidance
        parts.append("""
        You are a coding assistant powered by Gemini. You help users with software engineering tasks \
        including writing code, debugging, refactoring, explaining code, running commands, and managing files.

        # Tool Usage
        You have access to these tools: \(toolNames)

        Guidelines:
        - Use tools to explore the codebase before making changes. Read files before editing them.
        - Use `list_dir` to understand project structure before diving into specific files. Start with a broad overview.
        - Use `read_many_files` to read multiple files in a single call when you need context from several files.
        - Use `grep` to search for patterns across the codebase.
        - Use `glob` to find files matching a pattern.
        - Use `shell` to run build commands, tests, linters, and other CLI tools. Default timeout is 10 seconds.
        - Use `edit_file` for surgical edits to existing files. The `old_string` must exactly match existing content.
        - Use `write_file` only for creating new files or when you need to rewrite an entire file.
        - Use `web_search` to search the web for documentation, APIs, or solutions.
        - Use `web_fetch` to fetch content from a specific URL.
        - Always use absolute file paths.
        - When running shell commands, prefer short-lived commands. Set appropriate timeouts for long-running operations.

        # GEMINI.md Conventions
        If the project contains a GEMINI.md or AGENTS.md file, follow the instructions and conventions defined there. \
        These files contain project-specific guidelines that take precedence over general defaults.

        # Coding Best Practices
        - Write clean, readable, idiomatic code following the project's existing style.
        - Prefer editing existing files over creating new ones to avoid file bloat.
        - Do not add unnecessary comments, docstrings, or type annotations to code you did not change.
        - Do not over-engineer solutions. Keep changes minimal and focused on the task.
        - Run tests after making changes to verify correctness.
        - Do not introduce security vulnerabilities (injection, XSS, etc.).
        """)

        // Environment context block
        var envLines: [String] = []
        envLines.append("Platform: \(environment.platform())")
        envLines.append("OS: \(environment.osVersion())")
        envLines.append("Working directory: \(environment.workingDirectory())")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        envLines.append("Today's date: \(dateFormatter.string(from: Date()))")
        envLines.append("Model: \(model)")
        envLines.append("Knowledge cutoff: \(knowledgeCutoff())")

        if let git = gitContext {
            envLines.append("Is git repository: true")
            if let branch = git.branch {
                envLines.append("Git branch: \(branch)")
            }
            envLines.append("Modified files: \(git.modifiedFileCount)")
            if let commits = git.recentCommits, !commits.isEmpty {
                envLines.append("Recent commits:\n\(commits)")
            }
        } else {
            envLines.append("Is git repository: false")
        }

        parts.append("<environment>\n\(envLines.joined(separator: "\n"))\n</environment>")

        if let docs = projectDocs {
            parts.append("# Project Documentation\n\(docs)")
        }

        // User instructions override (highest priority, appended last)
        if let instructions = userInstructions, !instructions.isEmpty {
            parts.append("""
            # User Instructions

            \(instructions)
            """)
        }

        return parts.joined(separator: "\n\n")
    }

    private func knowledgeCutoff() -> String {
        if model.contains("gemini") {
            return "March 2025"
        }
        return "Check with current date for recency"
    }

    public func providerOptions() -> [String: JSONValue]? {
        return nil
    }
}
