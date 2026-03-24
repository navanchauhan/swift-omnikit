import Foundation
import OmniAgentMesh

public struct RootConversationSnapshot: Sendable, Equatable {
    public var summary: ConversationSummary?
    public var hotContext: [InteractionItem]
    public var unresolvedNotifications: [NotificationRecord]

    public init(
        summary: ConversationSummary?,
        hotContext: [InteractionItem],
        unresolvedNotifications: [NotificationRecord]
    ) {
        self.summary = summary
        self.hotContext = hotContext
        self.unresolvedNotifications = unresolvedNotifications
    }
}

public actor RootConversation {
    public let sessionID: String
    public let scope: SessionScope

    private let store: any ConversationStore
    private let hotWindowLimit: Int

    public init(scope: SessionScope, store: any ConversationStore, hotWindowLimit: Int = 12) {
        self.sessionID = scope.sessionID
        self.scope = scope
        self.store = store
        self.hotWindowLimit = hotWindowLimit
    }

    public init(sessionID: String, store: any ConversationStore, hotWindowLimit: Int = 12) {
        let scope = SessionScope.bestEffort(sessionID: sessionID)
        self.sessionID = sessionID
        self.scope = scope
        self.store = store
        self.hotWindowLimit = hotWindowLimit
    }

    @discardableResult
    public func recordUserText(
        _ content: String,
        actorID: ActorID? = nil,
        metadata: [String: String] = [:]
    ) async throws -> InteractionItem {
        try await append(role: .user, modality: .text, actorID: actorID, content: content, metadata: metadata)
    }

    @discardableResult
    public func recordAssistantText(_ content: String, metadata: [String: String] = [:]) async throws -> InteractionItem {
        try await append(role: .assistant, modality: .chat, content: content, metadata: metadata)
    }

    @discardableResult
    public func recordAudioTranscript(
        _ content: String,
        actorID: ActorID? = nil,
        metadata: [String: String] = [:]
    ) async throws -> InteractionItem {
        try await append(role: .user, modality: .audioTranscript, actorID: actorID, content: content, metadata: metadata)
    }

    public func recordNotification(_ notification: NotificationRecord) async throws {
        _ = try await append(
            role: .worker,
            modality: .notification,
            content: "\(notification.title): \(notification.body)",
            metadata: [
                "notification_id": notification.notificationID,
                "task_id": notification.taskID ?? "",
                "importance": notification.importance.rawValue,
                "status": notification.status.rawValue,
            ]
        )
    }

    public func snapshot() async throws -> RootConversationSnapshot {
        RootConversationSnapshot(
            summary: try await store.loadSummary(sessionID: sessionID),
            hotContext: try await store.interactions(sessionID: sessionID, limit: hotWindowLimit),
            unresolvedNotifications: try await store.notifications(sessionID: sessionID, unresolvedOnly: true)
        )
    }

    private func append(
        role: InteractionItem.Role,
        modality: InteractionItem.Modality,
        actorID: ActorID? = nil,
        content: String,
        metadata: [String: String]
    ) async throws -> InteractionItem {
        let stored = try await store.appendInteraction(
            InteractionItem(
                sessionID: sessionID,
                actorID: actorID ?? scope.actorID,
                workspaceID: scope.workspaceID,
                channelID: scope.channelID,
                role: role,
                modality: modality,
                content: content,
                metadata: metadata
            )
        )
        try await compactIfNeeded()
        return stored
    }

    private func compactIfNeeded() async throws {
        let allItems = try await store.interactions(sessionID: sessionID, limit: nil)
        guard allItems.count > hotWindowLimit else {
            return
        }

        let existingSummary = try await store.loadSummary(sessionID: sessionID)
        let hotItems = Array(allItems.suffix(hotWindowLimit))
        guard let firstHotSequence = hotItems.first?.sequenceNumber else {
            return
        }

        let lastCompactedSequence = existingSummary?.lastCompactedSequence ?? 0
        let compactableItems = allItems.filter { item in
            item.sequenceNumber > lastCompactedSequence && item.sequenceNumber < firstHotSequence
        }
        guard let newestCompactedSequence = compactableItems.last?.sequenceNumber else {
            return
        }

        let chunk = compactableItems
            .map { item in "\(item.role.rawValue)/\(item.modality.rawValue): \(item.content)" }
            .joined(separator: "\n")
        let previousSummary = existingSummary?.summaryText ?? ""
        let summaryText = [previousSummary, chunk]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        try await store.saveSummary(
            ConversationSummary(
                sessionID: sessionID,
                workspaceID: scope.workspaceID,
                channelID: scope.channelID,
                summaryText: summaryText,
                hotWindowLimit: hotWindowLimit,
                lastCompactedSequence: newestCompactedSequence
            )
        )
    }
}
