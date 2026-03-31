import Foundation
import Testing
import OmniAgentDeliveryCore
import OmniAgentMesh
import TheAgentControlPlaneKit
import TheAgentWorkerKit
@testable import OmniAgentDeployKit

@Suite
struct AgentFabricScenarioTests {
    @Test
    func failedDeployRollsBackWithoutDroppingUnrelatedQueuedTasks() async throws {
        let stateRoot = try makeStateRoot()
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let deploymentStore = try SQLiteDeploymentStore(fileURL: stateRoot.deploymentDatabaseURL)
        let releaseBundleStore = try FileReleaseBundleStore(
            rootDirectory: stateRoot.releasesDirectoryURL.appending(path: "bundles", directoryHint: .isDirectory)
        )
        let scheduler = RootScheduler(jobStore: jobStore)
        let coordinator = ChangeCoordinator(jobStore: jobStore)
        let previousRelease = DeploymentRecord(
            releaseID: "stable-release",
            version: "1.0.0",
            state: .live,
            slot: .active,
            healthStatus: .healthy,
            checkpointDirectory: stateRoot.checkpointsDirectoryURL.path()
        )
        try await deploymentStore.saveRelease(previousRelease, makeActive: true)

        let supervisor = Supervisor(releasesDirectory: stateRoot.releasesDirectoryURL) { release in
            release.version != "2.0.0"
        }
        try await supervisor.install(previousRelease)
        try await supervisor.activate(releaseID: previousRelease.releaseID)

        let releaseController = ReleaseController(
            deploymentStore: deploymentStore,
            supervisor: supervisor
        )
        let pipeline = ChangePipeline(
            scheduler: scheduler,
            jobStore: jobStore,
            artifactStore: artifactStore,
            changeCoordinator: coordinator,
            releaseBundleStore: releaseBundleStore,
            releaseController: releaseController
        )

        let unrelatedTask = TaskRecord(
            taskID: "background-task",
            rootSessionID: "root",
            capabilityRequirements: ["background"],
            historyProjection: HistoryProjection(taskBrief: "Keep running unrelated work"),
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 3_000)
        )
        _ = try await jobStore.createTask(unrelatedTask, idempotencyKey: "task.submitted.background-task")

        let implementationExecutor = LocalTaskExecutor { _, reportProgress in
            try await reportProgress("implementation running", [:])
            return LocalTaskExecutionResult(
                summary: "implementation complete",
                artifacts: [
                    LocalTaskExecutionArtifact(
                        name: "safe-change.swift",
                        contentType: "text/plain",
                        data: Data("func canaryChange() {}\n".utf8)
                    ),
                ]
            )
        }
        let request = ChangeRequest(
            rootSessionID: "root",
            title: "Canary deploy",
            summary: "Attempt a deploy that should roll back cleanly.",
            version: "2.0.0",
            implementationBrief: "Implement the change",
            deliveryMode: .deployable,
            service: "the-agent",
            targetEnvironment: "canary",
            autoRolloutEligible: true,
            maxRetries: 0
        )

        let result = try await pipeline.run(
            request: request,
            implementationExecutor: implementationExecutor,
            now: Date(timeIntervalSince1970: 3_001)
        )
        let activeRelease = try await deploymentStore.activeRelease()
        let backgroundTask = try await jobStore.task(taskID: unrelatedTask.taskID)
        let changeTask = try await jobStore.task(taskID: result.changeTaskID)

        #expect(!result.deployed)
        #expect(result.rolledBackToReleaseID == previousRelease.releaseID)
        #expect(activeRelease?.releaseID == previousRelease.releaseID)
        #expect(backgroundTask?.status == .submitted)
        #expect(changeTask?.status == .failed)
    }

    private func makeStateRoot() throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-scenario-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
