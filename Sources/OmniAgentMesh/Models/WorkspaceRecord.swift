import Foundation

public struct WorkspaceRecord: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case personal
        case shared
        case service
    }

    public var workspaceID: WorkspaceID
    public var displayName: String
    public var kind: Kind
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        workspaceID: WorkspaceID,
        displayName: String,
        kind: Kind = .personal,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.workspaceID = workspaceID
        self.displayName = displayName
        self.kind = kind
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
