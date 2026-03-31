import Foundation
import OmniAgentDeliveryCore
import OmniAgentMesh
import TheAgentControlPlaneKit
import TheAgentWorkerKit

public struct ChangePipelineResult: Sendable, Equatable {
    public var changeTaskID: String
    public var implementationTaskID: String
    public var reviewTaskID: String?
    public var scenarioTaskID: String?
    public var deliveryMode: ChangeDeliveryMode
    public var releaseBundleID: String?
    public var releaseID: String?
    public var deploymentState: DeploymentRecord.State?
    public var healthStatus: DeploymentRecord.HealthStatus?
    public var deployed: Bool
    public var rolledBackToReleaseID: String?
    public var summary: String

    public init(
        changeTaskID: String,
        implementationTaskID: String,
        reviewTaskID: String? = nil,
        scenarioTaskID: String? = nil,
        deliveryMode: ChangeDeliveryMode,
        releaseBundleID: String? = nil,
        releaseID: String? = nil,
        deploymentState: DeploymentRecord.State? = nil,
        healthStatus: DeploymentRecord.HealthStatus? = nil,
        deployed: Bool,
        rolledBackToReleaseID: String? = nil,
        summary: String
    ) {
        self.changeTaskID = changeTaskID
        self.implementationTaskID = implementationTaskID
        self.reviewTaskID = reviewTaskID
        self.scenarioTaskID = scenarioTaskID
        self.deliveryMode = deliveryMode
        self.releaseBundleID = releaseBundleID
        self.releaseID = releaseID
        self.deploymentState = deploymentState
        self.healthStatus = healthStatus
        self.deployed = deployed
        self.rolledBackToReleaseID = rolledBackToReleaseID
        self.summary = summary
    }
}

