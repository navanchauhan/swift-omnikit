import Foundation
import OmniAgentMesh

public struct InteractionInboxItem: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case notification
        case approval
        case question
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var body: String
    public var status: String
    public var createdAt: Date
    public var metadata: [String: String]

    public init(
        id: String,
        kind: Kind,
        title: String,
        body: String,
        status: String,
        createdAt: Date,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.status = status
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public actor InteractionBroker {
    private let missionStore: any MissionStore
    private let conversationStore: any ConversationStore
    private let deliveryStore: (any DeliveryStore)?
    private let notificationPolicy: NotificationPolicy

    public init(
        missionStore: any MissionStore,
        conversationStore: any ConversationStore,
        deliveryStore: (any DeliveryStore)? = nil,
        notificationPolicy: NotificationPolicy = NotificationPolicy()
    ) {
        self.missionStore = missionStore
        self.conversationStore = conversationStore
        self.deliveryStore = deliveryStore
        self.notificationPolicy = notificationPolicy
    }

    @discardableResult
    public func requestApproval(
        scope: SessionScope,
        title: String,
        prompt: String,
        missionID: String? = nil,
        taskID: String? = nil,
        requesterActorID: ActorID? = nil,
        sensitive: Bool = true,
        policy: WorkspacePolicy = WorkspacePolicy(),
        metadata: [String: String] = [:]
    ) async throws -> ApprovalRequestRecord {
        let request = ApprovalRequestRecord(
            missionID: missionID,
            taskID: taskID,
            rootSessionID: scope.sessionID,
            requesterActorID: requesterActorID ?? scope.actorID,
            workspaceID: scope.workspaceID,
            channelID: scope.channelID,
            title: title,
            prompt: prompt,
            sensitive: sensitive,
            deliveryPreference: sensitive && policy.sensitiveInteractionDelivery == .directMessage ? .directMessage : .sameChannel,
            metadata: metadata
        )
        let stored = try await missionStore.saveApprovalRequest(request)
        try await enqueueNotification(
            scope: scope,
            notificationID: "approval.\(stored.requestID)",
            title: "Approval Needed",
            body: "\(title): \(prompt)",
            importance: .urgent,
            metadata: [
                "interaction_kind": "approval",
                "request_id": stored.requestID,
                "delivery_preference": stored.deliveryPreference.rawValue,
            ]
        )
        try await savePromptDelivery(
            scope: scope,
            requestID: stored.requestID,
            kind: .approval,
            title: title,
            body: prompt,
            deliveryPreference: stored.deliveryPreference.rawValue,
            metadata: metadata.merging([
                "interaction_title": title,
                "sensitive": sensitive ? "true" : "false",
            ]) { _, new in new }
        )
        return stored
    }

    @discardableResult
    public func requestQuestion(
        scope: SessionScope,
        title: String,
        prompt: String,
        kind: QuestionRequestRecord.Kind = .freeText,
        options: [String] = [],
        missionID: String? = nil,
        taskID: String? = nil,
        requesterActorID: ActorID? = nil,
        metadata: [String: String] = [:]
    ) async throws -> QuestionRequestRecord {
        let request = QuestionRequestRecord(
            missionID: missionID,
            taskID: taskID,
            rootSessionID: scope.sessionID,
            requesterActorID: requesterActorID ?? scope.actorID,
            workspaceID: scope.workspaceID,
            channelID: scope.channelID,
            title: title,
            prompt: prompt,
            kind: kind,
            options: options,
            metadata: metadata
        )
        let stored = try await missionStore.saveQuestionRequest(request)
        try await enqueueNotification(
            scope: scope,
            notificationID: "question.\(stored.requestID)",
            title: "Question Pending",
            body: "\(title): \(prompt)",
            importance: .important,
            metadata: [
                "interaction_kind": "question",
                "request_id": stored.requestID,
            ]
        )
        try await savePromptDelivery(
            scope: scope,
            requestID: stored.requestID,
            kind: .question,
            title: title,
            body: prompt,
            deliveryPreference: ApprovalRequestRecord.DeliveryPreference.sameChannel.rawValue,
            metadata: metadata.merging([
                "interaction_title": title,
                "question_kind": kind.rawValue,
                "question_options": options.joined(separator: "\u{1F}"),
            ]) { _, new in new }
        )
        return stored
    }

    public func listInbox(
        scope: SessionScope,
        unresolvedOnly: Bool = true
    ) async throws -> [InteractionInboxItem] {
        let notifications = try await conversationStore.notifications(sessionID: scope.sessionID, unresolvedOnly: unresolvedOnly)
        let approvalStatuses: [ApprovalRequestRecord.Status]? = unresolvedOnly ? [.pending, .deferred] : nil
        let questionStatuses: [QuestionRequestRecord.Status]? = unresolvedOnly ? [.pending, .deferred] : nil
        let approvals = try await missionStore.approvalRequests(
            sessionID: scope.sessionID,
            workspaceID: scope.workspaceID,
            statuses: approvalStatuses
        )
        let questions = try await missionStore.questionRequests(
            sessionID: scope.sessionID,
            workspaceID: scope.workspaceID,
            statuses: questionStatuses
        )

        return notifications.map {
            InteractionInboxItem(
                id: $0.notificationID,
                kind: .notification,
                title: $0.title,
                body: $0.body,
                status: $0.status.rawValue,
                createdAt: $0.createdAt,
                metadata: $0.metadata
            )
        } + approvals.map {
            InteractionInboxItem(
                id: $0.requestID,
                kind: .approval,
                title: $0.title,
                body: $0.prompt,
                status: $0.status.rawValue,
                createdAt: $0.createdAt,
                metadata: $0.metadata
            )
        } + questions.map {
            InteractionInboxItem(
                id: $0.requestID,
                kind: .question,
                title: $0.title,
                body: $0.prompt,
                status: $0.status.rawValue,
                createdAt: $0.createdAt,
                metadata: $0.metadata
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }

    public func approve(
        requestID: String,
        approved: Bool,
        actorID: ActorID? = nil,
        responseText: String? = nil,
        at: Date = Date()
    ) async throws -> ApprovalRequestRecord {
        guard var request = try await missionStore.approvalRequest(requestID: requestID) else {
            throw InteractionBrokerError.approvalNotFound(requestID)
        }
        request.status = approved ? .approved : .rejected
        request.responseActorID = actorID
        request.responseText = responseText
        request.respondedAt = at
        request.updatedAt = at
        let stored = try await missionStore.saveApprovalRequest(request)
        _ = try await conversationStore.markNotificationResolved(notificationID: "approval.\(requestID)", at: at)
        return stored
    }

    public func answerQuestion(
        requestID: String,
        answerText: String,
        actorID: ActorID? = nil,
        at: Date = Date()
    ) async throws -> QuestionRequestRecord {
        guard var request = try await missionStore.questionRequest(requestID: requestID) else {
            throw InteractionBrokerError.questionNotFound(requestID)
        }
        request.status = .answered
        request.answerActorID = actorID
        request.answerText = answerText
        request.answeredAt = at
        request.updatedAt = at
        let stored = try await missionStore.saveQuestionRequest(request)
        _ = try await conversationStore.markNotificationResolved(notificationID: "question.\(requestID)", at: at)
        return stored
    }

    private func enqueueNotification(
        scope: SessionScope,
        notificationID: String,
        title: String,
        body: String,
        importance: NotificationRecord.Importance,
        metadata: [String: String]
    ) async throws {
        let inbox = NotificationInbox(scope: scope, store: conversationStore, policy: notificationPolicy)
        _ = try await inbox.enqueue(
            notificationID: notificationID,
            title: title,
            body: body,
            importance: importance,
            metadata: metadata
        )
    }

    private func savePromptDelivery(
        scope: SessionScope,
        requestID: String,
        kind: InteractionInboxItem.Kind,
        title: String,
        body: String,
        deliveryPreference: String,
        metadata: [String: String]
    ) async throws {
        guard let deliveryStore else {
            return
        }
        _ = try await deliveryStore.saveDelivery(
            DeliveryRecord(
                idempotencyKey: "interaction.\(kind.rawValue).\(requestID)",
                direction: .outbound,
                transport: .custom,
                sessionID: scope.sessionID,
                actorID: scope.actorID,
                workspaceID: scope.workspaceID,
                channelID: scope.channelID,
                status: .deferred,
                summary: "\(title): \(body)",
                metadata: metadata.merging([
                    "interaction_kind": kind.rawValue,
                    "request_id": requestID,
                    "delivery_preference": deliveryPreference,
                ]) { _, new in new }
            )
        )
    }
}

public enum InteractionBrokerError: Error, CustomStringConvertible {
    case approvalNotFound(String)
    case questionNotFound(String)

    public var description: String {
        switch self {
        case .approvalNotFound(let requestID):
            return "Approval request \(requestID) was not found."
        case .questionNotFound(let requestID):
            return "Question request \(requestID) was not found."
        }
    }
}
