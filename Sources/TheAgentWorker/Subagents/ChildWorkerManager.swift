import Foundation
import OmniAgentMesh

public struct ChildTaskRequest: Sendable, Equatable {
    public var brief: String
    public var capabilityRequirements: [String]
    public var constraints: [String]
    public var expectedOutputs: [String]
    public var artifactRefs: [String]
    public var priority: Int

    public init(
        brief: String,
        capabilityRequirements: [String] = [],
        constraints: [String] = [],
        expectedOutputs: [String] = [],
        artifactRefs: [String] = [],
        priority: Int = 0
    ) {
        self.brief = brief
        self.capabilityRequirements = capabilityRequirements
        self.constraints = constraints
        self.expectedOutputs = expectedOutputs
        self.artifactRefs = artifactRefs
        self.priority = priority
    }
}

public actor ChildWorkerManager {
    private let jobStore: any JobStore
    private let projectionBuilder: HistoryProjectionBuilder

    public init(
        jobStore: any JobStore,
        projectionBuilder: HistoryProjectionBuilder? = nil
    ) {
        self.jobStore = jobStore
        self.projectionBuilder = projectionBuilder ?? HistoryProjectionBuilder(jobStore: jobStore)
    }

    public func spawnChildTask(
        parentTaskID: String,
        request: ChildTaskRequest,
        createdAt: Date = Date()
    ) async throws -> TaskRecord {
        guard let parentTask = try await jobStore.task(taskID: parentTaskID) else {
            throw JobStoreError.taskNotFound(parentTaskID)
        }
        let projection = try await projectionBuilder.buildChildProjection(
            parentTask: parentTask,
            brief: request.brief,
            constraints: request.constraints,
            expectedOutputs: request.expectedOutputs,
            artifactRefs: request.artifactRefs
        )
        let childTask = TaskRecord(
            rootSessionID: parentTask.rootSessionID,
            parentTaskID: parentTask.taskID,
            capabilityRequirements: request.capabilityRequirements,
            historyProjection: projection,
            priority: request.priority,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let created = try await jobStore.createTask(
            childTask,
            idempotencyKey: "task.submitted.\(childTask.taskID)"
        )
        _ = try await reconcileParent(parentTaskID: parentTaskID, now: createdAt)
        return created
    }

    public func childTasks(parentTaskID: String) async throws -> [TaskRecord] {
        try await jobStore.tasks(statuses: nil)
            .filter { $0.parentTaskID == parentTaskID }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    @discardableResult
    public func reconcileParent(parentTaskID: String, now: Date = Date()) async throws -> TaskEvent? {
        guard let parentTask = try await jobStore.task(taskID: parentTaskID) else {
            throw JobStoreError.taskNotFound(parentTaskID)
        }
        guard [.submitted, .assigned, .running, .waiting].contains(parentTask.status) else {
            return nil
        }

        let children = try await childTasks(parentTaskID: parentTaskID)
        guard !children.isEmpty else {
            return nil
        }

        let counts = Dictionary(grouping: children, by: \.status).mapValues(\.count)
        let summaryParts: [String] = TaskRecord.Status.allCases
            .compactMap { status in
                guard let count = counts[status], count > 0 else { return nil }
                return "\(count) \(status.rawValue)"
            }
        let summary = "Child task fan-out: " + summaryParts.joined(separator: ", ")
        let idempotencyKey = "task.children.\(parentTaskID)." + TaskRecord.Status.allCases
            .map { "\($0.rawValue):\(counts[$0] ?? 0)" }
            .joined(separator: "|")

        return try await jobStore.appendProgress(
            taskID: parentTaskID,
            workerID: nil,
            summary: summary,
            data: counts.reduce(into: [:]) { partialResult, entry in
                partialResult[entry.key.rawValue] = String(entry.value)
            },
            idempotencyKey: idempotencyKey,
            now: now
        )
    }
}

private extension TaskRecord.Status {
    static var allCases: [TaskRecord.Status] {
        [.submitted, .assigned, .running, .waiting, .completed, .failed, .cancelled]
    }
}
