import Foundation
import Testing
import OmniAgentMesh
import TheAgentControlPlaneKit
import TheAgentWorkerKit
@testable import OmniAgentDeployKit

@Suite
struct ChangePipelineTests {
    @Test
    func changePipelineRunsImplementationReviewScenarioAndDeploysHealthyRelease() async throws {
        let stateRoot = try makeStateRoot()
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let deploymentStore = try SQLiteDeploymentStore(fileURL: stateRoot.deploymentDatabaseURL)
        let scheduler = RootScheduler(jobStore: jobStore)
        let coordinator = ChangeCoordinator(jobStore: jobStore)
        let supervisor = Supervisor(releasesDirectory: stateRoot.releasesDirectoryURL) { _ in true }
        let releaseController = ReleaseController(
            deploymentStore: deploymentStore,
            supervisor: supervisor
        )
        let pipeline = ChangePipeline(
            scheduler: scheduler,
            jobStore: jobStore,
            artifactStore: artifactStore,
            changeCoordinator: coordinator,
            releaseController: releaseController
        )

        let implementationExecutor = LocalTaskExecutor { _, reportProgress in
            try await reportProgress("implementation running", [:])
            return LocalTaskExecutionResult(
                summary: "implementation complete",
                artifacts: [
                    LocalTaskExecutionArtifact(
                        name: "patch.swift",
                        contentType: "text/plain",
                        data: Data("func shippedFeature() {}\n".utf8)
                    ),
                ]
            )
        }
        let request = ChangeRequest(
            rootSessionID: "root",
            title: "Ship safe change",
            summary: "Land a safe code change through isolated lanes.",
            version: "2.0.0",
            implementationBrief: "Implement the safe change"
        )

        let result = try await pipeline.run(
            request: request,
            implementationExecutor: implementationExecutor,
            now: Date(timeIntervalSince1970: 2_000)
        )

        let activeRelease = try await deploymentStore.activeRelease()
        let changeTask = try await jobStore.task(taskID: result.changeTaskID)

        #expect(result.deployed)
        #expect(activeRelease?.releaseID == result.releaseID)
        #expect(activeRelease?.state == .live)
        #expect(activeRelease?.metadata["integration_policy"] == ChangeIntegrationPolicy.pullRequestOnly.rawValue)
        #expect(changeTask?.status == .completed)
    }

    private func makeStateRoot() throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-deploy-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
