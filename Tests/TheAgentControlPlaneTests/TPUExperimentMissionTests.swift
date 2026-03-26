import Foundation
import Testing
import OmniAgentMesh
import OmniSkills
@testable import TheAgentControlPlaneKit

@Suite
struct TPUExperimentMissionTests {
    @Test
    func inspectionMissionCarriesProjectedTPUSkillMetadata() async throws {
        let stateRoot = try makeStateRoot(prefix: "tpu-experiment-inspect")
        let server = try makeServer(stateRoot: stateRoot)

        let snapshot = try await server.startTPUExperimentMission(
            operation: .inspectStatus,
            domain: "singing"
        )
        let task = try #require(snapshot.task)

        #expect(snapshot.mission.status == .executing)
        #expect(task.capabilityRequirements.contains("tpu"))
        #expect(task.capabilityRequirements.contains("teacher-training"))
        #expect(task.historyProjection.expectedOutputs.contains("tpu-status.json"))
        #expect(task.historyProjection.taskBrief.localizedStandardContains("tmux ls"))
        #expect(task.metadata["omni_skills.active_ids"] == "tpu.exps")
        #expect(task.metadata["tpu_operation"] == "inspect_status")
    }

    @Test
    func rerunMissionDefaultsToApprovalBeforeTrainingStarts() async throws {
        let stateRoot = try makeStateRoot(prefix: "tpu-experiment-rerun")
        let server = try makeServer(stateRoot: stateRoot)

        let snapshot = try await server.startTPUExperimentMission(
            operation: .rerunBestKnownConfig,
            domain: "singing"
        )

        #expect(snapshot.mission.status == .awaitingApproval)
        #expect(snapshot.task == nil)
        #expect(snapshot.approvals.count == 1)
        #expect(snapshot.approvals.first?.prompt.localizedStandardContains("fresh TPU training rerun") == true)
    }

    @Test
    func inspectionMissionRejectsDirectExecutionOverride() async throws {
        let stateRoot = try makeStateRoot(prefix: "tpu-experiment-direct-override")
        let server = try makeServer(stateRoot: stateRoot)

        let snapshot = try await server.startTPUExperimentMission(
            operation: .inspectStatus,
            domain: "singing",
            executionMode: .direct
        )
        let task = try #require(snapshot.task)

        #expect(snapshot.mission.executionMode == .workerTask)
        #expect(task.capabilityRequirements.contains("tpu"))
    }

    private func makeServer(stateRoot: AgentFabricStateRoot) throws -> RootAgentServer {
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.deliveriesDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let skillStore = try SQLiteSkillStore(fileURL: stateRoot.skillsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let skillsRoot = stateRoot.runtimeDirectoryURL.appending(path: "skills", directoryHint: .isDirectory)
        return RootAgentServer(
            sessionID: "root",
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            skillStore: skillStore,
            skillsRootDirectory: skillsRoot,
            runtimeRootDirectory: stateRoot.runtimeDirectoryURL,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore,
            workingDirectory: repositoryRoot().path()
        )
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

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
