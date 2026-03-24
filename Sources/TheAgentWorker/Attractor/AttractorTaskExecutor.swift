import Foundation
import OmniAIAttractor
import OmniAgentMesh

public enum AttractorTaskExecutorError: Error, CustomStringConvertible {
    case workflowFailed(taskID: String, status: OutcomeStatus, summary: String)

    public var description: String {
        switch self {
        case .workflowFailed(let taskID, let status, let summary):
            return "Attractor workflow for task \(taskID) ended with \(status.rawValue): \(summary)"
        }
    }
}

public struct AttractorTaskExecutor: Sendable {
    public var workflowTemplate: AttractorWorkflowTemplate
    public var backend: any CodergenBackend
    public var workingDirectory: String
    public var logsRoot: URL
    public var interactionBridge: (any WorkerInteractionBridge)?
    public var defaultHumanTimeoutSeconds: Double

    public init(
        workflowTemplate: AttractorWorkflowTemplate = AttractorWorkflowTemplate(),
        backend: any CodergenBackend,
        workingDirectory: String,
        logsRoot: URL,
        interactionBridge: (any WorkerInteractionBridge)? = nil,
        defaultHumanTimeoutSeconds: Double = 600
    ) {
        self.workflowTemplate = workflowTemplate
        self.backend = backend
        self.workingDirectory = workingDirectory
        self.logsRoot = logsRoot
        self.interactionBridge = interactionBridge
        self.defaultHumanTimeoutSeconds = max(1, defaultHumanTimeoutSeconds)
    }

    public func makeLocalTaskExecutor() -> LocalTaskExecutor {
        LocalTaskExecutor { task, reportProgress in
            let progressReporter: LocalTaskProgressReporter = { summary, data in
                try await reportProgress(summary, data)
            }
            return try await execute(task: task, reportProgress: progressReporter)
        }
    }

    public func execute(
        task: TaskRecord,
        reportProgress: @escaping LocalTaskProgressReporter
    ) async throws -> LocalTaskExecutionResult {
        let taskLogsRoot = logsRoot.appending(path: task.taskID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: taskLogsRoot, withIntermediateDirectories: true)

        let dot = workflowTemplate.dot(for: task)
        let workflowFile = taskLogsRoot.appending(path: "workflow.dot")
        try Data(dot.utf8).write(to: workflowFile, options: .atomic)

        try await reportProgress(
            "Launching Attractor workflow",
            [
                "task_id": task.taskID,
                "workflow": "plan-implement-validate",
            ]
        )

        let interviewer: any Interviewer
        if let interactionBridge {
            interviewer = RootBrokerInterviewer(
                task: task,
                bridge: interactionBridge,
                defaultTimeoutSeconds: defaultHumanTimeoutSeconds
            )
        } else {
            interviewer = AutoApproveInterviewer()
        }

        let eventEmitter = PipelineEventEmitter()
        await eventEmitter.onAsync { event in
            guard let summary = Self.progressSummary(for: event) else {
                return
            }
            try? await reportProgress(
                summary,
                Self.progressData(for: event, taskID: task.taskID)
            )
        }

        let result: PipelineResult
        do {
            result = try await PipelineEngine(
                config: PipelineConfig(
                    logsRoot: taskLogsRoot,
                    backend: backend,
                    interviewer: interviewer,
                    eventEmitter: eventEmitter
                )
            ).run(dot: dot)
        } catch {
            try? await reportProgress(
                "Attractor workflow failed",
                [
                    "task_id": task.taskID,
                    "workflow": "plan-implement-validate",
                    "error": String(describing: error),
                ]
            )
            throw AttractorTaskExecutorError.workflowFailed(
                taskID: task.taskID,
                status: .fail,
                summary: String(describing: error)
            )
        }

        let resultFile = taskLogsRoot.appending(path: "pipeline-result.json")
        try Self.pipelineResultData(result).write(to: resultFile, options: .atomic)

        let artifacts = try Self.collectArtifacts(from: taskLogsRoot)
        let summary = Self.summary(for: result)
        if result.status == .fail || result.status == .retry {
            throw AttractorTaskExecutorError.workflowFailed(
                taskID: task.taskID,
                status: result.status,
                summary: summary
            )
        }

        return LocalTaskExecutionResult(
            summary: summary,
            artifacts: artifacts,
            metadata: [
                "execution_mode": "attractor",
                "pipeline_status": result.status.rawValue,
                "completed_nodes": result.completedNodes.joined(separator: ","),
                "last_response": result.context["last_response"] ?? "",
            ]
        )
    }

    private static func progressSummary(for event: PipelineEvent) -> String? {
        switch event.kind {
        case .pipelineStarted:
            return "Attractor workflow started"
        case .pipelineCompleted:
            return "Attractor workflow completed"
        case .pipelineFailed:
            return "Attractor workflow failed"
        case .stageStarted:
            return event.nodeId.map { "Attractor stage \($0) started" }
        case .stageCompleted:
            return event.nodeId.map { "Attractor stage \($0) completed" }
        case .stageFailed:
            return event.nodeId.map { "Attractor stage \($0) failed" }
        case .interviewStarted:
            return event.nodeId.map { "Awaiting human input for \($0)" }
        case .interviewCompleted:
            return event.nodeId.map { "Human input received for \($0)" }
        case .interviewTimeout:
            return event.nodeId.map { "Human input timed out for \($0)" }
        default:
            return nil
        }
    }

    private static func progressData(for event: PipelineEvent, taskID: String) -> [String: String] {
        var data = event.data
        data["task_id"] = taskID
        data["event_kind"] = event.kind.rawValue
        if let nodeID = event.nodeId {
            data["node_id"] = nodeID
        }
        return data
    }

    private static func pipelineResultData(_ result: PipelineResult) throws -> Data {
        let payload: [String: Any] = [
            "status": result.status.rawValue,
            "completed_nodes": result.completedNodes,
            "node_outcomes": result.nodeOutcomes.mapValues(\.rawValue),
            "context": result.context,
            "logs_root": result.logsRoot.path,
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func summary(for result: PipelineResult) -> String {
        let lastResponse = result.context["last_response"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        if !lastResponse.isEmpty {
            return "Attractor workflow \(result.status.rawValue): \(String(lastResponse.prefix(500)))"
        }
        return "Attractor workflow \(result.status.rawValue) after \(result.completedNodes.count) completed node(s)."
    }

    private static func collectArtifacts(from logsRoot: URL) throws -> [LocalTaskExecutionArtifact] {
        let enumerator = FileManager.default.enumerator(
            at: logsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var artifacts: [LocalTaskExecutionArtifact] = []
        while let nextURL = enumerator?.nextObject() as? URL {
            let values = try nextURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                continue
            }
            if let size = values.fileSize, size > 256 * 1_024 {
                continue
            }
            let relativePath = nextURL.path.replacingOccurrences(
                of: logsRoot.path + "/",
                with: ""
            )
            let contentType = Self.contentType(for: nextURL.pathExtension.lowercased())
            let data = try Data(contentsOf: nextURL)
            artifacts.append(
                LocalTaskExecutionArtifact(
                    name: relativePath,
                    contentType: contentType,
                    data: data
                )
            )
        }

        return artifacts.sorted { $0.name < $1.name }
    }

    private static func contentType(for pathExtension: String) -> String {
        switch pathExtension {
        case "json":
            return "application/json"
        case "md":
            return "text/markdown"
        case "dot":
            return "text/vnd.graphviz"
        case "txt", "log":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }
}
