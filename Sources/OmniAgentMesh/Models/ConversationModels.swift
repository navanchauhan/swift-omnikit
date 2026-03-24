import Foundation

public struct InteractionItem: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case itemID
        case sessionID
        case actorID
        case workspaceID
        case channelID
        case sequenceNumber
        case role
        case modality
        case content
        case metadata
        case createdAt
    }

    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
        case worker
    }

    public enum Modality: String, Codable, Sendable {
        case text
        case chat
        case audioTranscript = "audio_transcript"
        case notification
        case summary
    }

    public var itemID: String
    public var sessionID: String
    public var actorID: ActorID?
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var sequenceNumber: Int
    public var role: Role
    public var modality: Modality
    public var content: String
    public var metadata: [String: String]
    public var createdAt: Date

    public init(
        itemID: String = UUID().uuidString,
        sessionID: String,
        actorID: ActorID? = nil,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        sequenceNumber: Int = 0,
        role: Role,
        modality: Modality,
        content: String,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        let resolvedScope = SessionScope.bestEffort(sessionID: sessionID)
        self.itemID = itemID
        self.sessionID = sessionID
        self.actorID = actorID ?? resolvedScope.actorID
        self.workspaceID = workspaceID ?? resolvedScope.workspaceID
        self.channelID = channelID ?? resolvedScope.channelID
        self.sequenceNumber = sequenceNumber
        self.role = role
        self.modality = modality
        self.content = content
        self.metadata = metadata
        self.createdAt = createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sessionID = try container.decode(String.self, forKey: .sessionID)
        let resolvedScope = SessionScope.bestEffort(sessionID: sessionID)
        self.itemID = try container.decode(String.self, forKey: .itemID)
        self.sessionID = sessionID
        self.actorID = try container.decodeIfPresent(ActorID.self, forKey: .actorID) ?? resolvedScope.actorID
        self.workspaceID = try container.decodeIfPresent(WorkspaceID.self, forKey: .workspaceID) ?? resolvedScope.workspaceID
        self.channelID = try container.decodeIfPresent(ChannelID.self, forKey: .channelID) ?? resolvedScope.channelID
        self.sequenceNumber = try container.decode(Int.self, forKey: .sequenceNumber)
        self.role = try container.decode(Role.self, forKey: .role)
        self.modality = try container.decode(Modality.self, forKey: .modality)
        self.content = try container.decode(String.self, forKey: .content)
        self.metadata = try container.decode([String: String].self, forKey: .metadata)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemID, forKey: .itemID)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(actorID, forKey: .actorID)
        try container.encodeIfPresent(workspaceID, forKey: .workspaceID)
        try container.encodeIfPresent(channelID, forKey: .channelID)
        try container.encode(sequenceNumber, forKey: .sequenceNumber)
        try container.encode(role, forKey: .role)
        try container.encode(modality, forKey: .modality)
        try container.encode(content, forKey: .content)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public struct ConversationSummary: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case sessionID
        case workspaceID
        case channelID
        case summaryText
        case hotWindowLimit
        case lastCompactedSequence
        case updatedAt
    }

    public var sessionID: String
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var summaryText: String
    public var hotWindowLimit: Int
    public var lastCompactedSequence: Int
    public var updatedAt: Date

    public init(
        sessionID: String,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        summaryText: String,
        hotWindowLimit: Int,
        lastCompactedSequence: Int,
        updatedAt: Date = Date()
    ) {
        let resolvedScope = SessionScope.bestEffort(sessionID: sessionID)
        self.sessionID = sessionID
        self.workspaceID = workspaceID ?? resolvedScope.workspaceID
        self.channelID = channelID ?? resolvedScope.channelID
        self.summaryText = summaryText
        self.hotWindowLimit = hotWindowLimit
        self.lastCompactedSequence = lastCompactedSequence
        self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sessionID = try container.decode(String.self, forKey: .sessionID)
        let resolvedScope = SessionScope.bestEffort(sessionID: sessionID)
        self.sessionID = sessionID
        self.workspaceID = try container.decodeIfPresent(WorkspaceID.self, forKey: .workspaceID) ?? resolvedScope.workspaceID
        self.channelID = try container.decodeIfPresent(ChannelID.self, forKey: .channelID) ?? resolvedScope.channelID
        self.summaryText = try container.decode(String.self, forKey: .summaryText)
        self.hotWindowLimit = try container.decode(Int.self, forKey: .hotWindowLimit)
        self.lastCompactedSequence = try container.decode(Int.self, forKey: .lastCompactedSequence)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(workspaceID, forKey: .workspaceID)
        try container.encodeIfPresent(channelID, forKey: .channelID)
        try container.encode(summaryText, forKey: .summaryText)
        try container.encode(hotWindowLimit, forKey: .hotWindowLimit)
        try container.encode(lastCompactedSequence, forKey: .lastCompactedSequence)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct NotificationRecord: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case notificationID
        case sessionID
        case actorID
        case workspaceID
        case channelID
        case taskID
        case title
        case body
        case importance
        case status
        case metadata
        case createdAt
        case deliveredAt
        case resolvedAt
    }

    public enum Importance: String, Codable, Sendable, Comparable {
        case passive
        case important
        case urgent

        public static func < (lhs: Importance, rhs: Importance) -> Bool {
            lhs.rank < rhs.rank
        }

        private var rank: Int {
            switch self {
            case .passive:
                return 0
            case .important:
                return 1
            case .urgent:
                return 2
            }
        }
    }

    public enum Status: String, Codable, Sendable {
        case unread
        case delivered
        case resolved
    }

    public var notificationID: String
    public var sessionID: String
    public var actorID: ActorID?
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var taskID: String?
    public var title: String
    public var body: String
    public var importance: Importance
    public var status: Status
    public var metadata: [String: String]
    public var createdAt: Date
    public var deliveredAt: Date?
    public var resolvedAt: Date?

    public init(
        notificationID: String = UUID().uuidString,
        sessionID: String,
        actorID: ActorID? = nil,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        taskID: String? = nil,
        title: String,
        body: String,
        importance: Importance = .passive,
        status: Status = .unread,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        deliveredAt: Date? = nil,
        resolvedAt: Date? = nil
    ) {
        let resolvedScope = SessionScope.bestEffort(sessionID: sessionID)
        self.notificationID = notificationID
        self.sessionID = sessionID
        self.actorID = actorID ?? resolvedScope.actorID
        self.workspaceID = workspaceID ?? resolvedScope.workspaceID
        self.channelID = channelID ?? resolvedScope.channelID
        self.taskID = taskID
        self.title = title
        self.body = body
        self.importance = importance
        self.status = status
        self.metadata = metadata
        self.createdAt = createdAt
        self.deliveredAt = deliveredAt
        self.resolvedAt = resolvedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sessionID = try container.decode(String.self, forKey: .sessionID)
        let resolvedScope = SessionScope.bestEffort(sessionID: sessionID)
        self.notificationID = try container.decode(String.self, forKey: .notificationID)
        self.sessionID = sessionID
        self.actorID = try container.decodeIfPresent(ActorID.self, forKey: .actorID) ?? resolvedScope.actorID
        self.workspaceID = try container.decodeIfPresent(WorkspaceID.self, forKey: .workspaceID) ?? resolvedScope.workspaceID
        self.channelID = try container.decodeIfPresent(ChannelID.self, forKey: .channelID) ?? resolvedScope.channelID
        self.taskID = try container.decodeIfPresent(String.self, forKey: .taskID)
        self.title = try container.decode(String.self, forKey: .title)
        self.body = try container.decode(String.self, forKey: .body)
        self.importance = try container.decode(Importance.self, forKey: .importance)
        self.status = try container.decode(Status.self, forKey: .status)
        self.metadata = try container.decode([String: String].self, forKey: .metadata)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.deliveredAt = try container.decodeIfPresent(Date.self, forKey: .deliveredAt)
        self.resolvedAt = try container.decodeIfPresent(Date.self, forKey: .resolvedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(notificationID, forKey: .notificationID)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(actorID, forKey: .actorID)
        try container.encodeIfPresent(workspaceID, forKey: .workspaceID)
        try container.encodeIfPresent(channelID, forKey: .channelID)
        try container.encodeIfPresent(taskID, forKey: .taskID)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(importance, forKey: .importance)
        try container.encode(status, forKey: .status)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(deliveredAt, forKey: .deliveredAt)
        try container.encodeIfPresent(resolvedAt, forKey: .resolvedAt)
    }
}
