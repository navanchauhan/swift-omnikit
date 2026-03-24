import Foundation

public struct QuestionRequestRecord: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case freeText = "free_text"
        case confirmation
        case singleSelect = "single_select"
    }

    public enum Status: String, Codable, Sendable, CaseIterable {
        case pending
        case answered
        case cancelled
        case deferred
        case timedOut = "timed_out"
    }

    public var requestID: String
    public var missionID: String?
    public var taskID: String?
    public var rootSessionID: String
    public var requesterActorID: ActorID?
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var title: String
    public var prompt: String
    public var kind: Kind
    public var options: [String]
    public var status: Status
    public var answerActorID: ActorID?
    public var answerText: String?
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date
    public var answeredAt: Date?

    public init(
        requestID: String = UUID().uuidString,
        missionID: String? = nil,
        taskID: String? = nil,
        rootSessionID: String,
        requesterActorID: ActorID? = nil,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        title: String,
        prompt: String,
        kind: Kind = .freeText,
        options: [String] = [],
        status: Status = .pending,
        answerActorID: ActorID? = nil,
        answerText: String? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        answeredAt: Date? = nil
    ) {
        let resolvedScope = SessionScope.bestEffort(sessionID: rootSessionID)
        self.requestID = requestID
        self.missionID = missionID
        self.taskID = taskID
        self.rootSessionID = rootSessionID
        self.requesterActorID = requesterActorID ?? resolvedScope.actorID
        self.workspaceID = workspaceID ?? resolvedScope.workspaceID
        self.channelID = channelID ?? resolvedScope.channelID
        self.title = title
        self.prompt = prompt
        self.kind = kind
        self.options = options
        self.status = status
        self.answerActorID = answerActorID
        self.answerText = answerText
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.answeredAt = answeredAt
    }
}
