import Foundation
import Testing
import OmniAgentDeliveryCore
import OmniAgentMesh
import TheAgentControlPlaneKit
@testable import OmniAgentDeployKit

@Suite
struct RollbackScenarioTests {
    @Test
    func releaseControllerRollsBackOnUnhealthyCanary() async throws {
        let stateRoot = try makeStateRoot()
        let deploymentStore = try SQLiteDeploymentStore(fileURL: stateRoot.deploymentDatabaseURL)
        let supervisor = Supervisor(releasesDirectory: stateRoot.releasesDirectoryURL) { _ in true }
        let health = DeployHealthService { release in
            if release.version == "2.0.0" {
                return DeployHealthOutcome(status: .unhealthy, summary: "smoke check failed")
            }
            return DeployHealthOutcome(status: .healthy, summary: "healthy")
        }
        let controller = ReleaseController(
            deploymentStore: deploymentStore,
            supervisor: supervisor,
            healthService: health
        )

        let stable = try await controller.prepareRelease(
            version: "1.0.0",
            service: "the-agent",
            targetEnvironment: "prod",
            deliveryMode: .deployable,
            autoRolloutEligible: true,
            now: Date(timeIntervalSince1970: 100)
        )
        try await supervisor.install(stable)
        try await supervisor.activate(releaseID: stable.releaseID)
        try await deploymentStore.saveRelease(stable, makeActive: true)

        let candidate = try await controller.prepareRelease(
            version: "2.0.0",
            service: "the-agent",
            targetEnvironment: "prod",
            deliveryMode: .deployable,
            autoRolloutEligible: true,
            now: Date(timeIntervalSince1970: 200)
        )
        let result = try await controller.deployCanary(
            releaseID: candidate.releaseID,
            maxAttempts: 1,
            now: Date(timeIntervalSince1970: 201)
        )

        #expect(!result.deployed)
        #expect(result.healthStatus == .unhealthy)
        #expect(result.rolledBackToReleaseID == stable.releaseID)
        #expect(try await deploymentStore.activeRelease()?.releaseID == stable.releaseID)
    }

    private func makeStateRoot() throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "rollback-scenario-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
