import Foundation
import OmniAgentMesh

public struct SupervisorSweepReport: Sendable, Equatable {
    public var recoveredTaskIDs: [String]
    public var stalledTasks: [TaskStallRecord]
    public var notificationIDs: [String]

    public init(
        recoveredTaskIDs: [String] = [],
        stalledTasks: [TaskStallRecord] = [],
        notificationIDs: [String] = []
    ) {
        self.recoveredTaskIDs = recoveredTaskIDs
        self.stalledTasks = stalledTasks
        self.notificationIDs = notificationIDs
    }
}

public actor SupervisorService {
    private let jobStore: any JobStore
    private let conversationStore: any ConversationStore
    private let watchdog: TimeoutWatchdog

    public init(
        jobStore: any JobStore,
        conversationStore: any ConversationStore,
        watchdog: TimeoutWatchdog
    ) {
        self.jobStore = jobStore
        self.conversationStore = conversationStore
        self.watchdog = watchdog
    }

    public func reconcile(now: Date = Date()) async throws -> SupervisorSweepReport {
        let recovered = try await jobStore.recoverOrphanedTasks(now: now)
        let stalls = try await watchdog.stalledTasks(now: now)
        var notificationIDs: [String] = []

        for stall in stalls {
            let notificationID = "watchdog.\(stall.task.taskID).\(stall.reason.rawValue)"
            let existing = try await conversationStore.notifications(
                sessionID: stall.task.rootSessionID,
                unresolvedOnly: false
            )
            if !existing.contains(where: { $0.notificationID == notificationID }) {
                _ = try await conversationStore.saveNotification(
                    NotificationRecord(
                        notificationID: notificationID,
                        sessionID: stall.task.rootSessionID,
                        actorID: stall.task.requesterActorID,
                        workspaceID: stall.task.workspaceID,
                        channelID: stall.task.channelID,
                        taskID: stall.task.taskID,
                        title: "Task Attention Required",
                        body: stall.summary,
                        importance: .urgent,
                        metadata: [
                            "supervision_reason": stall.reason.rawValue,
                            "task_id": stall.task.taskID,
                        ],
                        createdAt: now
                    )
                )
                notificationIDs.append(notificationID)
            }

            switch stall.task.restartPolicy {
            case .none:
                break
            case .retryStage, .retryMission, .escalate:
                _ = try? await jobStore.failTask(
                    taskID: stall.task.taskID,
                    workerID: nil,
                    summary: stall.summary,
                    idempotencyKey: "watchdog.fail.\(stall.task.taskID).\(stall.reason.rawValue)",
                    now: now
                )
            }
        }

        return SupervisorSweepReport(
            recoveredTaskIDs: recovered.map(\.taskID),
            stalledTasks: stalls,
            notificationIDs: notificationIDs
        )
    }

    public func runLoop(interval: Duration = .seconds(5)) async throws {
        while !Task.isCancelled {
            _ = try await reconcile(now: Date())
            try await Task.sleep(for: interval)
        }
    }
}
