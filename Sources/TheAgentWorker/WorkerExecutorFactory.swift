import Foundation
import OmniAIAttractor
import OmniAgentMesh

public enum WorkerACPProfile: String, CaseIterable, Sendable {
    case codex
    case claude
    case gemini

    public init?(cliValue: String) {
        switch cliValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "codex":
            self = .codex
        case "claude", "claude-code", "claudecode":
            self = .claude
        case "gemini":
            self = .gemini
        default:
            return nil
        }
    }

    public var capabilityLabel: String {
        "acp-\(rawValue)"
    }

    fileprivate var defaultModel: String {
        switch self {
        case .codex:
            return "gpt-5.3-codex"
        case .claude:
            return "claude-opus-4-6"
        case .gemini:
            return "gemini-3.1-pro-preview-customtools"
        }
    }

    fileprivate var provider: String {
        switch self {
        case .codex:
            return "openai"
        case .claude:
            return "anthropic"
        case .gemini:
            return "gemini"
        }
    }

    fileprivate func makeProfile(
        model: String?,
        reasoningEffort: String,
        configuration: ACPBackendConfiguration
    ) -> ACPWorkerProfile {
        let resolvedModel = model ?? defaultModel
        switch self {
        case .codex:
            return .codex(
                model: resolvedModel,
                reasoningEffort: reasoningEffort,
                configuration: configuration
            )
        case .claude:
            return .claude(
                model: resolvedModel,
                reasoningEffort: reasoningEffort,
                configuration: configuration
            )
        case .gemini:
            return .gemini(
                model: resolvedModel,
                reasoningEffort: reasoningEffort,
                configuration: configuration
            )
        }
    }
}

public struct ACPWorkerRuntimeOptions: Sendable {
    public var profile: WorkerACPProfile
    public var model: String?
    public var reasoningEffort: String
    public var agentPath: String?
    public var agentArguments: [String]
    public var workingDirectory: String?
    public var modeID: String?
    public var requestTimeout: Duration?

    public init(
        profile: WorkerACPProfile = .codex,
        model: String? = nil,
        reasoningEffort: String = "high",
        agentPath: String? = nil,
        agentArguments: [String] = [],
        workingDirectory: String? = nil,
        modeID: String? = nil,
        requestTimeout: Duration? = nil
    ) {
        self.profile = profile
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.agentPath = agentPath
        self.agentArguments = agentArguments
        self.workingDirectory = workingDirectory
        self.modeID = modeID
        self.requestTimeout = requestTimeout
    }
}

public struct AttractorWorkerRuntimeOptions: Sendable {
    public var provider: String
    public var model: String
    public var reasoningEffort: String
    public var workingDirectory: String?
    public var logsRoot: String?
    public var defaultHumanTimeoutSeconds: Double
    public var backend: (any CodergenBackend)?

    public init(
        provider: String = "openai",
        model: String = "gpt-5.2-codex",
        reasoningEffort: String = "high",
        workingDirectory: String? = nil,
        logsRoot: String? = nil,
        defaultHumanTimeoutSeconds: Double = 600,
        backend: (any CodergenBackend)? = nil
    ) {
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.workingDirectory = workingDirectory
        self.logsRoot = logsRoot
        self.defaultHumanTimeoutSeconds = max(1, defaultHumanTimeoutSeconds)
        self.backend = backend
    }
}

public enum WorkerExecutionMode: Sendable {
    case local
    case acp(ACPWorkerRuntimeOptions)
    case attractor(AttractorWorkerRuntimeOptions)
}

public enum WorkerExecutorFactory {
    public static func makeExecutor(
        mode: WorkerExecutionMode,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        toolRegistry: ToolRegistry? = nil,
        transportProvider: any ACPTransportProvider = DefaultACPTransportProvider(),
        delegateProvider: any ACPClientDelegateProvider = DefaultACPClientDelegateProvider(),
        interactionBridge: (any WorkerInteractionBridge)? = nil
    ) -> LocalTaskExecutor {
        switch mode {
        case .local:
            return LocalTaskExecutor()
        case .acp(let options):
            let configuration = ACPBackendConfiguration(
                agentPath: options.agentPath,
                agentArguments: options.agentArguments,
                workingDirectory: options.workingDirectory,
                requestTimeout: options.requestTimeout,
                modeID: options.modeID
            )
            let profile = options.profile.makeProfile(
                model: options.model,
                reasoningEffort: options.reasoningEffort,
                configuration: configuration
            )
            let session = ACPWorkerSession(
                toolRegistry: toolRegistry,
                transportProvider: transportProvider,
                delegateProvider: delegateProvider,
                environment: environment
            )
            let executor = ACPExecutor(session: session)
            return executor.makeLocalTaskExecutor(
                profile: profile,
                workingDirectory: options.workingDirectory ?? FileManager.default.currentDirectoryPath
            )
        case .attractor(let options):
            let workingDirectory = options.workingDirectory ?? FileManager.default.currentDirectoryPath
            let logsRoot = URL(fileURLWithPath: options.logsRoot ?? workingDirectory, isDirectory: true)
                .appending(path: ".ai/attractor-runs", directoryHint: .isDirectory)
            let backend = options.backend ?? CodingAgentBackend(workingDirectory: workingDirectory)
            let executor = AttractorTaskExecutor(
                workflowTemplate: AttractorWorkflowTemplate(
                    provider: options.provider,
                    model: options.model,
                    reasoningEffort: options.reasoningEffort
                ),
                backend: backend,
                workingDirectory: workingDirectory,
                logsRoot: logsRoot,
                interactionBridge: interactionBridge,
                defaultHumanTimeoutSeconds: options.defaultHumanTimeoutSeconds
            )
            return executor.makeLocalTaskExecutor()
        }
    }

    public static func augmentCapabilities(
        _ baseCapabilities: [String],
        mode: WorkerExecutionMode
    ) -> [String] {
        switch mode {
        case .local:
            return Array(Set(baseCapabilities)).sorted()
        case .acp(let options):
            return Array(
                Set(baseCapabilities)
                    .union(["acp", options.profile.capabilityLabel])
            ).sorted()
        case .attractor:
            return Array(
                Set(baseCapabilities)
                    .union(["execution:attractor", "workflow:plan-implement-validate"])
            ).sorted()
        }
    }

    public static func metadata(for mode: WorkerExecutionMode) -> [String: String] {
        switch mode {
        case .local:
            return ["execution_mode": "local"]
        case .acp(let options):
            return [
                "execution_mode": "acp",
                "acp_profile": options.profile.rawValue,
                "acp_provider": options.profile.provider,
                "acp_model": options.model ?? options.profile.defaultModel,
                "acp_reasoning_effort": options.reasoningEffort,
            ]
        case .attractor(let options):
            return [
                "execution_mode": "attractor",
                "attractor_provider": options.provider,
                "attractor_model": options.model,
                "attractor_reasoning_effort": options.reasoningEffort,
            ]
        }
    }

    public static func startupDescription(for mode: WorkerExecutionMode) -> String? {
        switch mode {
        case .local:
            return nil
        case .acp(let options):
            let model = options.model ?? options.profile.defaultModel
            return "using \(options.profile.rawValue) ACP executor (\(model))"
        case .attractor(let options):
            return "using attractor workflow executor (\(options.provider)/\(options.model))"
        }
    }
}
