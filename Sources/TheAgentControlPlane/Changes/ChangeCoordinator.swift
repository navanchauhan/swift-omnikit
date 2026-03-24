import Foundation
import OmniAgentMesh
import TheAgentWorkerKit

public enum ChangeIntegrationPolicy: String, Codable, Sendable {
    case pullRequestOnly = "pull_request_only"
    case directMain = "direct_main"
}

public struct ChangeRequest: Codable, Sendable, Equatable {
    public var changeID: String
    public var rootSessionID: String
    public var title: String
    public var summary: String
    public var version: String
    public var implementationBrief: String
    public var reviewBrief: String
    public var scenarioBrief: String
    public var implementationCapabilities: [String]
    public var reviewCapabilities: [String]
    public var scenarioCapabilities: [String]
    public var priority: Int
    public var policy: ChangeIntegrationPolicy
    public var maxRetries: Int

    public init(
        changeID: String = UUID().uuidString,
        rootSessionID: String,
        title: String,
        summary: String,
        version: String,
        implementationBrief: String,
        reviewBrief: String = "Review the implementation artifacts and report any blocking findings.",
        scenarioBrief: String = "Run scenario and automated verification against the implementation artifacts.",
        implementationCapabilities: [String] = ["lane:implementation"],
        reviewCapabilities: [String] = ["lane:review"],
        scenarioCapabilities: [String] = ["lane:scenario"],
        priority: Int = 100,
        policy: ChangeIntegrationPolicy = .pullRequestOnly,
        maxRetries: Int = 1
    ) {
        self.changeID = changeID
        self.rootSessionID = rootSessionID
        self.title = title
        self.summary = summary
        self.version = version
        self.implementationBrief = implementationBrief
        self.reviewBrief = reviewBrief
        self.scenarioBrief = scenarioBrief
        self.implementationCapabilities = implementationCapabilities
        self.reviewCapabilities = reviewCapabilities
        self.scenarioCapabilities = scenarioCapabilities
        self.priority = priority
        self.policy = policy
        self.maxRetries = max(0, maxRetries)
    }
}

public actor ChangeCoordinator {
    private let jobStore: any JobStore
    private let childManager: ChildWorkerManager

    public init(jobStore: any JobStore, childManager: ChildWorkerManager? = nil) {
        self.jobStore = jobStore
        self.childManager = childManager ?? ChildWorkerManager(jobStore: jobStore)
    }

    public func startChange(
        _ request: ChangeRequest,
        createdAt: Date = Date()
    ) async throws -> TaskRecord {
        let task = TaskRecord(
            taskID: request.changeID,
            rootSessionID: request.rootSessionID,
            capabilityRequirements: [],
            historyProjection: HistoryProjection(
                taskBrief: request.summary,
                constraints: [
                    "integration_policy=\(request.policy.rawValue)",
                    "version=\(request.version)",
                ],
                expectedOutputs: [
                    "implementation",
                    "review",
                    "scenario-eval",
                    "deploy",
                ]
            ),
            priority: request.priority,
            status: .running,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let created = try await jobStore.createTask(task, idempotencyKey: "task.submitted.\(request.changeID)")
        _ = try await jobStore.startTask(
            taskID: created.taskID,
            workerID: "change-coordinator",
            now: createdAt,
            idempotencyKey: "task.started.\(created.taskID).change-coordinator"
        )
        return try await jobStore.task(taskID: created.taskID) ?? created
    }

    public func enqueueImplementation(
        for changeTaskID: String,
        request: ChangeRequest,
        createdAt: Date = Date()
    ) async throws -> TaskRecord {
        try await childManager.spawnChildTask(
            parentTaskID: changeTaskID,
            request: ChildTaskRequest(
                brief: request.implementationBrief,
                capabilityRequirements: request.implementationCapabilities,
                constraints: [
                    "change_id=\(request.changeID)",
                    "integration_policy=\(request.policy.rawValue)",
                ],
                expectedOutputs: ["implementation-artifacts"],
                priority: request.priority
            ),
            createdAt: createdAt
        )
    }

    public func enqueueReview(
        for changeTaskID: String,
        request: ChangeRequest,
        implementationArtifactRefs: [String],
        createdAt: Date = Date()
    ) async throws -> TaskRecord {
        try await childManager.spawnChildTask(
            parentTaskID: changeTaskID,
            request: ChildTaskRequest(
                brief: request.reviewBrief,
                capabilityRequirements: request.reviewCapabilities,
                constraints: [
                    "change_id=\(request.changeID)",
                    "policy_requires_blocking_review=true",
                ],
                expectedOutputs: ["review-report"],
                artifactRefs: implementationArtifactRefs,
                priority: request.priority
            ),
            createdAt: createdAt
        )
    }

    public func enqueueScenarioEvaluation(
        for changeTaskID: String,
        request: ChangeRequest,
        implementationArtifactRefs: [String],
        createdAt: Date = Date()
    ) async throws -> TaskRecord {
        try await childManager.spawnChildTask(
            parentTaskID: changeTaskID,
            request: ChildTaskRequest(
                brief: request.scenarioBrief,
                capabilityRequirements: request.scenarioCapabilities,
                constraints: [
                    "change_id=\(request.changeID)",
                    "deploy_version=\(request.version)",
                ],
                expectedOutputs: ["scenario-report"],
                artifactRefs: implementationArtifactRefs,
                priority: request.priority
            ),
            createdAt: createdAt
        )
    }

    @discardableResult
    public func reconcileChange(changeTaskID: String, now: Date = Date()) async throws -> TaskEvent? {
        try await childManager.reconcileParent(parentTaskID: changeTaskID, now: now)
    }

    public func completeChange(
        changeTaskID: String,
        summary: String,
        artifactRefs: [String] = [],
        now: Date = Date()
    ) async throws -> TaskEvent {
        try await jobStore.completeTask(
            taskID: changeTaskID,
            workerID: "change-coordinator",
            summary: summary,
            artifactRefs: artifactRefs,
            idempotencyKey: "task.completed.\(changeTaskID).change-coordinator",
            now: now
        )
    }

    public func failChange(
        changeTaskID: String,
        summary: String,
        now: Date = Date()
    ) async throws -> TaskEvent {
        try await jobStore.failTask(
            taskID: changeTaskID,
            workerID: "change-coordinator",
            summary: summary,
            idempotencyKey: "task.failed.\(changeTaskID).change-coordinator",
            now: now
        )
    }
}
