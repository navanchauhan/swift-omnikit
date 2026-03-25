import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentWorkerKit

@Suite
struct WorkerDaemonTests {
    @Test
    func workerDrainOnceExecutesTaskAndPersistsArtifacts() async throws {
        let stateRoot = try makeStateRoot()
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)

        let task = TaskRecord(
            taskID: "task-run",
            rootSessionID: "root-session",
            capabilityRequirements: ["macOS", "swift"],
            historyProjection: HistoryProjection(taskBrief: "Run local worker slice")
        )
        _ = try await jobStore.createTask(task, idempotencyKey: "task.submitted.task-run")

        let worker = WorkerDaemon(
            displayName: "local-worker",
            capabilities: WorkerCapabilities(["macOS", "swift", "tests"]),
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: LocalTaskExecutor { task, reportProgress in
                try await reportProgress("Task is running", ["task_id": task.taskID])
                return LocalTaskExecutionResult(
                    summary: "Task completed successfully",
                    artifacts: [
                        LocalTaskExecutionArtifact(
                            name: "summary.txt",
                            contentType: "text/plain",
                            data: Data("ok".utf8)
                        )
                    ]
                )
            },
            leaseDuration: 5
        )
        _ = try await worker.register(at: Date(timeIntervalSince1970: 1_000))

        let finishedTask = try await worker.drainOnce(now: Date(timeIntervalSince1970: 1_001))
        let events = try await jobStore.events(taskID: task.taskID, afterSequence: nil)
        let artifacts = try await artifactStore.list(taskID: task.taskID)
        let progressEvents = events.filter { $0.kind == .progress }

        #expect(finishedTask?.status == .completed)
        #expect(events.map(\.kind) == [.submitted, .assigned, .started, .progress, .progress, .completed])
        #expect(progressEvents.contains { $0.summary?.localizedStandardContains("task started") == true })
        #expect(progressEvents.contains { $0.summary == "Task is running" })
        #expect(artifacts.count == 1)
        #expect(artifacts.first?.name == "summary.txt")
    }

    @Test
    func workerCanCancelBackgroundTask() async throws {
        let stateRoot = try makeStateRoot()
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)

        let task = TaskRecord(
            taskID: "task-cancel",
            rootSessionID: "root-session",
            capabilityRequirements: ["macOS"],
            historyProjection: HistoryProjection(taskBrief: "Cancel this task")
        )
        _ = try await jobStore.createTask(task, idempotencyKey: "task.submitted.task-cancel")

        let worker = WorkerDaemon(
            displayName: "local-worker",
            capabilities: WorkerCapabilities(["macOS"]),
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: LocalTaskExecutor { _, reportProgress in
                try await reportProgress("Started cancellable work", [:])
                try await Task.sleep(for: .seconds(5))
                try Task.checkCancellation()
                return LocalTaskExecutionResult(summary: "This should not be reached")
            },
            leaseDuration: 5
        )
        _ = try await worker.register(at: Date(timeIntervalSince1970: 2_000))

        let claimed = try await worker.runNextTaskInBackground(now: Date(timeIntervalSince1970: 2_001))
        #expect(claimed?.taskID == "task-cancel")

        await worker.cancel(taskID: "task-cancel")
        await worker.waitForTask(taskID: "task-cancel")

        let restoredTask = try await jobStore.task(taskID: "task-cancel")
        let events = try await jobStore.events(taskID: "task-cancel", afterSequence: nil)

        #expect(restoredTask?.status == .cancelled)
        #expect(events.last?.kind == .cancelled)
    }

    private func makeStateRoot() throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-worker-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
