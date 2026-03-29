import Foundation

public actor MeshServer {
    private let jobStore: any JobStore
    private let eventHub = MeshEventHub()

    public init(jobStore: any JobStore) {
        self.jobStore = jobStore
    }

    public func createTask(_ task: TaskRecord, idempotencyKey: String? = nil) async throws -> TaskRecord {
        let created = try await jobStore.createTask(task, idempotencyKey: idempotencyKey)
        try await publishRecentEvents(taskID: created.taskID, limit: 1)
        return created
    }

    public func task(taskID: String) async throws -> TaskRecord? {
        try await jobStore.task(taskID: taskID)
    }

    public func tasks(statuses: [TaskRecord.Status]? = nil) async throws -> [TaskRecord] {
        try await jobStore.tasks(statuses: statuses)
    }

    public func claimNextTask(
        workerID: String,
        capabilities: [String],
        leaseDuration: TimeInterval,
        now: Date = Date()
    ) async throws -> TaskRecord? {
        guard let task = try await jobStore.claimNextTask(
            workerID: workerID,
            capabilities: capabilities,
            leaseDuration: leaseDuration,
            now: now
        ) else {
            return nil
        }
        try await publishRecentEvents(taskID: task.taskID, limit: 1)
        return task
    }

    public func renewLease(
        taskID: String,
        workerID: String,
        leaseDuration: TimeInterval,
        now: Date = Date()
    ) async throws -> TaskRecord {
        try await jobStore.renewLease(
            taskID: taskID,
            workerID: workerID,
            leaseDuration: leaseDuration,
            now: now
        )
    }

    public func startTask(
        taskID: String,
        workerID: String,
        now: Date = Date(),
        idempotencyKey: String
    ) async throws -> TaskEvent {
        let event = try await jobStore.startTask(
            taskID: taskID,
            workerID: workerID,
            now: now,
            idempotencyKey: idempotencyKey
        )
        await eventHub.publish(event)
        return event
    }

    public func appendProgress(
        taskID: String,
        workerID: String?,
        summary: String,
        data: [String: String],
        idempotencyKey: String,
        now: Date = Date()
    ) async throws -> TaskEvent {
        let event = try await jobStore.appendProgress(
            taskID: taskID,
            workerID: workerID,
            summary: summary,
            data: data,
            idempotencyKey: idempotencyKey,
            now: now
        )
        await eventHub.publish(event)
        return event
    }

    public func completeTask(
        taskID: String,
        workerID: String?,
        summary: String,
        artifactRefs: [String],
        idempotencyKey: String,
        now: Date = Date()
    ) async throws -> TaskEvent {
        let event = try await jobStore.completeTask(
            taskID: taskID,
            workerID: workerID,
            summary: summary,
            artifactRefs: artifactRefs,
            idempotencyKey: idempotencyKey,
            now: now
        )
        await eventHub.publish(event)
        return event
    }

    public func failTask(
        taskID: String,
        workerID: String?,
        summary: String,
        idempotencyKey: String,
        now: Date = Date()
    ) async throws -> TaskEvent {
        let event = try await jobStore.failTask(
            taskID: taskID,
            workerID: workerID,
            summary: summary,
            idempotencyKey: idempotencyKey,
            now: now
        )
        await eventHub.publish(event)
        return event
    }

    public func cancelTask(
        taskID: String,
        workerID: String?,
        summary: String,
        idempotencyKey: String,
        now: Date = Date()
    ) async throws -> TaskEvent {
        let event = try await jobStore.cancelTask(
            taskID: taskID,
            workerID: workerID,
            summary: summary,
            idempotencyKey: idempotencyKey,
            now: now
        )
        await eventHub.publish(event)
        return event
    }

    public func events(taskID: String, afterSequence: Int? = nil) async throws -> [TaskEvent] {
        try await jobStore.events(taskID: taskID, afterSequence: afterSequence)
    }

    public func upsertWorker(_ worker: WorkerRecord) async throws {
        try await jobStore.upsertWorker(worker)
    }

    public func worker(workerID: String) async throws -> WorkerRecord? {
        try await jobStore.worker(workerID: workerID)
    }

    public func workers() async throws -> [WorkerRecord] {
        try await jobStore.workers()
    }

    public func recordHeartbeat(workerID: String, state: WorkerRecord.State?, at: Date) async throws -> WorkerRecord? {
        try await jobStore.recordHeartbeat(workerID: workerID, state: state, at: at)
    }

    public func recoverOrphanedTasks(now: Date = Date()) async throws -> [TaskRecord] {
        let recovered = try await jobStore.recoverOrphanedTasks(now: now)
        for task in recovered {
            try await publishRecentEvents(taskID: task.taskID, limit: 2)
        }
        return recovered
    }

    public func eventStream(taskID: String? = nil, afterSequence: Int? = nil) async throws -> AsyncStream<TaskEvent> {
        let replay: [TaskEvent]
        if let taskID {
            replay = try await jobStore.events(taskID: taskID, afterSequence: afterSequence)
        } else {
            replay = []
        }
        return await eventHub.stream(taskID: taskID, afterSequence: afterSequence, replay: replay)
    }

    private func publishRecentEvents(taskID: String, limit: Int) async throws {
        let recent = try await jobStore.events(taskID: taskID, afterSequence: nil).suffix(limit)
        for event in recent {
            await eventHub.publish(event)
        }
    }
}

private actor MeshEventHub {
    private struct Subscriber {
        var taskID: String?
        var afterSequence: Int?
        var continuation: AsyncStream<TaskEvent>.Continuation
    }

    private var subscribers: [UUID: Subscriber] = [:]

    func publish(_ event: TaskEvent) {
        for subscriber in subscribers.values {
            guard matches(event: event, taskID: subscriber.taskID, afterSequence: subscriber.afterSequence) else {
                continue
            }
            subscriber.continuation.yield(event)
        }
    }

    func stream(
        taskID: String?,
        afterSequence: Int?,
        replay: [TaskEvent]
    ) -> AsyncStream<TaskEvent> {
        AsyncStream { continuation in
            let identifier = UUID()
            subscribers[identifier] = Subscriber(
                taskID: taskID,
                afterSequence: afterSequence,
                continuation: continuation
            )
            for event in replay where matches(event: event, taskID: taskID, afterSequence: afterSequence) {
                continuation.yield(event)
            }
            continuation.onTermination = { [weak self] _ in
                // Safety: `onTermination` is synchronous; this cleanup hop only removes the
                // stored subscriber entry from actor-owned state.
                Task {
                    await self?.removeSubscriber(identifier)
                }
            }
        }
    }

    private func removeSubscriber(_ identifier: UUID) {
        subscribers.removeValue(forKey: identifier)
    }

    private func matches(event: TaskEvent, taskID: String?, afterSequence: Int?) -> Bool {
        let matchesTask = taskID.map { event.taskID == $0 } ?? true
        let matchesSequence = afterSequence.map { event.sequenceNumber > $0 } ?? true
        return matchesTask && matchesSequence
    }
}
