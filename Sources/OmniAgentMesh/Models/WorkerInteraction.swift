import Foundation

public enum WorkerInteractionResolutionStatus: String, Codable, Sendable, Equatable {
    case approved
    case rejected
    case answered
    case cancelled
    case deferred
    case timedOut = "timed_out"
}

public struct WorkerApprovalPrompt: Codable, Sendable, Equatable {
    public var rootSessionID: String
    public var requesterActorID: ActorID?
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var missionID: String?
    public var taskID: String?
    public var title: String
    public var prompt: String
    public var sensitive: Bool
    public var metadata: [String: String]
    public var timeoutSeconds: Double?

    public init(
        rootSessionID: String,
        requesterActorID: ActorID? = nil,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        missionID: String? = nil,
        taskID: String? = nil,
        title: String,
        prompt: String,
        sensitive: Bool = true,
        metadata: [String: String] = [:],
        timeoutSeconds: Double? = nil
    ) {
        self.rootSessionID = rootSessionID
        self.requesterActorID = requesterActorID
        self.workspaceID = workspaceID
        self.channelID = channelID
        self.missionID = missionID
        self.taskID = taskID
        self.title = title
        self.prompt = prompt
        self.sensitive = sensitive
        self.metadata = metadata
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct WorkerQuestionPrompt: Codable, Sendable, Equatable {
    public var rootSessionID: String
    public var requesterActorID: ActorID?
    public var workspaceID: WorkspaceID?
    public var channelID: ChannelID?
    public var missionID: String?
    public var taskID: String?
    public var title: String
    public var prompt: String
    public var kind: QuestionRequestRecord.Kind
    public var options: [String]
    public var metadata: [String: String]
    public var timeoutSeconds: Double?

    public init(
        rootSessionID: String,
        requesterActorID: ActorID? = nil,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        missionID: String? = nil,
        taskID: String? = nil,
        title: String,
        prompt: String,
        kind: QuestionRequestRecord.Kind = .freeText,
        options: [String] = [],
        metadata: [String: String] = [:],
        timeoutSeconds: Double? = nil
    ) {
        self.rootSessionID = rootSessionID
        self.requesterActorID = requesterActorID
        self.workspaceID = workspaceID
        self.channelID = channelID
        self.missionID = missionID
        self.taskID = taskID
        self.title = title
        self.prompt = prompt
        self.kind = kind
        self.options = options
        self.metadata = metadata
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct WorkerInteractionResolution: Codable, Sendable, Equatable {
    public var requestID: String
    public var status: WorkerInteractionResolutionStatus
    public var responseText: String?
    public var responderActorID: ActorID?

    public init(
        requestID: String,
        status: WorkerInteractionResolutionStatus,
        responseText: String? = nil,
        responderActorID: ActorID? = nil
    ) {
        self.requestID = requestID
        self.status = status
        self.responseText = responseText
        self.responderActorID = responderActorID
    }
}

public protocol WorkerInteractionBridge: Sendable {
    func requestApproval(_ prompt: WorkerApprovalPrompt) async throws -> WorkerInteractionResolution
    func requestQuestion(_ prompt: WorkerQuestionPrompt) async throws -> WorkerInteractionResolution
}
