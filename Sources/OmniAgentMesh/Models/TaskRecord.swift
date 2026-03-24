import Foundation

public struct TaskRecord: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case taskID
        case rootSessionID
        case requesterActorID
        case workspaceID
        case channelID
        case missionID
        case parentTaskID
        case assignedAgentID
        case capabilityRequirements
        case historyProjection
        case artifactRefs
        case attemptCount
        case maxAttempts
        case deadlineAt
        case restartPolicy
        case escalationPolicy
        case priority
        case lease
        case status
        case createdAt
        case updatedAt
    }

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

    public enum RestartPolicy: String, Codable, Sendable {
        case none
        case retryStage = "retry_stage"
        case retryMission = "retry_mission"
        case escalate
    }

    public enum EscalationPolicy: String, Codable, Sendable {
        case none
        case notifyRoot = "notify_root"
        case deadLetter = "dead_letter"
    }

    public var taskID: String
    public var rootSessionID: String
    public var requesterActorID: ActorID?
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var missionID: String?
    public var parentTaskID: String?
    public var assignedAgentID: String?
    public var capabilityRequirements: [String]
    public var historyProjection: HistoryProjection
    public var artifactRefs: [String]
    public var attemptCount: Int
    public var maxAttempts: Int
    public var deadlineAt: Date?
    public var restartPolicy: RestartPolicy
    public var escalationPolicy: EscalationPolicy
    public var priority: Int
    public var lease: Lease?
    public var status: Status
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        taskID: String = UUID().uuidString,
        rootSessionID: String,
        requesterActorID: ActorID? = nil,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        missionID: String? = nil,
        parentTaskID: String? = nil,
        assignedAgentID: String? = nil,
        capabilityRequirements: [String] = [],
        historyProjection: HistoryProjection,
        artifactRefs: [String] = [],
        attemptCount: Int = 0,
        maxAttempts: Int = 1,
        deadlineAt: Date? = nil,
        restartPolicy: RestartPolicy = .escalate,
        escalationPolicy: EscalationPolicy = .notifyRoot,
        priority: Int = 0,
        lease: Lease? = nil,
        status: Status = .submitted,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let resolvedScope = SessionScope.bestEffort(sessionID: rootSessionID)
        self.taskID = taskID
        self.rootSessionID = rootSessionID
        self.requesterActorID = requesterActorID ?? resolvedScope.actorID
        self.workspaceID = workspaceID ?? resolvedScope.workspaceID
        self.channelID = channelID ?? resolvedScope.channelID
        self.missionID = missionID
        self.parentTaskID = parentTaskID
        self.assignedAgentID = assignedAgentID
        self.capabilityRequirements = Array(Set(capabilityRequirements)).sorted()
        self.historyProjection = historyProjection
        self.artifactRefs = artifactRefs
        self.attemptCount = max(0, attemptCount)
        self.maxAttempts = max(1, maxAttempts)
        self.deadlineAt = deadlineAt
        self.restartPolicy = restartPolicy
        self.escalationPolicy = escalationPolicy
        self.priority = priority
        self.lease = lease
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rootSessionID = try container.decode(String.self, forKey: .rootSessionID)
        let resolvedScope = SessionScope.bestEffort(sessionID: rootSessionID)
        self.taskID = try container.decode(String.self, forKey: .taskID)
        self.rootSessionID = rootSessionID
        self.requesterActorID = try container.decodeIfPresent(ActorID.self, forKey: .requesterActorID) ?? resolvedScope.actorID
        self.workspaceID = try container.decodeIfPresent(WorkspaceID.self, forKey: .workspaceID) ?? resolvedScope.workspaceID
        self.channelID = try container.decodeIfPresent(ChannelID.self, forKey: .channelID) ?? resolvedScope.channelID
        self.missionID = try container.decodeIfPresent(String.self, forKey: .missionID)
        self.parentTaskID = try container.decodeIfPresent(String.self, forKey: .parentTaskID)
        self.assignedAgentID = try container.decodeIfPresent(String.self, forKey: .assignedAgentID)
        self.capabilityRequirements = try container.decode([String].self, forKey: .capabilityRequirements)
        self.historyProjection = try container.decode(HistoryProjection.self, forKey: .historyProjection)
        self.artifactRefs = try container.decode([String].self, forKey: .artifactRefs)
        self.attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        self.maxAttempts = try container.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 1
        self.deadlineAt = try container.decodeIfPresent(Date.self, forKey: .deadlineAt)
        self.restartPolicy = try container.decodeIfPresent(RestartPolicy.self, forKey: .restartPolicy) ?? .escalate
        self.escalationPolicy = try container.decodeIfPresent(EscalationPolicy.self, forKey: .escalationPolicy) ?? .notifyRoot
        self.priority = try container.decode(Int.self, forKey: .priority)
        self.lease = try container.decodeIfPresent(Lease.self, forKey: .lease)
        self.status = try container.decode(Status.self, forKey: .status)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskID, forKey: .taskID)
        try container.encode(rootSessionID, forKey: .rootSessionID)
        try container.encodeIfPresent(requesterActorID, forKey: .requesterActorID)
        try container.encodeIfPresent(workspaceID, forKey: .workspaceID)
        try container.encodeIfPresent(channelID, forKey: .channelID)
        try container.encodeIfPresent(missionID, forKey: .missionID)
        try container.encodeIfPresent(parentTaskID, forKey: .parentTaskID)
        try container.encodeIfPresent(assignedAgentID, forKey: .assignedAgentID)
        try container.encode(capabilityRequirements, forKey: .capabilityRequirements)
        try container.encode(historyProjection, forKey: .historyProjection)
        try container.encode(artifactRefs, forKey: .artifactRefs)
        try container.encode(attemptCount, forKey: .attemptCount)
        try container.encode(maxAttempts, forKey: .maxAttempts)
        try container.encodeIfPresent(deadlineAt, forKey: .deadlineAt)
        try container.encode(restartPolicy, forKey: .restartPolicy)
        try container.encode(escalationPolicy, forKey: .escalationPolicy)
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(lease, forKey: .lease)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
