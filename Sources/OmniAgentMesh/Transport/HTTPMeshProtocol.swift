import Foundation

enum HTTPMeshProtocol {
    struct EmptyRequest: Codable, Sendable {}

    struct ValueResponse<Value: Codable & Sendable>: Codable, Sendable {
        let value: Value
    }

    struct ErrorResponse: Codable, Sendable {
        let error: String
    }

    struct CreateTaskRequest: Codable, Sendable {
        let task: TaskRecord
        let idempotencyKey: String?
    }

    struct TaskLookupRequest: Codable, Sendable {
        let taskID: String
    }

    struct TaskListRequest: Codable, Sendable {
        let statuses: [TaskRecord.Status]?
    }

    struct ClaimNextTaskRequest: Codable, Sendable {
        let workerID: String
        let capabilities: [String]
        let leaseDuration: TimeInterval
        let now: Date
    }

    struct RenewLeaseRequest: Codable, Sendable {
        let taskID: String
        let workerID: String
        let leaseDuration: TimeInterval
        let now: Date
    }

    struct StartTaskRequest: Codable, Sendable {
        let taskID: String
        let workerID: String
        let now: Date
        let idempotencyKey: String
    }

    struct AppendProgressRequest: Codable, Sendable {
        let taskID: String
        let workerID: String?
        let summary: String
        let data: [String: String]
        let idempotencyKey: String
        let now: Date
    }

    struct CompleteTaskRequest: Codable, Sendable {
        let taskID: String
        let workerID: String?
        let summary: String
        let artifactRefs: [String]
        let idempotencyKey: String
        let now: Date
    }

    struct FailTaskRequest: Codable, Sendable {
        let taskID: String
        let workerID: String?
        let summary: String
        let idempotencyKey: String
        let now: Date
    }

    struct CancelTaskRequest: Codable, Sendable {
        let taskID: String
        let workerID: String?
        let summary: String
        let idempotencyKey: String
        let now: Date
    }

    struct EventsRequest: Codable, Sendable {
        let taskID: String
        let afterSequence: Int?
    }

    struct WorkerLookupRequest: Codable, Sendable {
        let workerID: String
    }

    struct HeartbeatRequest: Codable, Sendable {
        let workerID: String
        let state: WorkerRecord.State?
        let at: Date
    }

    struct RecoverOrphanedTasksRequest: Codable, Sendable {
        let now: Date
    }
}
