import Foundation
import OmniAgentMesh

public struct ReflectionResult: Sendable, Equatable {
    public var candidates: [MemoryCandidate]
    public var notification: NotificationRecord?

    public init(
        candidates: [MemoryCandidate] = [],
        notification: NotificationRecord? = nil
    ) {
        self.candidates = candidates
        self.notification = notification
    }
}

public actor ReflectionLoop {
    private let conversationStore: any ConversationStore
    private let memoryStore: WorkspaceMemoryStore
    private let notificationPlanner: NotificationPlanner?

    public init(
        conversationStore: any ConversationStore,
        memoryStore: WorkspaceMemoryStore,
        notificationPlanner: NotificationPlanner? = nil
    ) {
        self.conversationStore = conversationStore
        self.memoryStore = memoryStore
        self.notificationPlanner = notificationPlanner
    }

    public func reflectOnMissionCompletion(
        mission: MissionRecord,
        task: TaskRecord?,
        events: [TaskEvent]
    ) async throws -> ReflectionResult {
        guard mission.status == .completed, let workspaceID = mission.workspaceID else {
            return ReflectionResult()
        }
        if try await memoryStore.candidate(workspaceID: workspaceID, missionID: mission.missionID) != nil {
            return ReflectionResult()
        }

        let interactions = try await conversationStore.interactions(sessionID: mission.rootSessionID, limit: 12)
        let userText = interactions.last { $0.role == .user }?.content ?? mission.brief
        let assistantText = interactions.last { $0.role == .assistant }?.content ?? ""
        let eventSummary = events.last?.summary ?? task?.historyProjection.taskBrief ?? mission.brief
        let summary = [
            "Mission '\(mission.title)' completed.",
            "User intent: \(trimmedLine(userText))",
            "Outcome: \(trimmedLine(eventSummary))",
            assistantText.isEmpty ? nil : "Root response: \(trimmedLine(assistantText))",
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        let candidate = try await memoryStore.append(
            MemoryCandidate(
                workspaceID: workspaceID,
                rootSessionID: mission.rootSessionID,
                missionID: mission.missionID,
                taskID: task?.taskID,
                summary: summary,
                keywords: keywords(from: mission.title + " " + mission.brief),
                metadata: [
                    "mission_title": mission.title,
                    "task_status": task?.status.rawValue ?? "direct",
                ]
            )
        )

        let notification: NotificationRecord?
        if mission.metadata["notify_on_completion"] == "true" {
            notification = try await notificationPlanner?.planMissionCompletion(
                scope: SessionScope.bestEffort(sessionID: mission.rootSessionID),
                mission: mission,
                summary: summary
            )
        } else {
            notification = nil
        }

        return ReflectionResult(candidates: [candidate], notification: notification)
    }

    private func keywords(from text: String) -> [String] {
        Array(
            Set(
                text
                    .lowercased()
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map(String.init)
                    .filter { $0.count >= 4 }
            )
        )
        .sorted()
        .prefix(8)
        .map { $0 }
    }

    private func trimmedLine(_ text: String, limit: Int = 220) -> String {
        let collapsed = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else {
            return collapsed
        }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<endIndex]) + "..."
    }
}
