import Foundation
import OmniAgentMesh
import OmniAgentDeployKit

@main
enum OmniAgentDeployMain {
    static func main() async throws {
        let configuredRoot = ProcessInfo.processInfo.environment["THE_AGENT_STATE_ROOT"]
        let stateRoot: AgentFabricStateRoot
        if let configuredRoot {
            stateRoot = AgentFabricStateRoot(rootDirectory: URL(fileURLWithPath: configuredRoot))
        } else {
            stateRoot = .workingDirectoryDefault()
        }
        try stateRoot.prepare()

        let deploymentStore = try SQLiteDeploymentStore(fileURL: stateRoot.deploymentDatabaseURL)
        let supervisor = Supervisor(releasesDirectory: stateRoot.releasesDirectoryURL)
        let controller = ReleaseController(
            deploymentStore: deploymentStore,
            supervisor: supervisor
        )

        if let active = try await deploymentStore.activeRelease() {
            print("OmniAgentDeploy ready. Active release: \(active.releaseID) (\(active.version)).")
        } else {
            let prepared = try await controller.prepareRelease(
                version: "bootstrap",
                checkpointDirectory: stateRoot.checkpointsDirectoryURL.path(),
                now: Date()
            )
            print("OmniAgentDeploy ready. Prepared release \(prepared.releaseID).")
        }
    }
}
