import Foundation
import OmniAgentMesh
import TheAgentControlPlaneKit
import TheAgentWorkerKit

public struct ChangePipelineResult: Sendable, Equatable {
    public var changeTaskID: String
    public var implementationTaskID: String
    public var reviewTaskID: String?
    public var scenarioTaskID: String?
    public var releaseID: String?
    public var deployed: Bool
    public var rolledBackToReleaseID: String?

    public init(
        changeTaskID: String,
        implementationTaskID: String,
        reviewTaskID: String? = nil,
        scenarioTaskID: String? = nil,
        releaseID: String? = nil,
        deployed: Bool,
        rolledBackToReleaseID: String? = nil
    ) {
        self.changeTaskID = changeTaskID
        self.implementationTaskID = implementationTaskID
        self.reviewTaskID = reviewTaskID
        self.scenarioTaskID = scenarioTaskID
        self.releaseID = releaseID
        self.deployed = deployed
        self.rolledBackToReleaseID = rolledBackToReleaseID
    }
}

public actor ChangePipeline {
    private let scheduler: RootScheduler
    private let jobStore: any JobStore
    private let artifactStore: any ArtifactStore
    private let changeCoordinator: ChangeCoordinator
    private let releaseController: ReleaseController

    public init(
        scheduler: RootScheduler,
        jobStore: any JobStore,
        artifactStore: any ArtifactStore,
        changeCoordinator: ChangeCoordinator,
        releaseController: ReleaseController
    ) {
        self.scheduler = scheduler
        self.jobStore = jobStore
        self.artifactStore = artifactStore
        self.changeCoordinator = changeCoordinator
        self.releaseController = releaseController
    }

    public func run(
        request: ChangeRequest,
        implementationExecutor: LocalTaskExecutor,
        reviewWorker: ReviewWorker = ReviewWorker(),
        scenarioWorker: ScenarioEvalWorker = ScenarioEvalWorker(),
        now: Date = Date()
    ) async throws -> ChangePipelineResult {
        let implementationLane = WorkerDaemon(
            displayName: "implementation-lane",
            capabilities: WorkerCapabilities(request.implementationCapabilities + ["change"]),
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: implementationExecutor,
            leaseDuration: 60
        )
        let reviewLane = WorkerDaemon(
            displayName: "review-lane",
            capabilities: WorkerCapabilities(request.reviewCapabilities + ["change"]),
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: reviewWorker.makeExecutor(artifactStore: artifactStore),
            leaseDuration: 60
        )
        let scenarioLane = WorkerDaemon(
            displayName: "scenario-lane",
            capabilities: WorkerCapabilities(request.scenarioCapabilities + ["change"]),
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: scenarioWorker.makeExecutor(),
            leaseDuration: 60
        )

        try await scheduler.registerLocalWorker(implementationLane, at: now)
        try await scheduler.registerLocalWorker(reviewLane, at: now)
        try await scheduler.registerLocalWorker(scenarioLane, at: now)

        let changeTask = try await changeCoordinator.startChange(request, createdAt: now)
        let implementationTask = try await changeCoordinator.enqueueImplementation(
            for: changeTask.taskID,
            request: request,
            createdAt: now
        )
        _ = try await scheduler.dispatchNextAvailableTask(now: now)

        let implementationRecord = try await requireTask(taskID: implementationTask.taskID)
        guard implementationRecord.status == .completed else {
            _ = try await changeCoordinator.failChange(
                changeTaskID: changeTask.taskID,
                summary: "Implementation lane failed for change \(request.changeID).",
                now: now
            )
            return ChangePipelineResult(
                changeTaskID: changeTask.taskID,
                implementationTaskID: implementationTask.taskID,
                deployed: false
            )
        }

        let reviewTask = try await changeCoordinator.enqueueReview(
            for: changeTask.taskID,
            request: request,
            implementationArtifactRefs: implementationRecord.artifactRefs,
            createdAt: now.addingTimeInterval(1)
        )
        let scenarioTask = try await changeCoordinator.enqueueScenarioEvaluation(
            for: changeTask.taskID,
            request: request,
            implementationArtifactRefs: implementationRecord.artifactRefs,
            createdAt: now.addingTimeInterval(2)
        )
        _ = try await scheduler.dispatchAllAvailableTasks(now: now.addingTimeInterval(2))

        let reviewSummary = try await latestSummary(taskID: reviewTask.taskID)
        let scenarioSummary = try await latestSummary(taskID: scenarioTask.taskID)
        let reviewApproved = reviewWorker.isApproved(summary: reviewSummary)
        let scenarioPassed = scenarioWorker.didPass(summary: scenarioSummary)

        guard reviewApproved && scenarioPassed else {
            let failureReason = reviewApproved
                ? "Scenario evaluation blocked deployment."
                : "Automated review blocked deployment."
            _ = try await changeCoordinator.failChange(
                changeTaskID: changeTask.taskID,
                summary: failureReason,
                now: now.addingTimeInterval(3)
            )
            return ChangePipelineResult(
                changeTaskID: changeTask.taskID,
                implementationTaskID: implementationTask.taskID,
                reviewTaskID: reviewTask.taskID,
                scenarioTaskID: scenarioTask.taskID,
                deployed: false
            )
        }

        let unrelatedRunningTasks = try await jobStore.tasks(statuses: [.submitted, .assigned, .running, .waiting])
            .map(\.taskID)
            .filter { taskID in
                taskID != changeTask.taskID
                    && taskID != implementationTask.taskID
                    && taskID != reviewTask.taskID
                    && taskID != scenarioTask.taskID
            }
        let release = try await releaseController.prepareRelease(
            version: request.version,
            drainingTaskIDs: unrelatedRunningTasks,
            metadata: [
                "change_id": request.changeID,
                "integration_policy": request.policy.rawValue,
            ],
            now: now.addingTimeInterval(4)
        )
        let deployResult = try await releaseController.deployCanary(
            releaseID: release.releaseID,
            maxAttempts: max(1, request.maxRetries + 1),
            now: now.addingTimeInterval(5)
        )

        if deployResult.deployed {
            _ = try await changeCoordinator.completeChange(
                changeTaskID: changeTask.taskID,
                summary: "Change deployed successfully under policy \(request.policy.rawValue).",
                artifactRefs: implementationRecord.artifactRefs,
                now: now.addingTimeInterval(6)
            )
        } else {
            let failureSummary = if let rolledBackToReleaseID = deployResult.rolledBackToReleaseID {
                "Deploy failed health verification and rolled back to \(rolledBackToReleaseID)."
            } else {
                "Deploy failed health verification without a rollback target."
            }
            _ = try await changeCoordinator.failChange(
                changeTaskID: changeTask.taskID,
                summary: failureSummary,
                now: now.addingTimeInterval(6)
            )
        }

        return ChangePipelineResult(
            changeTaskID: changeTask.taskID,
            implementationTaskID: implementationTask.taskID,
            reviewTaskID: reviewTask.taskID,
            scenarioTaskID: scenarioTask.taskID,
            releaseID: release.releaseID,
            deployed: deployResult.deployed,
            rolledBackToReleaseID: deployResult.rolledBackToReleaseID
        )
    }

    private func requireTask(taskID: String) async throws -> TaskRecord {
        guard let task = try await jobStore.task(taskID: taskID) else {
            throw JobStoreError.taskNotFound(taskID)
        }
        return task
    }

    private func latestSummary(taskID: String) async throws -> String {
        let events = try await jobStore.events(taskID: taskID, afterSequence: nil)
        return events.last?.summary ?? ""
    }
}
