import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentControlPlaneKit

@Suite
struct ReflectionLoopTests {
    @Test
    func reflectionWritesWorkspaceScopedMemoryOncePerMission() async throws {
        let stateRoot = try makeStateRoot(prefix: "reflection-loop")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let memoryStore = WorkspaceMemoryStore(rootDirectory: stateRoot.runtimeDirectoryURL.appending(path: "memory"))
        let reflectionLoop = ReflectionLoop(
            conversationStore: conversationStore,
            memoryStore: memoryStore
        )
        let scope = SessionScope(actorID: "chief", workspaceID: "workspace-a", channelID: "dm-a")
        _ = try await conversationStore.appendInteraction(
            InteractionItem(sessionID: scope.sessionID, actorID: scope.actorID, workspaceID: scope.workspaceID, channelID: scope.channelID, role: .user, modality: .text, content: "Ship the release checklist.")
        )
        _ = try await conversationStore.appendInteraction(
            InteractionItem(sessionID: scope.sessionID, actorID: scope.actorID, workspaceID: scope.workspaceID, channelID: scope.channelID, role: .assistant, modality: .text, content: "The release checklist is complete.")
        )
        let mission = MissionRecord(
            missionID: "mission-memory",
            rootSessionID: scope.sessionID,
            requesterActorID: scope.actorID,
            workspaceID: scope.workspaceID,
            channelID: scope.channelID,
            title: "Release checklist",
            brief: "Finish the release checklist.",
            executionMode: .workerTask,
            status: .completed
        )
        let task = TaskRecord(
            taskID: "task-memory",
            rootSessionID: scope.sessionID,
            requesterActorID: scope.actorID,
            workspaceID: scope.workspaceID,
            channelID: scope.channelID,
            missionID: mission.missionID,
            historyProjection: HistoryProjection(taskBrief: "Complete the release checklist"),
            status: .completed
        )

        let first = try await reflectionLoop.reflectOnMissionCompletion(
            mission: mission,
            task: task,
            events: [TaskEvent(taskID: task.taskID, sequenceNumber: 1, idempotencyKey: "event-1", kind: .completed, summary: "Checklist completed")]
        )
        let second = try await reflectionLoop.reflectOnMissionCompletion(
            mission: mission,
            task: task,
            events: [TaskEvent(taskID: task.taskID, sequenceNumber: 2, idempotencyKey: "event-2", kind: .completed, summary: "Checklist completed")]
        )
        let stored = try await memoryStore.candidates(workspaceID: scope.workspaceID)

        #expect(first.candidates.count == 1)
        #expect(second.candidates.isEmpty)
        #expect(stored.count == 1)
        #expect(stored.first?.workspaceID == scope.workspaceID)
        #expect(stored.first?.summary.localizedStandardContains("Release checklist") == true)
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
