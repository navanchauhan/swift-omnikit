import Foundation
import OmniAILLMClient

public final class OpenAIProfile: ProviderProfile, @unchecked Sendable {
    public let id = "openai"
    public let model: String
    public let toolRegistry: ToolRegistry
    public let supportsReasoning = true
    public let supportsStreaming = true
    public let supportsParallelToolCalls = true
    public let contextWindowSize = 200_000

    public init(model: String = "gpt-5.2", session: Session? = nil) {
        self.model = model

        let registry = ToolRegistry()
        registry.register(readFileTool())
        registry.register(applyPatchTool())
        registry.register(writeFileTool())
        registry.register(shellTool(defaultTimeoutMs: 10_000))
        registry.register(grepTool())
        registry.register(globTool())

        if let session = session {
            registry.register(spawnAgentTool(parentSession: session))
            registry.register(sendInputTool(parentSession: session))
            registry.register(waitTool(parentSession: session))
            registry.register(closeAgentTool(parentSession: session))
        }

        self.toolRegistry = registry
    }

    public func buildSystemPrompt(environment: ExecutionEnvironment, projectDocs: String?, userInstructions: String? = nil, gitContext: GitContext? = nil) -> String {
        var parts: [String] = []

        // GPT-specific identity and guidance
        parts.append("""
        You are a coding agent powered by OpenAI. You have access to tools that let you read files, \
        write files, execute shell commands, and search the codebase. Use these tools \
        to accomplish the user's task.

        You should be thorough and efficient. Read files before modifying them. \
        Use grep/glob to understand the codebase structure. Run tests after making changes. \
        When returning structured output, use well-formed JSON. When calling functions, \
        provide all required parameters and use the correct types.
        """)

        // Tool usage guidelines
        parts.append("""
        # Tool Usage

        - Use `read_file` to read file contents before editing.
        - Use `apply_patch` to make targeted edits using the v4a patch format. This is the preferred editing tool.
        - Use `write_file` to create new files or completely rewrite existing ones.
        - Use `shell` to run commands (build, test, git, etc.). Default timeout is 10 seconds; set `timeout_ms` for longer operations.
        - Use `grep` to search file contents with regex.
        - Use `glob` to find files by pattern.
        - Use absolute file paths in all tool calls.
        """)

        // apply_patch format documentation (GPT-specific: v4a details)
        parts.append("""
        # apply_patch v4a Format

        Use the v4a patch format for targeted file edits. This format is similar to unified diff but uses specific markers:

        ```
        *** Begin Patch
        *** Update File: path/to/file.ext
        @@ context_hint @@
         unchanged line
        -removed line
        +added line
         unchanged line
        *** End Patch
        ```

        To create a new file:
        ```
        *** Begin Patch
        *** Add File: path/to/new_file.ext
        +line 1
        +line 2
        *** End Patch
        ```

        To delete a file:
        ```
        *** Begin Patch
        *** Delete File: path/to/old_file.ext
        *** End Patch
        ```

        To rename/move a file (with optional edits):
        ```
        *** Begin Patch
        *** Update File: old_name.py
        *** Move to: new_name.py
        @@ context
         unchanged
        -old line
        +new line
        *** End Patch
        ```

        Rules:
        - Context lines start with a single space character (not a tab).
        - Removed lines start with `-`.
        - Added lines start with `+`.
        - Include 3 lines of context above and below each change for unambiguous matching.
        - The `@@ hint @@` line helps locate the hunk (use a nearby function name or unique line).
        - Multiple hunks and multiple file operations can be combined in one patch.
        - Hunks are applied top-to-bottom; keep them in file order.
        """)

        // Coding best practices
        parts.append("""
        # Best Practices

        - Read files before editing to understand existing code.
        - Make minimal, targeted changes. Do not refactor unrelated code.
        - Run the build/test suite after making changes to verify correctness.
        - When fixing bugs, understand the root cause before applying a fix.
        - Write clean, idiomatic code that matches the existing style.
        - Do not add unnecessary comments, type annotations, or error handling.
        - Be careful not to introduce security vulnerabilities.
        """)

        // Environment context block
        var envLines: [String] = []
        envLines.append("Working directory: \(environment.workingDirectory())")
        envLines.append("Platform: \(environment.platform())")
        envLines.append("OS version: \(environment.osVersion())")

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

        // Append project docs if available
        if let docs = projectDocs, !docs.isEmpty {
            parts.append("""
            # Project Documentation

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
        if model.contains("gpt") {
            return "April 2025"
        }
        return "Check with current date for recency"
    }

    public func providerOptions() -> [String: [String: AnyCodable]]? {
        return nil
    }
}
