import Foundation

public struct MissionRecord: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case missionID
        case rootSessionID
        case requesterActorID
        case workspaceID
        case channelID
        case title
        case brief
        case executionMode
        case status
        case primaryTaskID
        case contractArtifactID
        case progressArtifactID
        case verificationArtifactID
        case budgetUnits
        case maxRecursionDepth
        case metadata
        case createdAt
        case updatedAt
        case completedAt
    }

    public enum ExecutionMode: String, Codable, Sendable, CaseIterable {
        case direct
        case workerTask = "worker_task"
        case attractorWorkflow = "attractor_workflow"
    }

    public enum Status: String, Codable, Sendable, CaseIterable {
        case planning
        case awaitingApproval = "awaiting_approval"
        case awaitingUserInput = "awaiting_user_input"
        case executing
        case validating
        case blocked
        case paused
        case completed
        case failed
        case cancelled

        public var isTerminal: Bool {
            switch self {
            case .completed, .failed, .cancelled:
                return true
            case .planning, .awaitingApproval, .awaitingUserInput, .executing, .validating, .blocked, .paused:
                return false
            }
        }
    }

    public var missionID: String
    public var rootSessionID: String
    public var requesterActorID: ActorID?
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var title: String
    public var brief: String
    public var executionMode: ExecutionMode
    public var status: Status
    public var primaryTaskID: String?
    public var contractArtifactID: String?
    public var progressArtifactID: String?
    public var verificationArtifactID: String?
    public var budgetUnits: Int
    public var maxRecursionDepth: Int
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(
        missionID: String = UUID().uuidString,
        rootSessionID: String,
        requesterActorID: ActorID? = nil,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        title: String,
        brief: String,
        executionMode: ExecutionMode,
        status: Status = .planning,
        primaryTaskID: String? = nil,
        contractArtifactID: String? = nil,
        progressArtifactID: String? = nil,
        verificationArtifactID: String? = nil,
        budgetUnits: Int = 1,
        maxRecursionDepth: Int = 2,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        let resolvedScope = SessionScope.bestEffort(sessionID: rootSessionID)
        self.missionID = missionID
        self.rootSessionID = rootSessionID
        self.requesterActorID = requesterActorID ?? resolvedScope.actorID
        self.workspaceID = workspaceID ?? resolvedScope.workspaceID
        self.channelID = channelID ?? resolvedScope.channelID
        self.title = title
        self.brief = brief
        self.executionMode = executionMode
        self.status = status
        self.primaryTaskID = primaryTaskID
        self.contractArtifactID = contractArtifactID
        self.progressArtifactID = progressArtifactID
        self.verificationArtifactID = verificationArtifactID
        self.budgetUnits = budgetUnits
        self.maxRecursionDepth = max(0, maxRecursionDepth)
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rootSessionID = try container.decode(String.self, forKey: .rootSessionID)
        let resolvedScope = SessionScope.bestEffort(sessionID: rootSessionID)
        self.missionID = try container.decode(String.self, forKey: .missionID)
        self.rootSessionID = rootSessionID
        self.requesterActorID = try container.decodeIfPresent(ActorID.self, forKey: .requesterActorID) ?? resolvedScope.actorID
        self.workspaceID = try container.decodeIfPresent(WorkspaceID.self, forKey: .workspaceID) ?? resolvedScope.workspaceID
        self.channelID = try container.decodeIfPresent(ChannelID.self, forKey: .channelID) ?? resolvedScope.channelID
        self.title = try container.decode(String.self, forKey: .title)
        self.brief = try container.decode(String.self, forKey: .brief)
        self.executionMode = try container.decode(ExecutionMode.self, forKey: .executionMode)
        self.status = try container.decode(Status.self, forKey: .status)
        self.primaryTaskID = try container.decodeIfPresent(String.self, forKey: .primaryTaskID)
        self.contractArtifactID = try container.decodeIfPresent(String.self, forKey: .contractArtifactID)
        self.progressArtifactID = try container.decodeIfPresent(String.self, forKey: .progressArtifactID)
        self.verificationArtifactID = try container.decodeIfPresent(String.self, forKey: .verificationArtifactID)
        self.budgetUnits = try container.decode(Int.self, forKey: .budgetUnits)
        self.maxRecursionDepth = try container.decode(Int.self, forKey: .maxRecursionDepth)
        self.metadata = try container.decode([String: String].self, forKey: .metadata)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(missionID, forKey: .missionID)
        try container.encode(rootSessionID, forKey: .rootSessionID)
        try container.encodeIfPresent(requesterActorID, forKey: .requesterActorID)
        try container.encodeIfPresent(workspaceID, forKey: .workspaceID)
        try container.encodeIfPresent(channelID, forKey: .channelID)
        try container.encode(title, forKey: .title)
        try container.encode(brief, forKey: .brief)
        try container.encode(executionMode, forKey: .executionMode)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(primaryTaskID, forKey: .primaryTaskID)
        try container.encodeIfPresent(contractArtifactID, forKey: .contractArtifactID)
        try container.encodeIfPresent(progressArtifactID, forKey: .progressArtifactID)
        try container.encodeIfPresent(verificationArtifactID, forKey: .verificationArtifactID)
        try container.encode(budgetUnits, forKey: .budgetUnits)
        try container.encode(maxRecursionDepth, forKey: .maxRecursionDepth)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}
