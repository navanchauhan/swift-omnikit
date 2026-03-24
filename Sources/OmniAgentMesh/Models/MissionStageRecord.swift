import Foundation

public struct MissionStageRecord: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case stageID
        case missionID
        case rootSessionID
        case workspaceID
        case channelID
        case taskID
        case parentStageID
        case kind
        case executionMode
        case title
        case status
        case attemptCount
        case maxAttempts
        case deadlineAt
        case artifactRefs
        case metadata
        case createdAt
        case updatedAt
        case completedAt
    }

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case plan
        case implement
        case review
        case scenario
        case judge
        case approval
        case question
        case direct
        case finalize
    }

    public enum Status: String, Codable, Sendable, CaseIterable {
        case pending
        case running
        case waiting
        case completed
        case failed
        case cancelled

        public var isTerminal: Bool {
            switch self {
            case .completed, .failed, .cancelled:
                return true
            case .pending, .running, .waiting:
                return false
            }
        }
    }

    public var stageID: String
    public var missionID: String
    public var rootSessionID: String
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var taskID: String?
    public var parentStageID: String?
    public var kind: Kind
    public var executionMode: MissionRecord.ExecutionMode
    public var title: String
    public var status: Status
    public var attemptCount: Int
    public var maxAttempts: Int
    public var deadlineAt: Date?
    public var artifactRefs: [String]
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(
        stageID: String = UUID().uuidString,
        missionID: String,
        rootSessionID: String,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        taskID: String? = nil,
        parentStageID: String? = nil,
        kind: Kind,
        executionMode: MissionRecord.ExecutionMode,
        title: String,
        status: Status = .pending,
        attemptCount: Int = 0,
        maxAttempts: Int = 1,
        deadlineAt: Date? = nil,
        artifactRefs: [String] = [],
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        let resolvedScope = SessionScope.bestEffort(sessionID: rootSessionID)
        self.stageID = stageID
        self.missionID = missionID
        self.rootSessionID = rootSessionID
        self.workspaceID = workspaceID ?? resolvedScope.workspaceID
        self.channelID = channelID ?? resolvedScope.channelID
        self.taskID = taskID
        self.parentStageID = parentStageID
        self.kind = kind
        self.executionMode = executionMode
        self.title = title
        self.status = status
        self.attemptCount = max(0, attemptCount)
        self.maxAttempts = max(1, maxAttempts)
        self.deadlineAt = deadlineAt
        self.artifactRefs = Array(Set(artifactRefs)).sorted()
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rootSessionID = try container.decode(String.self, forKey: .rootSessionID)
        let resolvedScope = SessionScope.bestEffort(sessionID: rootSessionID)
        self.stageID = try container.decode(String.self, forKey: .stageID)
        self.missionID = try container.decode(String.self, forKey: .missionID)
        self.rootSessionID = rootSessionID
        self.workspaceID = try container.decodeIfPresent(WorkspaceID.self, forKey: .workspaceID) ?? resolvedScope.workspaceID
        self.channelID = try container.decodeIfPresent(ChannelID.self, forKey: .channelID) ?? resolvedScope.channelID
        self.taskID = try container.decodeIfPresent(String.self, forKey: .taskID)
        self.parentStageID = try container.decodeIfPresent(String.self, forKey: .parentStageID)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.executionMode = try container.decode(MissionRecord.ExecutionMode.self, forKey: .executionMode)
        self.title = try container.decode(String.self, forKey: .title)
        self.status = try container.decode(Status.self, forKey: .status)
        self.attemptCount = try container.decode(Int.self, forKey: .attemptCount)
        self.maxAttempts = try container.decode(Int.self, forKey: .maxAttempts)
        self.deadlineAt = try container.decodeIfPresent(Date.self, forKey: .deadlineAt)
        self.artifactRefs = try container.decode([String].self, forKey: .artifactRefs)
        self.metadata = try container.decode([String: String].self, forKey: .metadata)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stageID, forKey: .stageID)
        try container.encode(missionID, forKey: .missionID)
        try container.encode(rootSessionID, forKey: .rootSessionID)
        try container.encodeIfPresent(workspaceID, forKey: .workspaceID)
        try container.encodeIfPresent(channelID, forKey: .channelID)
        try container.encodeIfPresent(taskID, forKey: .taskID)
        try container.encodeIfPresent(parentStageID, forKey: .parentStageID)
        try container.encode(kind, forKey: .kind)
        try container.encode(executionMode, forKey: .executionMode)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(attemptCount, forKey: .attemptCount)
        try container.encode(maxAttempts, forKey: .maxAttempts)
        try container.encodeIfPresent(deadlineAt, forKey: .deadlineAt)
        try container.encode(artifactRefs, forKey: .artifactRefs)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}
