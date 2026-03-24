import Foundation

public struct DeploymentRecord: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case prepared
        case draining
        case live
        case rollbackReady = "rollback_ready"
        case rolledBack = "rolled_back"
        case failed
    }

    public var releaseID: String
    public var version: String
    public var state: State
    public var drainingTaskIDs: [String]
    public var checkpointDirectory: String?
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        releaseID: String = UUID().uuidString,
        version: String,
        state: State,
        drainingTaskIDs: [String] = [],
        checkpointDirectory: String? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.releaseID = releaseID
        self.version = version
        self.state = state
        self.drainingTaskIDs = drainingTaskIDs
        self.checkpointDirectory = checkpointDirectory
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
