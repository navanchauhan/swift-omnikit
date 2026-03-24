import Foundation

public struct ApprovalRequestRecord: Codable, Sendable, Equatable {
    public enum DeliveryPreference: String, Codable, Sendable {
        case sameChannel = "same_channel"
        case directMessage = "direct_message"
        case workspaceDefault = "workspace_default"
    }

    public enum Status: String, Codable, Sendable, CaseIterable {
        case pending
        case approved
        case rejected
        case cancelled
        case deferred
    }

    public var requestID: String
    public var missionID: String?
    public var taskID: String?
    public var rootSessionID: String
    public var requesterActorID: ActorID?
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var title: String
    public var prompt: String
    public var sensitive: Bool
    public var deliveryPreference: DeliveryPreference
    public var status: Status
    public var responseActorID: ActorID?
    public var responseText: String?
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date
    public var respondedAt: Date?

    public init(
        requestID: String = UUID().uuidString,
        missionID: String? = nil,
        taskID: String? = nil,
        rootSessionID: String,
        requesterActorID: ActorID? = nil,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        title: String,
        prompt: String,
        sensitive: Bool = true,
        deliveryPreference: DeliveryPreference = .workspaceDefault,
        status: Status = .pending,
        responseActorID: ActorID? = nil,
        responseText: String? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        respondedAt: Date? = nil
    ) {
        let resolvedScope = SessionScope.bestEffort(sessionID: rootSessionID)
        self.requestID = requestID
        self.missionID = missionID
        self.taskID = taskID
        self.rootSessionID = rootSessionID
        self.requesterActorID = requesterActorID ?? resolvedScope.actorID
        self.workspaceID = workspaceID ?? resolvedScope.workspaceID
        self.channelID = channelID ?? resolvedScope.channelID
        self.title = title
        self.prompt = prompt
        self.sensitive = sensitive
        self.deliveryPreference = deliveryPreference
        self.status = status
        self.responseActorID = responseActorID
        self.responseText = responseText
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.respondedAt = respondedAt
    }
}
