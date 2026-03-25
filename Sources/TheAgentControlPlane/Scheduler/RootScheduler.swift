import Foundation
import OmniAgentMesh

public actor RootScheduler {
    private let jobStore: any JobStore
    private let registry: WorkerRegistry
    private let matcher: CapabilityMatcher

    public init(
        jobStore: any JobStore,
        registry: WorkerRegistry? = nil,
        matcher: CapabilityMatcher = CapabilityMatcher()
    ) {
        self.jobStore = jobStore
        self.registry = registry ?? WorkerRegistry(jobStore: jobStore)
        self.matcher = matcher
    }

    public func registerLocalWorker(_ worker: any WorkerDispatching, at: Date = Date()) async throws {
        try await registry.register(worker, placement: .sameHost, at: at)
    }

    public func registerRemoteWorker(_ worker: any WorkerDispatching, at: Date = Date()) async throws {
        try await registry.register(worker, placement: .remote, at: at)
    }

    public func submitTask(
        rootSessionID: String,
        requesterActorID: ActorID? = nil,
        workspaceID: WorkspaceID? = nil,
        channelID: ChannelID? = nil,
        missionID: String? = nil,
        parentTaskID: String? = nil,
        historyProjection: HistoryProjection,
        capabilityRequirements: [String] = [],
        metadata: [String: String] = [:],
        attemptCount: Int = 0,
        maxAttempts: Int = 1,
        deadlineAt: Date? = nil,
        restartPolicy: TaskRecord.RestartPolicy = .escalate,
        escalationPolicy: TaskRecord.EscalationPolicy = .notifyRoot,
        priority: Int = 0,
        createdAt: Date = Date()
    ) async throws -> TaskRecord {
        let task = TaskRecord(
            rootSessionID: rootSessionID,
            requesterActorID: requesterActorID,
            workspaceID: workspaceID,
            channelID: channelID,
            missionID: missionID,
            parentTaskID: parentTaskID,
            capabilityRequirements: capabilityRequirements,
            historyProjection: historyProjection,
            metadata: metadata,
            attemptCount: attemptCount,
            maxAttempts: maxAttempts,
            deadlineAt: deadlineAt,
            restartPolicy: restartPolicy,
            escalationPolicy: escalationPolicy,
            priority: priority,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        return try await jobStore.createTask(task, idempotencyKey: "task.submitted.\(task.taskID)")
    }

    public func dispatchNextAvailableTask(now: Date = Date()) async throws -> TaskRecord? {
        for task in try await jobStore.tasks(statuses: [.submitted, .waiting]) {
            for worker in try await registry.matchingDispatchers(for: task, matcher: matcher, now: now) {
                if let claimed = try await worker.drainOnce(now: now) {
                    return claimed
                }
            }
        }
        return nil
    }

    public func dispatchNextAvailableTaskInBackground(now: Date = Date()) async throws -> TaskRecord? {
        for task in try await jobStore.tasks(statuses: [.submitted, .waiting]) {
            for worker in try await registry.matchingDispatchers(for: task, matcher: matcher, now: now) {
                if let claimed = try await worker.runNextTaskInBackground(now: now) {
                    return claimed
                }
            }
        }
        return nil
    }

    public func dispatchAllAvailableTasks(now: Date = Date()) async throws -> [TaskRecord] {
        var completedTasks: [TaskRecord] = []
        while let task = try await dispatchNextAvailableTask(now: now) {
            completedTasks.append(task)
        }
        return completedTasks
    }

    public func dispatchAllAvailableTasksInBackground(now: Date = Date()) async throws -> [TaskRecord] {
        var claimedTasks: [TaskRecord] = []
        while let task = try await dispatchNextAvailableTaskInBackground(now: now) {
            claimedTasks.append(task)
        }
        return claimedTasks
    }
}
