import Foundation
import OmniAgentMesh

public actor WorkerDaemon: WorkerDispatching {
    public nonisolated let workerID: String
    public nonisolated let displayName: String
    public nonisolated let advertisedCapabilities: [String]

    private let jobStore: any JobStore
    private let artifactStore: any ArtifactStore
    private let executor: LocalTaskExecutor
    private let leaseDuration: TimeInterval
    private let eventStream: WorkerEventStream
    private var runningTasks: [String: Task<Void, Never>] = [:]

    public init(
        workerID: String = UUID().uuidString,
        displayName: String,
        capabilities: WorkerCapabilities,
        jobStore: any JobStore,
        artifactStore: any ArtifactStore,
        executor: LocalTaskExecutor = LocalTaskExecutor(),
        leaseDuration: TimeInterval = 30,
        eventStream: WorkerEventStream = WorkerEventStream()
    ) {
        self.workerID = workerID
        self.displayName = displayName
        self.advertisedCapabilities = capabilities.labels
        self.jobStore = jobStore
        self.artifactStore = artifactStore
        self.executor = executor
        self.leaseDuration = leaseDuration
        self.eventStream = eventStream
    }

    public func register(at: Date = Date(), metadata: [String: String] = [:]) async throws -> WorkerRecord {
        let record = WorkerRecord(
            workerID: workerID,
            displayName: displayName,
            capabilities: advertisedCapabilities,
            state: .idle,
            lastHeartbeatAt: at,
            metadata: metadata
        )
        try await jobStore.upsertWorker(record)
        return record
    }

    public func heartbeat(at: Date = Date(), state: WorkerRecord.State? = nil) async throws -> WorkerRecord? {
        try await jobStore.recordHeartbeat(workerID: workerID, state: state, at: at)
    }

    public func recoverOrphanedTasks(now: Date = Date()) async throws -> [TaskRecord] {
        try await jobStore.recoverOrphanedTasks(now: now)
    }

    public func drainOnce(now: Date = Date()) async throws -> TaskRecord? {
        guard let claimed = try await claimNextTask(now: now) else {
            _ = try await heartbeat(at: now, state: .idle)
            return nil
        }

        await executeClaimedTask(claimed, claimedAt: now)
        return try await jobStore.task(taskID: claimed.taskID)
    }

    public func runNextTaskInBackground(now: Date = Date()) async throws -> TaskRecord? {
        guard let claimed = try await claimNextTask(now: now) else {
            _ = try await heartbeat(at: now, state: .idle)
            return nil
        }

        let taskID = claimed.taskID
        let operation = Task { [task = claimed, claimedAt = now] in
            await self.executeClaimedTask(task, claimedAt: claimedAt)
        }
        runningTasks[taskID] = operation
        return claimed
    }

    public func cancel(taskID: String) {
        runningTasks[taskID]?.cancel()
    }

    public func waitForTask(taskID: String) async {
        if let task = runningTasks[taskID] {
            await task.value
        }
    }

    public func runLoop(
        pollInterval: Duration = .seconds(1),
        maxIdlePolls: Int? = nil
    ) async throws {
        var idlePolls = 0

        while !Task.isCancelled {
            let claimed = try await drainOnce(now: Date())
            if claimed == nil {
                idlePolls += 1
                if let maxIdlePolls, idlePolls >= maxIdlePolls {
                    return
                }
                try await Task.sleep(for: pollInterval)
            } else {
                idlePolls = 0
            }
        }
    }

    public func events(taskID: String? = nil, afterSequence: Int? = nil) async -> AsyncStream<TaskEvent> {
        await eventStream.stream(taskID: taskID, afterSequence: afterSequence)
    }

    private func claimNextTask(now: Date) async throws -> TaskRecord? {
        _ = try await heartbeat(at: now, state: .idle)
        return try await jobStore.claimNextTask(
            workerID: workerID,
            capabilities: advertisedCapabilities,
            leaseDuration: leaseDuration,
            now: now
        )
    }

    private func executeClaimedTask(_ task: TaskRecord, claimedAt: Date) async {
        do {
            _ = try await heartbeat(at: claimedAt, state: .busy)
            let started = try await jobStore.startTask(
                taskID: task.taskID,
                workerID: workerID,
                now: claimedAt,
                idempotencyKey: "task.started.\(task.taskID).\(Int(claimedAt.timeIntervalSince1970 * 1_000))"
            )
            await eventStream.publish(started)
            let workerStartedHeartbeat = try await jobStore.appendProgress(
                taskID: task.taskID,
                workerID: workerID,
                summary: "Worker heartbeat: task started",
                data: [
                    "heartbeat_source": "worker",
                    "heartbeat_phase": "started",
                    "task_id": task.taskID,
                ],
                idempotencyKey: "task.heartbeat.started.\(task.taskID)",
                now: claimedAt
            )
            await eventStream.publish(workerStartedHeartbeat)

            let result = try await executor.execute(task: task) { summary, data in
                try Task.checkCancellation()
                let timestamp = Date()
                var heartbeatData = data
                heartbeatData["heartbeat_source"] = heartbeatData["heartbeat_source"] ?? "worker"
                heartbeatData["heartbeat_phase"] = heartbeatData["heartbeat_phase"] ?? "progress"
                let progress = try await self.jobStore.appendProgress(
                    taskID: task.taskID,
                    workerID: self.workerID,
                    summary: summary,
                    data: heartbeatData,
                    idempotencyKey: "task.progress.\(task.taskID).\(UUID().uuidString)",
                    now: timestamp
                )
                _ = try await self.jobStore.renewLease(
                    taskID: task.taskID,
                    workerID: self.workerID,
                    leaseDuration: self.leaseDuration,
                    now: timestamp
                )
                await self.eventStream.publish(progress)
            }

            try Task.checkCancellation()

            var artifactIDs: [String] = []
            for artifact in result.artifacts {
                let record = try await artifactStore.put(
                    ArtifactPayload(
                        taskID: task.taskID,
                        missionID: task.missionID,
                        workspaceID: task.workspaceID,
                        channelID: task.channelID,
                        name: artifact.name,
                        contentType: artifact.contentType,
                        data: artifact.data
                    )
                )
                artifactIDs.append(record.artifactID)
            }

            let completed = try await jobStore.completeTask(
                taskID: task.taskID,
                workerID: workerID,
                summary: result.summary,
                artifactRefs: artifactIDs,
                idempotencyKey: "task.completed.\(task.taskID)",
                now: Date()
            )
            await eventStream.publish(completed)
        } catch is CancellationError {
            if let cancelled = try? await jobStore.cancelTask(
                taskID: task.taskID,
                workerID: workerID,
                summary: "Task cancelled",
                idempotencyKey: "task.cancelled.\(task.taskID)",
                now: Date()
            ) {
                await eventStream.publish(cancelled)
            }
        } catch {
            let timestamp = Date()
            if let failureHeartbeat = try? await jobStore.appendProgress(
                taskID: task.taskID,
                workerID: workerID,
                summary: "Worker heartbeat: task failed",
                data: [
                    "heartbeat_source": "worker",
                    "heartbeat_phase": "failed",
                    "error": String(describing: error),
                ],
                idempotencyKey: "task.heartbeat.failed.\(task.taskID)",
                now: timestamp
            ) {
                await eventStream.publish(failureHeartbeat)
            }
            if let failed = try? await jobStore.failTask(
                taskID: task.taskID,
                workerID: workerID,
                summary: String(describing: error),
                idempotencyKey: "task.failed.\(task.taskID)",
                now: Date()
            ) {
                await eventStream.publish(failed)
            }
        }

        runningTasks[task.taskID] = nil
        _ = try? await heartbeat(at: Date(), state: .idle)
    }
}
