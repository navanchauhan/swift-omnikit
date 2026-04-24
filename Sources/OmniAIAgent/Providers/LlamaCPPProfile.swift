import Foundation
import OmniAICore

public final class LlamaCPPProfile: ProviderProfile, @unchecked Sendable {
    public let id = "llamacpp"
    public let model: String
    public let toolRegistry: ToolRegistry
    private let forceCodexSystemPrompt: Bool

    public let supportsReasoning = true
    public let supportsStreaming = false
    public let supportsPreviousResponseId = false
    public let supportsParallelToolCalls = true
    public let contextWindowSize = 200_000

    public enum ShellType: Sendable {
        case shell
        case shellCommand
        case disabled
    }

    public init(
        model: String = "qwopus-local",
        session: Session? = nil,
        shellType: ShellType = .shellCommand,
        includeApplyPatch: Bool = true,
        useUnifiedExec: Bool = true,
        includeCollabTools: Bool = false,
        forceCodexSystemPrompt: Bool = false
    ) {
        self.model = model
        self.forceCodexSystemPrompt = forceCodexSystemPrompt

        let registry = ToolRegistry()
        if useUnifiedExec {
            registry.register(execCommandTool())
            registry.register(writeStdinTool())
        } else {
            switch shellType {
            case .shell:
                registry.register(codexShellTool(defaultTimeoutMs: 10_000))
            case .shellCommand:
                registry.register(shellCommandTool(defaultTimeoutMs: 10_000))
            case .disabled:
                break
            }
        }

        registry.register(codexReadFileTool())
        registry.register(grepFilesTool())
        registry.register(globTool())
        registry.register(codexListDirTool())
        registry.register(updatePlanTool())
        registry.register(viewImageTool())
        if includeApplyPatch {
            registry.register(applyPatchTool())
        }

        if includeCollabTools, let session {
            registry.register(codexSpawnAgentTool(parentSession: session))
            registry.register(codexSendInputTool(parentSession: session))
            registry.register(codexWaitTool(parentSession: session))
            registry.register(codexCloseAgentTool(parentSession: session))
        }

        self.toolRegistry = registry
    }

    public func buildSystemPrompt(environment: ExecutionEnvironment, projectDocs: String?, userInstructions: String? = nil, gitContext: GitContext? = nil) -> String {
        let basePrompt: String
        if forceCodexSystemPrompt {
            basePrompt = CodexSystemPrompt.prompt(for: model)
        } else if let localPrompt = LocalOrchestratorSystemPrompt.prompt(for: model) {
            basePrompt = localPrompt
        } else {
            basePrompt = CodexSystemPrompt.openAIPrompt(for: model)
        }
        let workingDir = environment.workingDirectory()
        let envContext = """

# Environment Context

- Working directory: \(workingDir)
- When using shell tools, use "." or "\(workingDir)" for the workdir parameter, not "/workspace"
- Platform: \(environment.platform()) \(environment.osVersion())
"""
        var sections: [String] = [basePrompt + envContext]

        if let projectDocs, !projectDocs.isEmpty {
            sections.append("""
# Project Documentation
\(projectDocs)
""")
        }

        if let userInstructions, !userInstructions.isEmpty {
            sections.append("""
# User Instructions
\(userInstructions)
""")
        }

        return sections.joined(separator: "\n\n")
    }

    public func providerOptions() -> [String: JSONValue]? {
        [
            id: .object([
                OpenAIProviderOptionKeys.responsesTransport: .string("sse"),
            ]),
        ]
    }
}
