import Foundation

public struct DeliveryRecord: Codable, Sendable, Equatable {
    public enum Direction: String, Codable, Sendable {
        case inbound
        case outbound
    }

    public enum Status: String, Codable, Sendable {
        case received
        case processed
        case delivered
        case ignored
        case duplicate
        case failed
        case deferred
    }

    public var deliveryID: String
    public var idempotencyKey: String
    public var direction: Direction
    public var transport: ChannelBinding.Transport
    public var sessionID: String?
    public var actorID: ActorID?
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var messageID: String?
    public var status: Status
    public var summary: String?
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        deliveryID: String = UUID().uuidString,
        idempotencyKey: String,
        direction: Direction,
        transport: ChannelBinding.Transport,
        sessionID: String? = nil,
        actorID: ActorID? = nil,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        messageID: String? = nil,
        status: Status,
        summary: String? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.deliveryID = deliveryID
        self.idempotencyKey = idempotencyKey
        self.direction = direction
        self.transport = transport
        self.sessionID = sessionID
        self.actorID = actorID
        self.workspaceID = workspaceID
        self.channelID = channelID
        self.messageID = messageID
        self.status = status
        self.summary = summary
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
