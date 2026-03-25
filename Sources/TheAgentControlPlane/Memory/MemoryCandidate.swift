import Foundation
import OmniAgentMesh

public struct MemoryCandidate: Codable, Sendable, Equatable {
    public var candidateID: String
    public var workspaceID: WorkspaceID
    public var rootSessionID: String
    public var missionID: String?
    public var taskID: String?
    public var summary: String
    public var keywords: [String]
    public var metadata: [String: String]
    public var createdAt: Date

    public init(
        candidateID: String = UUID().uuidString,
        workspaceID: WorkspaceID,
        rootSessionID: String,
        missionID: String? = nil,
        taskID: String? = nil,
        summary: String,
        keywords: [String] = [],
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.candidateID = candidateID
        self.workspaceID = workspaceID
        self.rootSessionID = rootSessionID
        self.missionID = missionID
        self.taskID = taskID
        self.summary = summary
        self.keywords = keywords
        self.metadata = metadata
        self.createdAt = createdAt
    }
}
