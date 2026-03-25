import Foundation
import OmniAgentMesh

public actor NotificationPlanner {
    private let conversationStore: any ConversationStore

    public init(conversationStore: any ConversationStore) {
        self.conversationStore = conversationStore
    }

    public func planMissionCompletion(
        scope: SessionScope,
        mission: MissionRecord,
        summary: String,
        importance: NotificationRecord.Importance = .important
    ) async throws -> NotificationRecord? {
        let notificationID = "mission.\(mission.missionID).completed"
        let existing = try await conversationStore.notifications(sessionID: scope.sessionID, unresolvedOnly: false)
        if existing.contains(where: { $0.notificationID == notificationID }) {
            return nil
        }
        let notification = NotificationRecord(
            notificationID: notificationID,
            sessionID: scope.sessionID,
            actorID: mission.requesterActorID ?? scope.actorID,
            workspaceID: mission.workspaceID ?? scope.workspaceID,
            channelID: mission.channelID ?? scope.channelID,
            taskID: mission.primaryTaskID,
            title: "Mission Completed",
            body: summary,
            importance: importance,
            metadata: [
                "notification_kind": "mission_completion",
                "mission_id": mission.missionID,
            ]
        )
        return try await conversationStore.saveNotification(notification)
    }
}
