import Foundation

public struct SubAgentLineage: Codable, Sendable, Equatable {
    public var taskID: String?
    public var parentTaskID: String?
    public var historyProjectionSummary: String?

    public init(taskID: String? = nil, parentTaskID: String? = nil, historyProjectionSummary: String? = nil) {
        self.taskID = taskID
        self.parentTaskID = parentTaskID
        self.historyProjectionSummary = historyProjectionSummary
    }
}

public struct SubAgentHandle: Sendable {
    public var id: String
    public var session: Session
    public var status: SubAgentStatus
    public var lineage: SubAgentLineage?

    public init(
        id: String,
        session: Session,
        status: SubAgentStatus = .running,
        lineage: SubAgentLineage? = nil
    ) {
        self.id = id
        self.session = session
        self.status = status
        self.lineage = lineage
    }
}

public enum SubAgentStatus: String, Sendable {
    case running
    case completed
    case failed
}

public struct SubAgentResult: Sendable {
    public var output: String
    public var success: Bool
    public var turnsUsed: Int
    public var taskID: String?
    public var artifactRefs: [String]

    public init(
        output: String,
        success: Bool,
        turnsUsed: Int,
        taskID: String? = nil,
        artifactRefs: [String] = []
    ) {
        self.output = output
        self.success = success
        self.turnsUsed = turnsUsed
        self.taskID = taskID
        self.artifactRefs = artifactRefs
    }
}
