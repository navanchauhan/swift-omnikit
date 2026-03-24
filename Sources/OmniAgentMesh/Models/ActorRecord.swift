import Foundation

public struct ActorRecord: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case human
        case service
        case system
    }

    public var actorID: ActorID
    public var displayName: String
    public var kind: Kind
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        actorID: ActorID,
        displayName: String,
        kind: Kind = .human,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.actorID = actorID
        self.displayName = displayName
        self.kind = kind
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
