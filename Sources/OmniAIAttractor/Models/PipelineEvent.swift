import Foundation

// MARK: - Pipeline Event

public enum PipelineEventKind: String, Sendable {
    // Pipeline lifecycle
    case pipelineStarted = "pipeline_started"
    case pipelineCompleted = "pipeline_completed"
    case pipelineFailed = "pipeline_failed"

    // Stage lifecycle
    case stageStarted = "stage_started"
    case stageCompleted = "stage_completed"
    case stageFailed = "stage_failed"
    case stageRetrying = "stage_retrying"

    // Parallel execution
    case parallelStarted = "parallel_started"
    case parallelBranchStarted = "parallel_branch_started"
    case parallelBranchCompleted = "parallel_branch_completed"
    case parallelCompleted = "parallel_completed"

    // Human interaction
    case interviewStarted = "interview_started"
    case interviewCompleted = "interview_completed"
    case interviewTimeout = "interview_timeout"

    // Checkpointing
    case checkpointSaved = "checkpoint_saved"

    // Change / deploy flow
    case changeImplementationStarted = "change_implementation_started"
    case changeReviewCompleted = "change_review_completed"
    case changeScenarioCompleted = "change_scenario_completed"
    case deployStarted = "deploy_started"
    case deployVerified = "deploy_verified"
    case deployRolledBack = "deploy_rolled_back"
}

public struct PipelineEvent: Sendable {
    public var kind: PipelineEventKind
    public var timestamp: Date
    public var nodeId: String?
    public var taskID: String?
    public var lane: String?
    public var releaseID: String?
    public var artifactIDs: [String]
    public var data: [String: String]

    public init(
        kind: PipelineEventKind,
        timestamp: Date = Date(),
        nodeId: String? = nil,
        taskID: String? = nil,
        lane: String? = nil,
        releaseID: String? = nil,
        artifactIDs: [String] = [],
        data: [String: String] = [:]
    ) {
        self.kind = kind
        self.timestamp = timestamp
        self.nodeId = nodeId
        self.taskID = taskID
        self.lane = lane
        self.releaseID = releaseID
        self.artifactIDs = artifactIDs
        self.data = data
    }
}

// MARK: - Event Emitter

public actor PipelineEventEmitter {
    private var handlers: [@Sendable (PipelineEvent) -> Void] = []
    private var allEvents: [PipelineEvent] = []
    private var continuations: [AsyncStream<PipelineEvent>.Continuation] = []

    public init() {}

    public func on(_ handler: @escaping @Sendable (PipelineEvent) -> Void) {
        handlers.append(handler)
    }

    public func emit(_ event: PipelineEvent) {
        allEvents.append(event)
        for handler in handlers {
            handler(event)
        }
        for continuation in continuations {
            continuation.yield(event)
        }
    }

    public func events() -> AsyncStream<PipelineEvent> {
        AsyncStream { continuation in
            continuations.append(continuation)
        }
    }

    public func history() -> [PipelineEvent] {
        allEvents
    }
}
