import Foundation
import Testing
@testable import OmniAgentMesh

@Suite
struct MeshTransportTests {
    @Test
    func meshClientReplaysMissedEventsAfterReconnect() async throws {
        let stateRoot = try makeStateRoot()
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let server = MeshServer(jobStore: jobStore)
        let client = MeshClient(server: server)

        let task = TaskRecord(
            taskID: "mesh-task",
            rootSessionID: "root",
            capabilityRequirements: ["remote"],
            historyProjection: HistoryProjection(taskBrief: "Stream progress over the mesh"),
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        _ = try await client.createTask(task, idempotencyKey: "task.submitted.mesh-task")
        try await client.upsertWorker(
            WorkerRecord(
                workerID: "remote-worker",
                displayName: "remote",
                capabilities: ["remote"],
                lastHeartbeatAt: Date(timeIntervalSince1970: 10)
            )
        )

        let firstStream = try await client.subscribe(taskID: task.taskID, afterSequence: nil)
        _ = try await client.claimNextTask(
            workerID: "remote-worker",
            capabilities: ["remote"],
            leaseDuration: 30,
            now: Date(timeIntervalSince1970: 11)
        )
        _ = try await client.startTask(
            taskID: task.taskID,
            workerID: "remote-worker",
            now: Date(timeIntervalSince1970: 12),
            idempotencyKey: "task.started.mesh-task"
        )
        _ = try await client.appendProgress(
            taskID: task.taskID,
            workerID: "remote-worker",
            summary: "halfway there",
            data: ["percent": "50"],
            idempotencyKey: "task.progress.mesh-task.1",
            now: Date(timeIntervalSince1970: 13)
        )

        let firstWave = await take(4, from: firstStream)
        #expect(firstWave.map(\.kind) == [.submitted, .assigned, .started, .progress])

        _ = try await client.appendProgress(
            taskID: task.taskID,
            workerID: "remote-worker",
            summary: "almost done",
            data: ["percent": "90"],
            idempotencyKey: "task.progress.mesh-task.2",
            now: Date(timeIntervalSince1970: 14)
        )
        _ = try await client.completeTask(
            taskID: task.taskID,
            workerID: "remote-worker",
            summary: "done",
            artifactRefs: [],
            idempotencyKey: "task.completed.mesh-task",
            now: Date(timeIntervalSince1970: 15)
        )

        let reconnectStream = try await client.subscribe(
            taskID: task.taskID,
            afterSequence: firstWave.last?.sequenceNumber
        )
        let replayed = await take(2, from: reconnectStream)

        #expect(replayed.map(\.kind) == [.progress, .completed])
        #expect(replayed.first?.summary == "almost done")
        #expect(replayed.last?.summary == "done")
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
            path: "omnikit-mesh-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
