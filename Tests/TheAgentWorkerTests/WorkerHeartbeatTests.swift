import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentWorkerKit

@Suite
struct WorkerHeartbeatTests {
    @Test
    func workerDaemonEmitsHeartbeatProgressMetadata() async throws {
        let stateRoot = try makeStateRoot(prefix: "worker-heartbeat")
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let task = TaskRecord(
            taskID: "heartbeat-task",
            rootSessionID: "root",
            capabilityRequirements: ["swift"],
            historyProjection: HistoryProjection(taskBrief: "Emit worker progress")
        )
        _ = try await jobStore.createTask(task, idempotencyKey: "task.submitted.heartbeat-task")

        let worker = WorkerDaemon(
            displayName: "heartbeat-worker",
            capabilities: WorkerCapabilities(["swift"]),
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: LocalTaskExecutor { _, reportProgress in
                try await reportProgress("Doing work", [:])
                return LocalTaskExecutionResult(summary: "Done.")
            }
        )
        _ = try await worker.register()
        _ = try await worker.drainOnce(now: Date(timeIntervalSince1970: 4_000))

        let events = try await jobStore.events(taskID: task.taskID, afterSequence: nil)
        let progressEvents = events.filter { $0.kind == .progress }

        #expect(progressEvents.contains { $0.data["heartbeat_source"] == "worker" && $0.data["heartbeat_phase"] == "started" })
        #expect(progressEvents.contains { $0.data["heartbeat_source"] == "worker" && $0.data["heartbeat_phase"] == "progress" })
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
