import Foundation

public struct TaskRecord: Codable, Sendable, Equatable {
    public struct Lease: Codable, Sendable, Equatable {
        public var ownerID: String
        public var issuedAt: Date
        public var expiresAt: Date

        public init(ownerID: String, issuedAt: Date, expiresAt: Date) {
            self.ownerID = ownerID
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
        }
    }

    public enum Status: String, Codable, Sendable {
        case submitted
        case assigned
        case running
        case waiting
        case completed
        case failed
        case cancelled
    }

    public var taskID: String
    public var rootSessionID: String
    public var parentTaskID: String?
    public var assignedAgentID: String?
    public var capabilityRequirements: [String]
    public var historyProjection: HistoryProjection
    public var artifactRefs: [String]
    public var priority: Int
    public var lease: Lease?
    public var status: Status
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        taskID: String = UUID().uuidString,
        rootSessionID: String,
        parentTaskID: String? = nil,
        assignedAgentID: String? = nil,
        capabilityRequirements: [String] = [],
        historyProjection: HistoryProjection,
        artifactRefs: [String] = [],
        priority: Int = 0,
        lease: Lease? = nil,
        status: Status = .submitted,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.taskID = taskID
        self.rootSessionID = rootSessionID
        self.parentTaskID = parentTaskID
        self.assignedAgentID = assignedAgentID
        self.capabilityRequirements = Array(Set(capabilityRequirements)).sorted()
        self.historyProjection = historyProjection
        self.artifactRefs = artifactRefs
        self.priority = priority
        self.lease = lease
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
