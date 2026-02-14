import Foundation
import OmniAICore

public final class AnthropicProfile: ProviderProfile, @unchecked Sendable {

    // MARK: - ProviderProfile

    public let id = "anthropic"
    public let model: String
    public let toolRegistry: ToolRegistry

    public let supportsReasoning = true
    public let supportsStreaming = true
    public let supportsParallelToolCalls = true
    public let contextWindowSize = 200_000

    // MARK: - Init

    public init(model: String = "claude-haiku-4-5-20251001", session: Session? = nil) {
        self.model = model
        self.toolRegistry = ToolRegistry()

        // Core tools
        toolRegistry.register(readFileTool())
        toolRegistry.register(writeFileTool())
        toolRegistry.register(editFileTool())
        toolRegistry.register(shellTool(defaultTimeoutMs: 120_000))
        toolRegistry.register(grepTool())
        toolRegistry.register(globTool())

        // Subagent tools (only when running inside a session)
        if let session = session {
            toolRegistry.register(spawnAgentTool(parentSession: session))
            toolRegistry.register(sendInputTool(parentSession: session))
            toolRegistry.register(waitTool(parentSession: session))
            toolRegistry.register(closeAgentTool(parentSession: session))
        }
    }

    // MARK: - System Prompt

    public func buildSystemPrompt(environment: ExecutionEnvironment, projectDocs: String?, userInstructions: String? = nil, gitContext: GitContext? = nil) -> String {
        var parts: [String] = []

        // Claude-specific identity and guidance
        parts.append("""
        You are Claude, an expert coding assistant made by Anthropic. You help users with software engineering tasks including writing, debugging, refactoring, and explaining code. You are thorough, careful, and always verify your understanding before making changes.

        # Tool Usage Guidelines

        - Always read a file before editing it. Never propose changes to code you have not read.
        - Prefer `edit_file` over `write_file` for modifying existing files. Use `write_file` only to create new files.
        - When using `edit_file`, the `old_string` must be unique within the file. Include enough surrounding context to ensure uniqueness. If it matches multiple locations, the edit will fail. Provide a larger context window (more surrounding lines) to disambiguate.
        - Use `grep` and `glob` to explore the codebase before making changes. Understand project structure first.
        - Use `shell` for running tests, builds, git commands, and other system operations. The default timeout is 120 seconds; set `timeout_ms` for long-running commands.
        - Do not guess file contents or project structure. Use tools to verify.
        - Prefer calling multiple tools sequentially rather than assuming the result of a previous call. Verify each step.
        - When making multiple related edits, read the file once, then make all edits. Re-read if the file has changed between edits.

        # Coding Best Practices

        - Write clear, maintainable code that follows the project's existing style and conventions.
        - Keep changes minimal and focused. Only modify what is necessary to accomplish the task.
        - Do not add unnecessary comments, docstrings, or type annotations to code you did not change.
        - Avoid over-engineering: no premature abstractions, feature flags, or backwards-compatibility shims.
        - Validate at system boundaries only; trust internal code and framework guarantees.
        - When fixing bugs, understand the root cause before applying a fix.
        - After making changes, run the project's tests or build to verify correctness.
        - Be careful not to introduce security vulnerabilities (command injection, XSS, SQL injection, etc.).
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

        // Project docs
        if let docs = projectDocs, !docs.isEmpty {
            parts.append("""
            # Project Instructions

            The following project-level instructions were discovered automatically. Follow them.

            \(docs)
            """)
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
        if model.contains("claude") {
            return "Early 2025"
        }
        return "Check with current date for recency"
    }

    // MARK: - Provider Options

    public func providerOptions() -> [String: JSONValue]? {
        return nil
    }
}
