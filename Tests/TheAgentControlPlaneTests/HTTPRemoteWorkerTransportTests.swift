import Foundation
import Testing
import OmniAgentMesh
import TheAgentWorkerKit
@testable import TheAgentControlPlaneKit

@Suite
struct HTTPRemoteWorkerTransportTests {
    @Test
    func remoteWorkerCompletesTaskOverHTTPMesh() async throws {
        let stateRoot = try makeStateRoot(prefix: "http-remote")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let rootServer = RootAgentServer(
            sessionID: "root",
            conversationStore: conversationStore,
            jobStore: jobStore,
            scheduler: RootScheduler(jobStore: jobStore)
        )

        let meshServer = HTTPMeshServer(
            jobStore: jobStore,
            artifactStore: artifactStore,
            host: "127.0.0.1",
            port: 0
        )
        let listeningAddress = try await meshServer.start()
        defer {
            Task {
                try? await meshServer.stop()
            }
        }

        let remoteStore = HTTPMeshClient(baseURL: listeningAddress.baseURL)
        let remoteWorker = WorkerDaemon(
            displayName: "linux-worker",
            capabilities: WorkerCapabilities(["linux"]),
            jobStore: remoteStore,
            artifactStore: remoteStore,
            executor: LocalTaskExecutor { task, reportProgress in
                try await reportProgress("remote http progress", ["task_id": task.taskID])
                return LocalTaskExecutionResult(
                    summary: "remote http completed",
                    artifacts: [
                        LocalTaskExecutionArtifact(
                            name: "remote-http.txt",
                            contentType: "text/plain",
                            data: Data("remote artifact".utf8)
                        ),
                    ]
                )
            },
            leaseDuration: 5
        )
        _ = try await remoteWorker.register(metadata: ["mode": "remote-http"])

        let submittedTask = try await rootServer.delegateTask(
            brief: "Run over http mesh",
            capabilityRequirements: ["linux"]
        )

        let workerLoop = Task {
            try await remoteWorker.runLoop(pollInterval: .milliseconds(100), maxIdlePolls: 5)
        }
        defer { workerLoop.cancel() }

        try await waitForTerminalTask(taskID: submittedTask.taskID, jobStore: jobStore, timeoutSeconds: 5)

        let stored = try await jobStore.task(taskID: submittedTask.taskID)
        let events = try await jobStore.events(taskID: submittedTask.taskID, afterSequence: nil)
        let notifications = try await rootServer.refreshTaskNotifications()
        let artifactID = try #require(stored?.artifactRefs.first)

        #expect(stored?.status == .completed)
        #expect(events.map(\.kind) == [.submitted, .assigned, .started, .progress, .completed])
        #expect(notifications.first?.taskID == submittedTask.taskID)
        #expect(try await artifactStore.data(for: artifactID) == Data("remote artifact".utf8))
    }

    private func waitForTerminalTask(
        taskID: String,
        jobStore: any JobStore,
        timeoutSeconds: Double
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let task = try await jobStore.task(taskID: taskID),
               task.status == .completed || task.status == .failed || task.status == .cancelled {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("Timed out waiting for task \(taskID) to finish.")
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
