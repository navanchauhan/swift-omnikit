import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentControlPlaneKit

@Suite
struct MissionRecoveryTests {
    @Test
    func stalledMissionTaskIsFailedBySupervisorAndRetriedByMissionCoordinator() async throws {
        let stateRoot = try makeStateRoot(prefix: "mission-recovery")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.deliveriesDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let scope = SessionScope(actorID: "chief", workspaceID: "workspace-r", channelID: "dm-r")
        let server = RootAgentServer(
            scope: scope,
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            runtimeRootDirectory: stateRoot.runtimeDirectoryURL,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore
        )
        let now = Date(timeIntervalSince1970: 3_000)

        let started = try await server.startMission(
            MissionStartRequest(
                title: "Recoverable mission",
                brief: "Delegate this mission and recover if it stalls.",
                executionMode: .workerTask,
                capabilityRequirements: ["linux"],
                expectedOutputs: ["artifact"],
                metadata: ["heartbeat_grace_seconds": "5"]
            ),
            now: now
        )
        let originalTaskID = try #require(started.task?.taskID)

        let sweep = try await server.runSupervisorSweep(now: now.addingTimeInterval(30))
        let snapshot = try await server.missionStatus(missionID: started.mission.missionID)

        #expect(sweep.stalledTasks.count == 1)
        #expect(sweep.notificationIDs.count == 1)
        #expect(snapshot.mission.status == MissionRecord.Status.executing)
        #expect(snapshot.task?.taskID != originalTaskID)
        #expect(try await jobStore.task(taskID: originalTaskID)?.status == .failed)
    }

    private func makeStateRoot(prefix: String) throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