public actor ChangePipeline {
    private let scheduler: RootScheduler
    private let jobStore: any JobStore
    private let artifactStore: any ArtifactStore
    private let changeCoordinator: ChangeCoordinator
    private let releaseBundleStore: any ReleaseBundleStore
    private let releaseController: ReleaseController

    public init(
        scheduler: RootScheduler,
        jobStore: any JobStore,
        artifactStore: any ArtifactStore,
        changeCoordinator: ChangeCoordinator,
        releaseBundleStore: any ReleaseBundleStore,
        releaseController: ReleaseController
    ) {
        self.scheduler = scheduler
        self.jobStore = jobStore
        self.artifactStore = artifactStore
        self.changeCoordinator = changeCoordinator
        self.releaseBundleStore = releaseBundleStore
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

        if request.deliveryMode == .blockedForTargeting {
            let summary = "Change blocked: deployment target is required before rollout can begin."
            _ = try await changeCoordinator.failChange(
                changeTaskID: changeTask.taskID,
                summary: summary,
                now: now
            )
            return ChangePipelineResult(
                changeTaskID: changeTask.taskID,
                implementationTaskID: changeTask.taskID,
                deliveryMode: request.deliveryMode,
                deployed: false,
                summary: summary
            )
        }

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
                deliveryMode: request.deliveryMode,
                deployed: false,
                summary: "Implementation lane failed for change \(request.changeID)."
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
                deliveryMode: request.deliveryMode,
                deployed: false,
                summary: failureReason
            )
        }

        let implementationArtifacts = try await artifactStore.list(taskID: implementationTask.taskID)
        let releaseBundleID: String?
        if request.deliveryMode == .deployable {
            let releaseBundle = try await makeReleaseBundle(
                request: request,
                implementationArtifacts: implementationArtifacts,
                now: now.addingTimeInterval(3.5)
            )
            try await releaseBundleStore.saveBundle(releaseBundle)
            releaseBundleID = releaseBundle.bundleID
        } else {
            releaseBundleID = nil
        }

        if request.deliveryMode == .artifactOnly {
            let summary = "Change completed with durable artifacts; deployment skipped by policy."
            _ = try await changeCoordinator.completeChange(
                changeTaskID: changeTask.taskID,
                summary: summary,
                artifactRefs: implementationRecord.artifactRefs,
                now: now.addingTimeInterval(4)
            )
            return ChangePipelineResult(
                changeTaskID: changeTask.taskID,
                implementationTaskID: implementationTask.taskID,
                reviewTaskID: reviewTask.taskID,
                scenarioTaskID: scenarioTask.taskID,
                deliveryMode: request.deliveryMode,
                releaseBundleID: releaseBundleID,
                deployed: false,
                summary: summary
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
            releaseBundleID: releaseBundleID,
            service: request.service,
            targetEnvironment: request.targetEnvironment,
            deliveryMode: .deployable,
            autoRolloutEligible: request.autoRolloutEligible,
            drainingTaskIDs: unrelatedRunningTasks,
            metadata: [
                "change_id": request.changeID,
                "integration_policy": request.policy.rawValue,
                "require_deploy_approval": String(request.requireDeployApproval),
            ],
            now: now.addingTimeInterval(4)
        )
        let deployResult = try await releaseController.deployCanary(
            releaseID: release.releaseID,
            maxAttempts: max(1, request.maxRetries + 1),
            now: now.addingTimeInterval(5)
        )

        if deployResult.deployed {
            let summary = "Change deployed successfully under policy \(request.policy.rawValue)."
            _ = try await changeCoordinator.completeChange(
                changeTaskID: changeTask.taskID,
                summary: summary,
                artifactRefs: implementationRecord.artifactRefs,
                now: now.addingTimeInterval(6)
            )
            return ChangePipelineResult(
                changeTaskID: changeTask.taskID,
                implementationTaskID: implementationTask.taskID,
                reviewTaskID: reviewTask.taskID,
                scenarioTaskID: scenarioTask.taskID,
                deliveryMode: request.deliveryMode,
                releaseBundleID: releaseBundleID,
                releaseID: release.releaseID,
                deploymentState: deployResult.state,
                healthStatus: deployResult.healthStatus,
                deployed: deployResult.deployed,
                rolledBackToReleaseID: deployResult.rolledBackToReleaseID,
                summary: summary
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
            return ChangePipelineResult(
                changeTaskID: changeTask.taskID,
                implementationTaskID: implementationTask.taskID,
                reviewTaskID: reviewTask.taskID,
                scenarioTaskID: scenarioTask.taskID,
                deliveryMode: request.deliveryMode,
                releaseBundleID: releaseBundleID,
                releaseID: release.releaseID,
                deploymentState: deployResult.state,
                healthStatus: deployResult.healthStatus,
                deployed: false,
                rolledBackToReleaseID: deployResult.rolledBackToReleaseID,
                summary: failureSummary
            )
        }
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

    private func makeReleaseBundle(
        request: ChangeRequest,
        implementationArtifacts: [ArtifactRecord],
        now: Date
    ) async throws -> ReleaseBundle {
        var artifactRefs: [ReleaseBundleArtifact] = []
        artifactRefs.reserveCapacity(implementationArtifacts.count)
        for artifact in implementationArtifacts {
            let data = try await artifactStore.data(for: artifact.artifactID) ?? Data()
            artifactRefs.append(
                ReleaseBundleArtifact(
                artifactID: artifact.artifactID,
                name: artifact.name,
                contentType: artifact.contentType,
                byteCount: data.count,
                contentHash: ReleaseBundleHash.hash(data)
            )
            )
        }
        let targetEnvironment = request.targetEnvironment ?? "unspecified"
        return ReleaseBundle(
            changeID: request.changeID,
            rootSessionID: request.rootSessionID,
            service: request.service,
            targetEnvironment: targetEnvironment,
            version: request.version,
            commitish: request.policy.rawValue,
            artifactRefs: artifactRefs,
            healthPlan: [
                "service_liveness",
                "worker_heartbeats",
                "smoke_checks",
            ],
            rollbackEligible: request.deliveryMode == .deployable,
            metadata: [
                "delivery_mode": request.deliveryMode.rawValue,
                "auto_rollout_eligible": String(request.autoRolloutEligible),
            ],
            createdAt: now
        )
    }
}
