import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentControlPlaneKit

@Suite
struct TimeoutWatchdogTests {
    @Test
    func watchdogDistinguishesMissingHeartbeatAndWallClockTimeout() async throws {
        let stateRoot = try makeStateRoot(prefix: "watchdog")
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let now = Date(timeIntervalSince1970: 2_000)

        _ = try await jobStore.createTask(
            TaskRecord(
                taskID: "missing-heartbeat",
                rootSessionID: "root",
                historyProjection: HistoryProjection(taskBrief: "No worker picked this up"),
                metadata: ["heartbeat_grace_seconds": "5"],
                createdAt: now.addingTimeInterval(-20),
                updatedAt: now.addingTimeInterval(-20)
            ),
            idempotencyKey: "task.submitted.missing-heartbeat"
        )

        let deadlineTask = TaskRecord(
            taskID: "deadline-task",
            rootSessionID: "root",
            historyProjection: HistoryProjection(taskBrief: "Exceeded deadline"),
            deadlineAt: now.addingTimeInterval(-1),
            createdAt: now.addingTimeInterval(-30),
            updatedAt: now.addingTimeInterval(-30)
        )
        _ = try await jobStore.createTask(deadlineTask, idempotencyKey: "task.submitted.deadline-task")
        _ = try await jobStore.startTask(
            taskID: deadlineTask.taskID,
            workerID: "worker-1",
            now: now.addingTimeInterval(-25),
            idempotencyKey: "task.started.deadline-task"
        )

        let stalled = try await TimeoutWatchdog(jobStore: jobStore).stalledTasks(now: now)
        let reasons = Dictionary(uniqueKeysWithValues: stalled.map { ($0.task.taskID, $0.reason) })

        #expect(reasons["missing-heartbeat"] == .missingHeartbeat)
        #expect(reasons["deadline-task"] == .wallClockTimeout)
    }

    private func makeStateRoot(prefix: String) throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
