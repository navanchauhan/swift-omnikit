import Foundation
import Testing
import OmniAgentMesh
import TheAgentWorkerKit
@testable import TheAgentControlPlaneKit

@Suite
struct RemoteSchedulingTests {
    @Test
    func rootSchedulerDispatchesRemoteWorkerViaMeshClient() async throws {
        let stateRoot = try makeStateRoot()
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let meshServer = MeshServer(jobStore: jobStore)
        let remoteStore = MeshClient(server: meshServer)
        let scheduler = RootScheduler(jobStore: jobStore)

        let remoteWorker = WorkerDaemon(
            displayName: "remote-worker",
            capabilities: WorkerCapabilities(["linux", "gpu"]),
            jobStore: remoteStore,
            artifactStore: artifactStore,
            executor: LocalTaskExecutor { task, reportProgress in
                try await reportProgress("remote progress", ["task_id": task.taskID])
                return LocalTaskExecutionResult(summary: "remote completed")
            },
            leaseDuration: 5
        )
        try await scheduler.registerRemoteWorker(remoteWorker, at: Date(timeIntervalSince1970: 1_000))

        let task = try await scheduler.submitTask(
            rootSessionID: "root",
            historyProjection: HistoryProjection(taskBrief: "Run on remote worker"),
            capabilityRequirements: ["linux"],
            priority: 1,
            createdAt: Date(timeIntervalSince1970: 1_001)
        )
        let stream = try await remoteStore.subscribe(taskID: task.taskID, afterSequence: nil)

        let finished = try await scheduler.dispatchNextAvailableTask(now: Date(timeIntervalSince1970: 1_002))
        let stored = try await jobStore.task(taskID: task.taskID)
        let streamedEvents = await take(6, from: stream)
        let progressEvents = streamedEvents.filter { $0.kind == .progress }

        #expect(finished?.taskID == task.taskID)
        #expect(stored?.status == .completed)
        #expect(streamedEvents.map(\.kind) == [.submitted, .assigned, .started, .progress, .progress, .completed])
        #expect(progressEvents.contains { $0.summary?.localizedStandardContains("task started") == true })
        #expect(progressEvents.contains { $0.summary == "remote progress" })
    }

    private func take(_ count: Int, from stream: AsyncStream<TaskEvent>) async -> [TaskEvent] {
        var iterator = stream.makeAsyncIterator()
        var collected: [TaskEvent] = []
        while collected.count < count, let event = await iterator.next() {
            collected.append(event)
        }
        return collected
    }

    private func makeStateRoot() throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-remote-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
