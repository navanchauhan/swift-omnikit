import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentControlPlaneKit

@Suite
struct ProactiveNotificationTests {
    @Test
    func reflectionCanPlanCompletionNotificationForBackgroundMission() async throws {
        let stateRoot = try makeStateRoot(prefix: "proactive-notification")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let memoryStore = WorkspaceMemoryStore(rootDirectory: stateRoot.runtimeDirectoryURL.appending(path: "memory"))
        let planner = NotificationPlanner(conversationStore: conversationStore)
        let reflectionLoop = ReflectionLoop(
            conversationStore: conversationStore,
            memoryStore: memoryStore,
            notificationPlanner: planner
        )
        let scope = SessionScope(actorID: "chief", workspaceID: "workspace-a", channelID: "dm-a")
        let mission = MissionRecord(
            missionID: "mission-notify",
            rootSessionID: scope.sessionID,
            requesterActorID: scope.actorID,
            workspaceID: scope.workspaceID,
            channelID: scope.channelID,
            title: "Background monitor",
            brief: "Watch the system and notify on completion.",
            executionMode: .workerTask,
            status: .completed,
            metadata: ["notify_on_completion": "true"]
        )

        let result = try await reflectionLoop.reflectOnMissionCompletion(
            mission: mission,
            task: nil,
            events: []
        )
        let notifications = try await conversationStore.notifications(sessionID: scope.sessionID, unresolvedOnly: false)

        #expect(result.notification?.notificationID == "mission.mission-notify.completed")
        #expect(notifications.contains { $0.notificationID == "mission.mission-notify.completed" })
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
