import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentWorkerKit

@Suite
struct NestedDelegationTests {
    @Test
    func childWorkerManagerBuildsBoundedProjectionAndRollsUpParentProgress() async throws {
        let stateRoot = try makeStateRoot()
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let parentCreatedAt = Date(timeIntervalSince1970: 100)
        let parentTask = TaskRecord(
            taskID: "parent-task",
            rootSessionID: "root",
            capabilityRequirements: ["swift"],
            historyProjection: HistoryProjection(
                taskBrief: "Implement the feature",
                summaries: ["summary-1", "summary-2", "summary-3"],
                parentExcerpts: ["excerpt-1", "excerpt-2", "excerpt-3"],
                artifactRefs: ["artifact-a", "artifact-b"]
            ),
            status: .running,
            createdAt: parentCreatedAt,
            updatedAt: parentCreatedAt
        )
        _ = try await jobStore.createTask(parentTask, idempotencyKey: "task.submitted.parent-task")
        _ = try await jobStore.startTask(
            taskID: parentTask.taskID,
            workerID: "parent-worker",
            now: parentCreatedAt.addingTimeInterval(1),
            idempotencyKey: "task.started.parent-task"
        )
        _ = try await jobStore.appendProgress(
            taskID: parentTask.taskID,
            workerID: "parent-worker",
            summary: "halfway complete",
            data: [:],
            idempotencyKey: "task.progress.parent-task",
            now: parentCreatedAt.addingTimeInterval(2)
        )

        let builder = HistoryProjectionBuilder(
            jobStore: jobStore,
            bounds: HistoryProjectionBounds(maxSummaries: 2, maxParentExcerpts: 2, maxArtifacts: 2)
        )
        let manager = ChildWorkerManager(jobStore: jobStore, projectionBuilder: builder)
        let childTask = try await manager.spawnChildTask(
            parentTaskID: parentTask.taskID,
            request: ChildTaskRequest(
                brief: "Review the implementation",
                capabilityRequirements: ["review"],
                expectedOutputs: ["review.txt"],
                artifactRefs: ["artifact-c"]
            ),
            createdAt: parentCreatedAt.addingTimeInterval(3)
        )

        #expect(childTask.parentTaskID == parentTask.taskID)
        #expect(childTask.historyProjection.taskBrief == "Review the implementation")
        #expect(childTask.historyProjection.summaries.count == 2)
        #expect(childTask.historyProjection.summaries.contains("halfway complete"))
        #expect(childTask.historyProjection.parentExcerpts.count == 2)
        #expect(childTask.historyProjection.artifactRefs == ["artifact-b", "artifact-c"])

        let initialParentEvents = try await jobStore.events(taskID: parentTask.taskID, afterSequence: nil)
        #expect(initialParentEvents.last?.summary?.contains("Child task fan-out") == true)

        _ = try await jobStore.completeTask(
            taskID: childTask.taskID,
            workerID: "review-worker",
            summary: "review finished",
            artifactRefs: [],
            idempotencyKey: "task.completed.child",
            now: parentCreatedAt.addingTimeInterval(4)
        )
        _ = try await manager.reconcileParent(parentTaskID: parentTask.taskID, now: parentCreatedAt.addingTimeInterval(5))

        let finalParentEvents = try await jobStore.events(taskID: parentTask.taskID, afterSequence: nil)
        #expect(finalParentEvents.last?.summary?.contains("completed") == true)
    }

    private func makeStateRoot() throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-nested-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
