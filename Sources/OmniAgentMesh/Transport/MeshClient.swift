import Foundation

public actor MeshClient: JobStore {
    private let server: MeshServer

    public init(server: MeshServer) {
        self.server = server
    }

    public func subscribe(taskID: String? = nil, afterSequence: Int? = nil) async throws -> AsyncStream<TaskEvent> {
        try await server.eventStream(taskID: taskID, afterSequence: afterSequence)
    }

    public func createTask(_ task: TaskRecord, idempotencyKey: String?) async throws -> TaskRecord {
        try await server.createTask(task, idempotencyKey: idempotencyKey)
    }

    public func task(taskID: String) async throws -> TaskRecord? {
        try await server.task(taskID: taskID)
    }

    public func tasks(statuses: [TaskRecord.Status]?) async throws -> [TaskRecord] {
        try await server.tasks(statuses: statuses)
    }

    public func claimNextTask(
        workerID: String,
        capabilities: [String],
        leaseDuration: TimeInterval,
        now: Date
    ) async throws -> TaskRecord? {
        try await server.claimNextTask(
            workerID: workerID,
            capabilities: capabilities,
            leaseDuration: leaseDuration,
            now: now
        )
    }

    public func renewLease(taskID: String, workerID: String, leaseDuration: TimeInterval, now: Date) async throws -> TaskRecord {
        try await server.renewLease(
            taskID: taskID,
            workerID: workerID,
            leaseDuration: leaseDuration,
            now: now
        )
    }

    public func startTask(taskID: String, workerID: String, now: Date, idempotencyKey: String) async throws -> TaskEvent {
        try await server.startTask(
            taskID: taskID,
            workerID: workerID,
            now: now,
            idempotencyKey: idempotencyKey
        )
    }

    public func appendProgress(
        taskID: String,
        workerID: String?,
        summary: String,
        data: [String: String],
        idempotencyKey: String,
        now: Date
    ) async throws -> TaskEvent {
        try await server.appendProgress(
            taskID: taskID,
            workerID: workerID,
            summary: summary,
            data: data,
            idempotencyKey: idempotencyKey,
            now: now
        )
    }

    public func completeTask(
        taskID: String,
        workerID: String?,
        summary: String,
        artifactRefs: [String],
        idempotencyKey: String,
        now: Date
    ) async throws -> TaskEvent {
        try await server.completeTask(
            taskID: taskID,
            workerID: workerID,
            summary: summary,
            artifactRefs: artifactRefs,
            idempotencyKey: idempotencyKey,
            now: now
        )
    }

    public func failTask(
        taskID: String,
        workerID: String?,
        summary: String,
        idempotencyKey: String,
        now: Date
    ) async throws -> TaskEvent {
        try await server.failTask(
            taskID: taskID,
            workerID: workerID,
            summary: summary,
            idempotencyKey: idempotencyKey,
            now: now
        )
    }

    public func cancelTask(
        taskID: String,
        workerID: String?,
        summary: String,
        idempotencyKey: String,
        now: Date
    ) async throws -> TaskEvent {
        try await server.cancelTask(
            taskID: taskID,
            workerID: workerID,
            summary: summary,
            idempotencyKey: idempotencyKey,
            now: now
        )
    }

    public func events(taskID: String, afterSequence: Int?) async throws -> [TaskEvent] {
        try await server.events(taskID: taskID, afterSequence: afterSequence)
    }

    public func upsertWorker(_ worker: WorkerRecord) async throws {
        try await server.upsertWorker(worker)
    }

    public func worker(workerID: String) async throws -> WorkerRecord? {
        try await server.worker(workerID: workerID)
    }

    public func workers() async throws -> [WorkerRecord] {
        try await server.workers()
    }

    public func recordHeartbeat(workerID: String, state: WorkerRecord.State?, at: Date) async throws -> WorkerRecord? {
        try await server.recordHeartbeat(workerID: workerID, state: state, at: at)
    }

    public func recoverOrphanedTasks(now: Date) async throws -> [TaskRecord] {
        try await server.recoverOrphanedTasks(now: now)
    }
}
