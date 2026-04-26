import Foundation

public enum ScheduledPromptRecurrence: String, Codable, Sendable, CaseIterable {
    case none
    case daily
    case weekdays
    case weekly
    case monthly
}

public enum ScheduledPromptStatus: String, Codable, Sendable, CaseIterable {
    case active
    case completed
    case cancelled
}

public struct ScheduledPromptRecord: Codable, Sendable, Equatable {
    public var scheduleID: String
    public var createdBySessionID: String
    public var transport: ChannelBinding.Transport
    public var actorExternalID: String
    public var actorDisplayName: String?
    public var channelExternalID: String
    public var channelKind: String
    public var title: String
    public var prompt: String
    public var eventKind: String
    public var recurrence: ScheduledPromptRecurrence
    public var timezoneIdentifier: String
    public var status: ScheduledPromptStatus
    public var nextFireAt: Date?
    public var lastFiredAt: Date?
    public var fireCount: Int
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        scheduleID: String = UUID().uuidString,
        createdBySessionID: String,
        transport: ChannelBinding.Transport,
        actorExternalID: String,
        actorDisplayName: String? = nil,
        channelExternalID: String,
        channelKind: String,
        title: String,
        prompt: String,
        eventKind: String,
        recurrence: ScheduledPromptRecurrence = .none,
        timezoneIdentifier: String = TimeZone.current.identifier,
        status: ScheduledPromptStatus = .active,
        nextFireAt: Date?,
        lastFiredAt: Date? = nil,
        fireCount: Int = 0,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.scheduleID = scheduleID
        self.createdBySessionID = createdBySessionID
        self.transport = transport
        self.actorExternalID = actorExternalID
        self.actorDisplayName = actorDisplayName
        self.channelExternalID = channelExternalID
        self.channelKind = channelKind
        self.title = title
        self.prompt = prompt
        self.eventKind = eventKind
        self.recurrence = recurrence
        self.timezoneIdentifier = timezoneIdentifier
        self.status = status
        self.nextFireAt = nextFireAt
        self.lastFiredAt = lastFiredAt
        self.fireCount = fireCount
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
