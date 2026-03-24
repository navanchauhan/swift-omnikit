import Foundation

public struct InteractionItem: Codable, Sendable, Equatable {
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
    public var sequenceNumber: Int
    public var role: Role
    public var modality: Modality
    public var content: String
    public var metadata: [String: String]
    public var createdAt: Date

    public init(
        itemID: String = UUID().uuidString,
        sessionID: String,
        sequenceNumber: Int = 0,
        role: Role,
        modality: Modality,
        content: String,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.itemID = itemID
        self.sessionID = sessionID
        self.sequenceNumber = sequenceNumber
        self.role = role
        self.modality = modality
        self.content = content
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct ConversationSummary: Codable, Sendable, Equatable {
    public var sessionID: String
    public var summaryText: String
    public var hotWindowLimit: Int
    public var lastCompactedSequence: Int
    public var updatedAt: Date

    public init(
        sessionID: String,
        summaryText: String,
        hotWindowLimit: Int,
        lastCompactedSequence: Int,
        updatedAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.summaryText = summaryText
        self.hotWindowLimit = hotWindowLimit
        self.lastCompactedSequence = lastCompactedSequence
        self.updatedAt = updatedAt
    }
}

public struct NotificationRecord: Codable, Sendable, Equatable {
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
        self.notificationID = notificationID
        self.sessionID = sessionID
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
}
