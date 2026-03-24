import Foundation

public struct TaskEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case submitted = "task.submitted"
        case assigned = "task.assigned"
        case started = "task.started"
        case progress = "task.progress"
        case waiting = "task.waiting"
        case toolCall = "task.tool_call"
        case artifact = "task.artifact"
        case completed = "task.completed"
        case failed = "task.failed"
        case cancelled = "task.cancelled"
        case resumed = "task.resumed"
    }

    public var taskID: String
    public var sequenceNumber: Int
    public var idempotencyKey: String
    public var kind: Kind
    public var workerID: String?
    public var summary: String?
    public var data: [String: String]
    public var createdAt: Date

    public init(
        taskID: String,
        sequenceNumber: Int,
        idempotencyKey: String,
        kind: Kind,
        workerID: String? = nil,
        summary: String? = nil,
        data: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.taskID = taskID
        self.sequenceNumber = sequenceNumber
        self.idempotencyKey = idempotencyKey
        self.kind = kind
        self.workerID = workerID
        self.summary = summary
        self.data = data
        self.createdAt = createdAt
    }
}
