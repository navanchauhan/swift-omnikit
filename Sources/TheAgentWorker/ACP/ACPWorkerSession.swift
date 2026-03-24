import Foundation
import OmniAIAttractor
import OmniAgentMesh
import OmniACPModel

public struct ACPWorkerProfile: Sendable {
    public var profileID: String
    public var preset: ACPBackendPreset
    public var provider: String
    public var model: String
    public var reasoningEffort: String
    public var configuration: ACPBackendConfiguration

    public init(
        profileID: String,
        preset: ACPBackendPreset,
        provider: String,
        model: String,
        reasoningEffort: String = "high",
        configuration: ACPBackendConfiguration = ACPBackendConfiguration()
    ) {
        self.profileID = profileID
        self.preset = preset
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.configuration = configuration
    }

    public static func codex(
        model: String = "gpt-5.3-codex",
        reasoningEffort: String = "high",
        configuration: ACPBackendConfiguration = ACPBackendConfiguration()
    ) -> ACPWorkerProfile {
        ACPWorkerProfile(
            profileID: "codex",
            preset: .codex,
            provider: "openai",
            model: model,
            reasoningEffort: reasoningEffort,
            configuration: configuration
        )
    }

    public static func claude(
        model: String = "claude-opus-4-6",
        reasoningEffort: String = "high",
        configuration: ACPBackendConfiguration = ACPBackendConfiguration()
    ) -> ACPWorkerProfile {
        ACPWorkerProfile(
            profileID: "claude",
            preset: .claudeCode,
            provider: "anthropic",
            model: model,
            reasoningEffort: reasoningEffort,
            configuration: configuration
        )
    }

    public static func gemini(
        model: String = "gemini-3.1-pro-preview-customtools",
        reasoningEffort: String = "high",
        configuration: ACPBackendConfiguration = ACPBackendConfiguration()
    ) -> ACPWorkerProfile {
        ACPWorkerProfile(
            profileID: "gemini",
            preset: .gemini,
            provider: "gemini",
            model: model,
            reasoningEffort: reasoningEffort,
            configuration: configuration
        )
    }
}

public struct ACPWorkerExecutionResult: Sendable, Equatable {
    public var profileID: String
    public var response: String
    public var notes: String
    public var contextUpdates: [String: String]
    public var toolServerNames: [String]

    public init(
        profileID: String,
        response: String,
        notes: String,
        contextUpdates: [String: String],
        toolServerNames: [String]
    ) {
        self.profileID = profileID
        self.response = response
        self.notes = notes
        self.contextUpdates = contextUpdates
        self.toolServerNames = toolServerNames
    }
}

public actor ACPWorkerSession {
    private let toolRegistry: ToolRegistry?
    private let transportProvider: any ACPTransportProvider
    private let delegateProvider: any ACPClientDelegateProvider
    private let environment: [String: String]

    public init(
        toolRegistry: ToolRegistry? = nil,
        transportProvider: any ACPTransportProvider = DefaultACPTransportProvider(),
        delegateProvider: any ACPClientDelegateProvider = DefaultACPClientDelegateProvider(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.toolRegistry = toolRegistry
        self.transportProvider = transportProvider
        self.delegateProvider = delegateProvider
        self.environment = environment
    }

    public func run(
        task: TaskRecord,
        profile: ACPWorkerProfile,
        workingDirectory: String
    ) async throws -> ACPWorkerExecutionResult {
        let toolServerName = "\(profile.profileID)-worker-tools"
        let mcpServers: [OmniACPModel.MCPServer] = if let toolRegistry {
            await toolRegistry.makeACPServers(serverName: toolServerName)
        } else {
            []
        }

        var configuration = profile.preset.makeConfiguration(
            overrides: profile.configuration,
            environment: environment
        )
        if configuration.workingDirectory == nil {
            configuration.workingDirectory = workingDirectory
        }
        configuration.mcpServers = mcpServers

        let backend = ACPAgentBackend(
            configuration: configuration,
            transportProvider: transportProvider,
            delegateProvider: delegateProvider
        )
        let result = try await backend.run(
            prompt: prompt(for: task),
            model: profile.model,
            provider: profile.provider,
            reasoningEffort: profile.reasoningEffort,
            context: context(for: task)
        )
        return ACPWorkerExecutionResult(
            profileID: profile.profileID,
            response: result.response,
            notes: result.notes,
            contextUpdates: result.contextUpdates,
            toolServerNames: mcpServers.map(\.name)
        )
    }

    private func context(for task: TaskRecord) -> PipelineContext {
        let projection = task.historyProjection
        let context = PipelineContext([
            "_graph_goal": projection.taskBrief,
            "task.id": task.taskID,
            "task.root_session_id": task.rootSessionID,
            "task.parent_task_id": task.parentTaskID ?? "",
        ])
        if !projection.expectedOutputs.isEmpty {
            context.set("task.expected_outputs", projection.expectedOutputs.joined(separator: ", "))
        }
        if !projection.constraints.isEmpty {
            context.set("task.constraints", projection.constraints.joined(separator: "\n"))
        }
        return context
    }

    private func prompt(for task: TaskRecord) -> String {
        let projection = task.historyProjection
        var sections: [String] = [
            "You are executing a delegated durable worker task.",
            "Task ID: \(task.taskID)",
            "Task brief:\n\(projection.taskBrief)",
        ]

        if !projection.summaries.isEmpty {
            sections.append(
                "Relevant summaries:\n" + projection.summaries.map { "- \($0)" }.joined(separator: "\n")
            )
        }
        if !projection.parentExcerpts.isEmpty {
            sections.append(
                "Parent excerpts:\n" + projection.parentExcerpts.map { "- \($0)" }.joined(separator: "\n")
            )
        }
        if !projection.artifactRefs.isEmpty {
            sections.append(
                "Artifact references:\n" + projection.artifactRefs.map { "- \($0)" }.joined(separator: "\n")
            )
        }
        if !projection.constraints.isEmpty {
            sections.append(
                "Constraints:\n" + projection.constraints.map { "- \($0)" }.joined(separator: "\n")
            )
        }
        if !projection.expectedOutputs.isEmpty {
            sections.append(
                "Expected outputs:\n" + projection.expectedOutputs.map { "- \($0)" }.joined(separator: "\n")
            )
        }
        return sections.joined(separator: "\n\n")
    }
}
