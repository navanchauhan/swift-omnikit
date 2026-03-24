import Foundation
import Testing
import OmniAgentMesh
import TheAgentWorkerKit
@testable import TheAgentControlPlaneKit

@Suite
struct RootControlPlaneTests {
    @Test
    func rootConversationMaintainsHotWindowAndSummary() async throws {
        let stateRoot = try makeStateRoot(prefix: "conversation")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let conversation = RootConversation(sessionID: "root", store: conversationStore, hotWindowLimit: 2)

        _ = try await conversation.recordUserText("first")
        _ = try await conversation.recordAssistantText("second")
        _ = try await conversation.recordUserText("third")

        let snapshot = try await conversation.snapshot()

        #expect(snapshot.hotContext.count == 2)
        #expect(snapshot.hotContext.first?.content == "second")
        #expect(snapshot.summary?.lastCompactedSequence == 1)
    }

    @Test
    func rootServerDelegatesToLocalWorkerAndRestoresNotifications() async throws {
        let stateRoot = try makeStateRoot(prefix: "root-worker")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let scheduler = RootScheduler(jobStore: jobStore)
        let rootServer = RootAgentServer(
            sessionID: "root",
            conversationStore: conversationStore,
            jobStore: jobStore,
            hotWindowLimit: 3,
            notificationPolicy: NotificationPolicy(interruptThreshold: .important),
            scheduler: scheduler
        )

        let worker = WorkerDaemon(
            displayName: "local-worker",
            capabilities: WorkerCapabilities(["macOS", "swift"]),
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: LocalTaskExecutor { task, reportProgress in
                try await reportProgress("Worker started task", ["task_id": task.taskID])
                return LocalTaskExecutionResult(summary: "Worker finished delegated task")
            },
            leaseDuration: 5
        )
        try await rootServer.registerLocalWorker(worker, at: Date(timeIntervalSince1970: 3_000))

        _ = try await rootServer.handleUserText("Please run the delegated task.")
        let submittedTask = try await rootServer.delegateTask(
            brief: "Run the delegated task",
            capabilityRequirements: ["macOS"],
            expectedOutputs: ["status-note"]
        )
        let notifications = try await rootServer.dispatchAndRefresh(now: Date(timeIntervalSince1970: 3_001))

        #expect(submittedTask.status == .submitted)
        #expect(notifications.count == 1)
        #expect(notifications.first?.taskID == submittedTask.taskID)

        let reopenedConversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let reopenedJobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let reopenedServer = RootAgentServer(
            sessionID: "root",
            conversationStore: reopenedConversationStore,
            jobStore: reopenedJobStore,
            hotWindowLimit: 3,
            notificationPolicy: NotificationPolicy(interruptThreshold: .important),
            scheduler: RootScheduler(jobStore: reopenedJobStore)
        )
        let restoredSnapshot = try await reopenedServer.restoreState()

        #expect(restoredSnapshot.unresolvedNotifications.count == 1)
        #expect(restoredSnapshot.unresolvedNotifications.first?.taskID == submittedTask.taskID)
        #expect(restoredSnapshot.hotContext.last?.modality == .notification)
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
