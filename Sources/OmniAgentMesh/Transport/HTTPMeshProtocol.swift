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

    struct ArtifactPutRequest: Codable, Sendable {
        let payload: ArtifactPayloadCodable
    }

    struct ArtifactLookupRequest: Codable, Sendable {
        let artifactID: String
    }

    struct ArtifactListRequest: Codable, Sendable {
        let taskID: String?
        let missionID: String?
        let workspaceID: WorkspaceID?
    }

    struct ArtifactBlobResponse: Codable, Sendable {
        let record: ArtifactRecord?
        let data: Data?
    }

    struct InteractionApprovalRequest: Codable, Sendable {
        let prompt: WorkerApprovalPrompt
    }

    struct InteractionQuestionRequest: Codable, Sendable {
        let prompt: WorkerQuestionPrompt
    }

    struct ArtifactPayloadCodable: Codable, Sendable {
        let taskID: String?
        let missionID: String?
        let workspaceID: WorkspaceID?
        let channelID: ChannelID?
        let name: String
        let contentType: String
        let data: Data

        init(payload: ArtifactPayload) {
            self.taskID = payload.taskID
            self.missionID = payload.missionID
            self.workspaceID = payload.workspaceID
            self.channelID = payload.channelID
            self.name = payload.name
            self.contentType = payload.contentType
            self.data = payload.data
        }

        func decoded() -> ArtifactPayload {
            ArtifactPayload(
                taskID: taskID,
                missionID: missionID,
                workspaceID: workspaceID,
                channelID: channelID,
                name: name,
                contentType: contentType,
                data: data
            )
        }
    }
}
