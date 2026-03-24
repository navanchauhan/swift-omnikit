import Foundation
import OmniAgentMesh

public actor NotificationInbox {
    public let sessionID: String
    public let scope: SessionScope

    private let store: any ConversationStore
    private let policy: NotificationPolicy

    public init(scope: SessionScope, store: any ConversationStore, policy: NotificationPolicy = NotificationPolicy()) {
        self.sessionID = scope.sessionID
        self.scope = scope
        self.store = store
        self.policy = policy
    }

    public init(sessionID: String, store: any ConversationStore, policy: NotificationPolicy = NotificationPolicy()) {
        let scope = SessionScope.bestEffort(sessionID: sessionID)
        self.sessionID = sessionID
        self.scope = scope
        self.store = store
        self.policy = policy
    }

    public func enqueue(
        notificationID: String? = nil,
        taskID: String? = nil,
        title: String,
        body: String,
        importance: NotificationRecord.Importance = .passive,
        metadata: [String: String] = [:]
    ) async throws -> NotificationRecord {
        let notification = NotificationRecord(
            notificationID: notificationID ?? UUID().uuidString,
            sessionID: sessionID,
            actorID: scope.actorID,
            workspaceID: scope.workspaceID,
            channelID: scope.channelID,
            taskID: taskID,
            title: title,
            body: body,
            importance: importance,
            metadata: metadata
        )
        let stored = try await store.saveNotification(notification)
        if policy.shouldInterruptUser(for: stored) {
            return try await deliver(notificationID: stored.notificationID) ?? stored
        }
        return stored
    }

    public func deliver(notificationID: String, at: Date = Date()) async throws -> NotificationRecord? {
        try await store.markNotificationDelivered(notificationID: notificationID, at: at)
    }

    public func resolve(notificationID: String, at: Date = Date()) async throws -> NotificationRecord? {
        try await store.markNotificationResolved(notificationID: notificationID, at: at)
    }

    public func unresolved() async throws -> [NotificationRecord] {
        try await store.notifications(sessionID: sessionID, unresolvedOnly: true)
    }

    public func all() async throws -> [NotificationRecord] {
        try await store.notifications(sessionID: sessionID, unresolvedOnly: false)
    }
}
