import Foundation

public struct ChannelBinding: Codable, Sendable, Equatable {
    public enum Transport: String, Codable, Sendable {
        case local
        case telegram
        case imessage
        case http
        case api
        case test
        case custom
    }

    public var bindingID: String
    public var transport: Transport
    public var externalID: String
    public var workspaceID: WorkspaceID
    public var channelID: ChannelID
    public var actorID: ActorID?
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        bindingID: String = UUID().uuidString,
        transport: Transport,
        externalID: String,
        workspaceID: WorkspaceID,
        channelID: ChannelID,
        actorID: ActorID? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.bindingID = bindingID
        self.transport = transport
        self.externalID = externalID
        self.workspaceID = workspaceID
        self.channelID = channelID
        self.actorID = actorID
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
