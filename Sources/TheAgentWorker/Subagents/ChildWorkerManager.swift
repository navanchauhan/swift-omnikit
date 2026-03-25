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

public enum ChildWorkerManagerError: Error, CustomStringConvertible {
    case recursionDepthExceeded(parentTaskID: String, maximumDepth: Int)
    case delegationBudgetExhausted(parentTaskID: String)

    public var description: String {
        switch self {
        case .recursionDepthExceeded(let parentTaskID, let maximumDepth):
            return "Task \(parentTaskID) already reached the maximum delegation depth of \(maximumDepth)."
        case .delegationBudgetExhausted(let parentTaskID):
            return "Task \(parentTaskID) exhausted its remaining delegation budget."
        }
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
        let currentDepth = try await delegationDepth(task: parentTask)
        if let maxDepth = maxRecursionDepth(for: parentTask),
           currentDepth >= maxDepth {
            throw ChildWorkerManagerError.recursionDepthExceeded(
                parentTaskID: parentTaskID,
                maximumDepth: maxDepth
            )
        }
        if let remainingBudget = remainingDelegationBudget(for: parentTask),
           remainingBudget <= 0 {
            throw ChildWorkerManagerError.delegationBudgetExhausted(parentTaskID: parentTaskID)
        }

        var constraints = request.constraints
        constraints.append("delegation_depth=\(currentDepth + 1)")
        if let maxDepth = maxRecursionDepth(for: parentTask) {
            constraints.append("max_recursion_depth=\(maxDepth)")
        }
        if let remainingBudget = remainingDelegationBudget(for: parentTask) {
            constraints.append("budget_units_remaining=\(max(0, remainingBudget - 1))")
        }
        if let missionID = parentTask.missionID {
            constraints.append("mission_id=\(missionID)")
        }
        constraints = normalizedConstraints(constraints)
        let projection = try await projectionBuilder.buildChildProjection(
            parentTask: parentTask,
            brief: request.brief,
            constraints: constraints,
            expectedOutputs: request.expectedOutputs,
            artifactRefs: request.artifactRefs
        )
        let childTask = TaskRecord(
            rootSessionID: parentTask.rootSessionID,
            requesterActorID: parentTask.requesterActorID,
            workspaceID: parentTask.workspaceID,
            channelID: parentTask.channelID,
            missionID: parentTask.missionID,
            parentTaskID: parentTask.taskID,
            capabilityRequirements: request.capabilityRequirements,
            historyProjection: projection,
            metadata: parentTask.metadata,
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

    private func delegationDepth(task: TaskRecord) async throws -> Int {
        var depth = constraintIntValue(prefix: "delegation_depth=", constraints: task.historyProjection.constraints) ?? 0
        var currentParentID: String? = task.parentTaskID
        while let parentTaskID = currentParentID {
            guard let parent = try await jobStore.task(taskID: parentTaskID) else {
                break
            }
            depth = max(depth, (constraintIntValue(prefix: "delegation_depth=", constraints: parent.historyProjection.constraints) ?? 0) + 1)
            currentParentID = parent.parentTaskID
        }
        return depth
    }

    private func maxRecursionDepth(for task: TaskRecord) -> Int? {
        constraintIntValue(prefix: "max_recursion_depth=", constraints: task.historyProjection.constraints)
    }

    private func remainingDelegationBudget(for task: TaskRecord) -> Int? {
        constraintIntValue(prefix: "budget_units_remaining=", constraints: task.historyProjection.constraints)
    }

    private func constraintIntValue(prefix: String, constraints: [String]) -> Int? {
        constraints.first(where: { $0.hasPrefix(prefix) })
            .flatMap { Int($0.dropFirst(prefix.count)) }
    }

    private func normalizedConstraints(_ constraints: [String]) -> [String] {
        var mergedByPrefix: [String: String] = [:]
        let knownPrefixes = [
            "delegation_depth=",
            "max_recursion_depth=",
            "budget_units_remaining=",
            "mission_id=",
        ]

        var passthrough: [String] = []
        for constraint in constraints {
            if let prefix = knownPrefixes.first(where: { constraint.hasPrefix($0) }) {
                mergedByPrefix[prefix] = constraint
            } else if !passthrough.contains(constraint) {
                passthrough.append(constraint)
            }
        }

        return passthrough + knownPrefixes.compactMap { mergedByPrefix[$0] }
    }
}

private extension TaskRecord.Status {
    static var allCases: [TaskRecord.Status] {
        [.submitted, .assigned, .running, .waiting, .completed, .failed, .cancelled]
    }
}
