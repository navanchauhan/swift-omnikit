import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentControlPlaneKit

@Suite
struct PolicyBootstrapperTests {
    @Test
    func telegramOwnerEnvironmentSeedsAllowlistAndAllowlistDMPolicy() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "policy-bootstrapper-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        try await identityStore.saveWorkspace(
            WorkspaceRecord(
                workspaceID: WorkspaceID(rawValue: "root"),
                displayName: "TheAgent Root Workspace",
                kind: .service,
                metadata: [:]
            )
        )

        try await PolicyBootstrapper.applyEnvironmentOverrides(
            identityStore: identityStore,
            environment: [
                "THE_AGENT_TELEGRAM_OWNER_ID": "7960102564",
            ]
        )

        let rootWorkspace = try #require(await identityStore.workspace(workspaceID: WorkspaceID(rawValue: "root")))
        #expect(rootWorkspace.metadata["telegram_allowlist_external_actor_ids"] == "7960102564")
        #expect(rootWorkspace.metadata["telegram_dm_policy"] == "allowlist")
    }
}
