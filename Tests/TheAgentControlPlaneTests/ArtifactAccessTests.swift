import Foundation
import Testing
import OmniAgentMesh
import TheAgentWorkerKit
@testable import TheAgentControlPlaneKit

@Suite
struct ArtifactAccessTests {
    @Test
    func rootServerListsAndReadsManagedArtifacts() async throws {
        let stateRoot = try makeStateRoot(prefix: "artifact-access")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let server = RootAgentServer(
            sessionID: "root",
            conversationStore: conversationStore,
            jobStore: jobStore,
            artifactStore: artifactStore
        )

        let task = try await server.delegateTask(
            brief: "Inspect the experiment artifact",
            capabilityRequirements: ["tpu"],
            expectedOutputs: ["status.md"]
        )
        let stored = try await artifactStore.put(
            ArtifactPayload(
                taskID: task.taskID,
                workspaceID: server.scope.workspaceID,
                channelID: server.scope.channelID,
                name: "status.md",
                contentType: "text/markdown",
                data: Data("Current best singing metric is 0.28073.\n".utf8)
            )
        )

        let listed = try await server.listArtifacts(taskID: task.taskID)
        let loaded = try await server.getArtifact(artifactID: stored.artifactID)

        #expect(listed.map(\.artifactID) == [stored.artifactID])
        #expect(loaded.record.name == "status.md")
        #expect(loaded.text?.localizedStandardContains("0.28073") == true)
        #expect(loaded.truncated == false)
    }

    @Test
    func rawRootSessionCanReadCanonicalMissionTaskArtifacts() async throws {
        let stateRoot = try makeStateRoot(prefix: "artifact-access-mission")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.deliveriesDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let server = RootAgentServer(
            sessionID: "root",
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore
        )

        let worker = WorkerDaemon(
            displayName: "artifact-worker",
            capabilities: WorkerCapabilities(["tpu"]),
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: LocalTaskExecutor { _, _ in
                LocalTaskExecutionResult(
                    summary: "TPU inspection finished.",
                    artifacts: [
                        LocalTaskExecutionArtifact(
                            name: "tpu-status.json",
                            contentType: "application/json",
                            data: Data(#"{"training_active":false,"best":"priority"}"#.utf8)
                        ),
                    ]
                )
            }
        )
        try await server.registerLocalWorker(worker)

        let started = try await server.startMission(
            MissionStartRequest(
                title: "Inspect TPU status",
                brief: "Run a worker-owned TPU mission.",
                capabilityRequirements: ["tpu"],
                expectedOutputs: ["tpu-status.json"]
            )
        )
        let finished = try await server.waitForMission(
            missionID: started.mission.missionID,
            timeoutSeconds: 5
        )
        let task = try #require(finished.task)
        let artifactID = try #require(task.artifactRefs.first)

        let latestMission = try await server.latestMission()
        let listed = try await server.listArtifacts(taskID: task.taskID)
        let loaded = try await server.getArtifact(artifactID: artifactID)
        let notifications = try await server.refreshTaskNotifications()

        #expect(latestMission?.missionID == finished.mission.missionID)
        #expect(listed.map(\.artifactID) == [artifactID])
        #expect(loaded.record.artifactID == artifactID)
        #expect(loaded.text?.localizedStandardContains(#""training_active":false"#) == true)
        #expect(notifications.contains { $0.taskID == task.taskID && $0.title == "Task Completed" })
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
