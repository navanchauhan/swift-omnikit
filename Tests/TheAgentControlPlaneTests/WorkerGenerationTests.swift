import Foundation
import Testing
import OmniAgentMesh
import TheAgentWorkerKit
@testable import TheAgentControlPlaneKit

@Suite
struct WorkerGenerationTests {
    @Test
    func schedulerPrefersRequiredGenerationAndIgnoresDrainingGeneration() async throws {
        let stateRoot = try makeStateRoot()
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let scheduler = RootScheduler(jobStore: jobStore)

        let generationOne = WorkerDaemon(
            displayName: "worker-gen-1",
            capabilities: WorkerCapabilities(["swift"]),
            generation: 1,
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: LocalTaskExecutor { _, _ in
                LocalTaskExecutionResult(summary: "gen-1")
            }
        )
        let generationTwo = WorkerDaemon(
            displayName: "worker-gen-2",
            capabilities: WorkerCapabilities(["swift"]),
            generation: 2,
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: LocalTaskExecutor { _, _ in
                LocalTaskExecutionResult(summary: "gen-2")
            }
        )

        try await scheduler.registerRemoteWorker(generationOne, at: Date(timeIntervalSince1970: 10))
        try await scheduler.registerRemoteWorker(generationTwo, at: Date(timeIntervalSince1970: 10))
        try await scheduler.markGenerationDraining(1, at: Date(timeIntervalSince1970: 11))

        _ = try await scheduler.submitTask(
            rootSessionID: "root",
            historyProjection: HistoryProjection(taskBrief: "generation-sensitive work"),
            capabilityRequirements: ["swift"],
            metadata: ["required_generation": "2"],
            createdAt: Date(timeIntervalSince1970: 12)
        )

        let finished = try await scheduler.dispatchNextAvailableTask(now: Date(timeIntervalSince1970: 13))
        let events = try await jobStore.events(taskID: finished?.taskID ?? "", afterSequence: nil)

        #expect(finished?.assignedAgentID == generationTwo.workerID)
        #expect(events.last?.summary == "gen-2")
    }

    private func makeStateRoot() throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "worker-generation-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
