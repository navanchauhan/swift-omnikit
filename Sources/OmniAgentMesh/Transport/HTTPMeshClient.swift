import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HTTPMeshClientError: Error, CustomStringConvertible, Sendable {
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    public var description: String {
        switch self {
        case .invalidResponse:
            return "Received an invalid HTTP response from the mesh server."
        case .requestFailed(let statusCode, let message):
            return "Mesh server request failed with status \(statusCode): \(message)"
        }
    }
}

public actor HTTPMeshClient: JobStore, ArtifactStore, WorkerInteractionBridge {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseURL: URL, configuration: URLSessionConfiguration = .ephemeral) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: configuration)
    }

    public func ping() async throws {
        _ = try await request(
            path: "health",
            payload: HTTPMeshProtocol.EmptyRequest(),
            responseType: HTTPMeshProtocol.ValueResponse<String>.self
        )
    }

    public func createTask(_ task: TaskRecord, idempotencyKey: String?) async throws -> TaskRecord {
        let response = try await request(
            path: "tasks/create",
            payload: HTTPMeshProtocol.CreateTaskRequest(task: task, idempotencyKey: idempotencyKey),
            responseType: HTTPMeshProtocol.ValueResponse<TaskRecord>.self
        )
        return response.value
    }

    public func task(taskID: String) async throws -> TaskRecord? {
        let response = try await request(
            path: "tasks/get",
            payload: HTTPMeshProtocol.TaskLookupRequest(taskID: taskID),
            responseType: HTTPMeshProtocol.ValueResponse<TaskRecord?>.self
        )
        return response.value
    }

    public func tasks(statuses: [TaskRecord.Status]?) async throws -> [TaskRecord] {
        let response = try await request(
            path: "tasks/list",
            payload: HTTPMeshProtocol.TaskListRequest(statuses: statuses),
            responseType: HTTPMeshProtocol.ValueResponse<[TaskRecord]>.self
        )
        return response.value
    }

    public func claimNextTask(
        workerID: String,
        capabilities: [String],
        leaseDuration: TimeInterval,
        now: Date
    ) async throws -> TaskRecord? {
        let response = try await request(
            path: "tasks/claim-next",
            payload: HTTPMeshProtocol.ClaimNextTaskRequest(
                workerID: workerID,
                capabilities: capabilities,
                leaseDuration: leaseDuration,
                now: now
            ),
            responseType: HTTPMeshProtocol.ValueResponse<TaskRecord?>.self
        )
        return response.value
    }

    public func renewLease(
        taskID: String,
        workerID: String,
        leaseDuration: TimeInterval,
        now: Date
    ) async throws -> TaskRecord {
        let response = try await request(
            path: "tasks/renew-lease",
            payload: HTTPMeshProtocol.RenewLeaseRequest(
                taskID: taskID,
                workerID: workerID,
                leaseDuration: leaseDuration,
                now: now
            ),
            responseType: HTTPMeshProtocol.ValueResponse<TaskRecord>.self
        )
        return response.value
    }

    public func startTask(taskID: String, workerID: String, now: Date, idempotencyKey: String) async throws -> TaskEvent {
        let response = try await request(
            path: "tasks/start",
            payload: HTTPMeshProtocol.StartTaskRequest(
                taskID: taskID,
                workerID: workerID,
                now: now,
                idempotencyKey: idempotencyKey
            ),
            responseType: HTTPMeshProtocol.ValueResponse<TaskEvent>.self
        )
        return response.value
    }

    public func appendProgress(
        taskID: String,
        workerID: String?,
        summary: String,
        data: [String: String],
        idempotencyKey: String,
        now: Date
    ) async throws -> TaskEvent {
        let response = try await request(
            path: "tasks/progress",
            payload: HTTPMeshProtocol.AppendProgressRequest(
                taskID: taskID,
                workerID: workerID,
                summary: summary,
                data: data,
                idempotencyKey: idempotencyKey,
                now: now
            ),
            responseType: HTTPMeshProtocol.ValueResponse<TaskEvent>.self
        )
        return response.value
    }

    public func completeTask(
        taskID: String,
        workerID: String?,
        summary: String,
        artifactRefs: [String],
        idempotencyKey: String,
        now: Date
    ) async throws -> TaskEvent {
        let response = try await request(
            path: "tasks/complete",
            payload: HTTPMeshProtocol.CompleteTaskRequest(
                taskID: taskID,
                workerID: workerID,
                summary: summary,
                artifactRefs: artifactRefs,
                idempotencyKey: idempotencyKey,
                now: now
            ),
            responseType: HTTPMeshProtocol.ValueResponse<TaskEvent>.self
        )
        return response.value
    }

    public func failTask(
        taskID: String,
        workerID: String?,
        summary: String,
        idempotencyKey: String,
        now: Date
    ) async throws -> TaskEvent {
        let response = try await request(
            path: "tasks/fail",
            payload: HTTPMeshProtocol.FailTaskRequest(
                taskID: taskID,
                workerID: workerID,
                summary: summary,
                idempotencyKey: idempotencyKey,
                now: now
            ),
            responseType: HTTPMeshProtocol.ValueResponse<TaskEvent>.self
        )
        return response.value
    }

    public func cancelTask(
        taskID: String,
        workerID: String?,
        summary: String,
        idempotencyKey: String,
        now: Date
    ) async throws -> TaskEvent {
        let response = try await request(
            path: "tasks/cancel",
            payload: HTTPMeshProtocol.CancelTaskRequest(
                taskID: taskID,
                workerID: workerID,
                summary: summary,
                idempotencyKey: idempotencyKey,
                now: now
            ),
            responseType: HTTPMeshProtocol.ValueResponse<TaskEvent>.self
        )
        return response.value
    }

    public func events(taskID: String, afterSequence: Int?) async throws -> [TaskEvent] {
        let response = try await request(
            path: "tasks/events",
            payload: HTTPMeshProtocol.EventsRequest(taskID: taskID, afterSequence: afterSequence),
            responseType: HTTPMeshProtocol.ValueResponse<[TaskEvent]>.self
        )
        return response.value
    }

    public func upsertWorker(_ worker: WorkerRecord) async throws {
        _ = try await request(
            path: "workers/upsert",
            payload: HTTPMeshProtocol.ValueResponse(value: worker),
            responseType: HTTPMeshProtocol.ValueResponse<Bool>.self
        )
    }

    public func worker(workerID: String) async throws -> WorkerRecord? {
        let response = try await request(
            path: "workers/get",
            payload: HTTPMeshProtocol.WorkerLookupRequest(workerID: workerID),
            responseType: HTTPMeshProtocol.ValueResponse<WorkerRecord?>.self
        )
        return response.value
    }

    public func workers() async throws -> [WorkerRecord] {
        let response = try await request(
            path: "workers/list",
            payload: HTTPMeshProtocol.EmptyRequest(),
            responseType: HTTPMeshProtocol.ValueResponse<[WorkerRecord]>.self
        )
        return response.value
    }

    public func recordHeartbeat(workerID: String, state: WorkerRecord.State?, at: Date) async throws -> WorkerRecord? {
        let response = try await request(
            path: "workers/heartbeat",
            payload: HTTPMeshProtocol.HeartbeatRequest(workerID: workerID, state: state, at: at),
            responseType: HTTPMeshProtocol.ValueResponse<WorkerRecord?>.self
        )
        return response.value
    }

    public func recoverOrphanedTasks(now: Date) async throws -> [TaskRecord] {
        let response = try await request(
            path: "tasks/recover-orphaned",
            payload: HTTPMeshProtocol.RecoverOrphanedTasksRequest(now: now),
            responseType: HTTPMeshProtocol.ValueResponse<[TaskRecord]>.self
        )
        return response.value
    }

    public func put(_ payload: ArtifactPayload) async throws -> ArtifactRecord {
        let response = try await request(
            path: "artifacts/put",
            payload: HTTPMeshProtocol.ArtifactPutRequest(payload: .init(payload: payload)),
            responseType: HTTPMeshProtocol.ValueResponse<ArtifactRecord>.self
        )
        return response.value
    }

    public func record(artifactID: String) async throws -> ArtifactRecord? {
        let response = try await request(
            path: "artifacts/get",
            payload: HTTPMeshProtocol.ArtifactLookupRequest(artifactID: artifactID),
            responseType: HTTPMeshProtocol.ValueResponse<HTTPMeshProtocol.ArtifactBlobResponse>.self
        )
        return response.value.record
    }

    public func data(for artifactID: String) async throws -> Data? {
        let response = try await request(
            path: "artifacts/get",
            payload: HTTPMeshProtocol.ArtifactLookupRequest(artifactID: artifactID),
            responseType: HTTPMeshProtocol.ValueResponse<HTTPMeshProtocol.ArtifactBlobResponse>.self
        )
        return response.value.data
    }

    public func list(
        taskID: String?,
        missionID: String?,
        workspaceID: WorkspaceID?
    ) async throws -> [ArtifactRecord] {
        let response = try await request(
            path: "artifacts/list",
            payload: HTTPMeshProtocol.ArtifactListRequest(
                taskID: taskID,
                missionID: missionID,
                workspaceID: workspaceID
            ),
            responseType: HTTPMeshProtocol.ValueResponse<[ArtifactRecord]>.self
        )
        return response.value
    }

    public func requestApproval(_ prompt: WorkerApprovalPrompt) async throws -> WorkerInteractionResolution {
        let response = try await request(
            path: "interactions/request-approval",
            payload: HTTPMeshProtocol.InteractionApprovalRequest(prompt: prompt),
            responseType: HTTPMeshProtocol.ValueResponse<WorkerInteractionResolution>.self,
            timeoutInterval: max(30, (prompt.timeoutSeconds ?? 600) + 10)
        )
        return response.value
    }

    public func requestQuestion(_ prompt: WorkerQuestionPrompt) async throws -> WorkerInteractionResolution {
        let response = try await request(
            path: "interactions/request-question",
            payload: HTTPMeshProtocol.InteractionQuestionRequest(prompt: prompt),
            responseType: HTTPMeshProtocol.ValueResponse<WorkerInteractionResolution>.self,
            timeoutInterval: max(30, (prompt.timeoutSeconds ?? 600) + 10)
        )
        return response.value
    }

    private func request<Request: Encodable, Response: Decodable>(
        path: String,
        payload: Request,
        responseType: Response.Type,
        timeoutInterval: TimeInterval = 15
    ) async throws -> Response {
        let body = try encoder.encode(payload)
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPMeshClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorMessage: String
            if let decoded = try? decoder.decode(HTTPMeshProtocol.ErrorResponse.self, from: data) {
                errorMessage = decoded.error
            } else {
                errorMessage = String(decoding: data, as: UTF8.self)
            }
            throw HTTPMeshClientError.requestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return try decoder.decode(responseType, from: data)
    }
}
