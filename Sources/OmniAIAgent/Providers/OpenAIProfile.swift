import Foundation
import OmniAICore

public final class OpenAIProfile: ProviderProfile, @unchecked Sendable {
    public let id = "openai"
    public let model: String
    public let toolRegistry: ToolRegistry
    private let includeNativeWebSearch: Bool
    private let webSearchExternalWebAccess: Bool?
    private let forceCodexSystemPrompt: Bool
    private let disablePreviousResponseId: Bool
    public let supportsReasoning = true
    public let supportsStreaming: Bool
    public let supportsPreviousResponseId: Bool
    public let supportsParallelToolCalls = true
    public let contextWindowSize = 200_000

    public enum ShellType: Sendable {
        case shell
        case shellCommand
        case disabled
    }

    public init(
        model: String = "gpt-5.4",
        session: Session? = nil,
        shellType: ShellType = .shellCommand,
        includeApplyPatch: Bool = true,
        useUnifiedExec: Bool = true,
        includeCollabTools: Bool = false,
        includeWebSearch: Bool = false,
        webSearchExternalWebAccess: Bool? = true,
        forceCodexSystemPrompt: Bool = false,
        disablePreviousResponseId: Bool = false,
        supportsPreviousResponseId: Bool? = nil
    ) {
        self.model = model
        self.includeNativeWebSearch = includeWebSearch
        self.webSearchExternalWebAccess = webSearchExternalWebAccess
        self.forceCodexSystemPrompt = forceCodexSystemPrompt
        self.disablePreviousResponseId = disablePreviousResponseId
        self.supportsStreaming = Self.defaultSupportsStreaming()
        self.supportsPreviousResponseId = (supportsPreviousResponseId ?? Self.defaultSupportsPreviousResponseId(model: model)) && !disablePreviousResponseId

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
        if Self.supportsImageInputs(model: model) {
            registry.register(viewImageTool())
        }
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
        let workdirGuidance: String
        if workingDir == "/workspace" {
            workdirGuidance = "When using shell tools, use \".\" or \"/workspace\" for the workdir parameter."
        } else {
            workdirGuidance = "When using shell tools, use \".\" or \"\(workingDir)\" for the workdir parameter, not \"/workspace\""
        }
        let envContext = """

# Environment Context

- Working directory: \(workingDir)
- \(workdirGuidance)
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
        var options: [String: JSONValue] = [
            OpenAIProviderOptionKeys.responsesTransport: .string(OpenAIProviderOptionKeys.preferredResponsesTransport),
        ]

        if includeNativeWebSearch {
            options[OpenAIProviderOptionKeys.includeNativeWebSearch] = .bool(true)
        }
        if let webSearchExternalWebAccess {
            options[OpenAIProviderOptionKeys.webSearchExternalWebAccess] = .bool(webSearchExternalWebAccess)
        }
        if disablePreviousResponseId {
            options[OpenAIProviderOptionKeys.disablePreviousResponseId] = .bool(true)
        }
        return [id: .object(options)]
    }
}

private extension OpenAIProfile {
    static func defaultSupportsStreaming(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        true
    }

    static func defaultSupportsPreviousResponseId(model: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if model.lowercased().contains("codex") {
            return false
        }
        guard let baseURL = environment["OPENAI_BASE_URL"], !baseURL.isEmpty else {
            return true
        }
        guard let components = URLComponents(string: baseURL),
              let host = components.host?.lowercased() else {
            return false
        }
        return host == "api.openai.com" || host.hasSuffix(".openai.com")
    }

    static func isCodexChatGPTAuthEnabled(environment: [String: String]) -> Bool {
        for key in ["OMNIKIT_USE_CODEX_CHATGPT_AUTH", "THE_AGENT_USE_CODEX_CHATGPT_AUTH"] {
            let normalized = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "on"].contains(normalized) {
                return true
            }
        }
        return false
    }

    static func supportsImageInputs(model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.contains("codex-spark")
    }
}
