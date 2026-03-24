import Foundation
import Testing
@testable import OmniAgentMesh

@Suite
struct SQLiteStoresTests {
    @Test
    func conversationStorePersistsInteractionsSummaryAndNotifications() async throws {
        let stateRoot = try makeStateRoot()
        let store = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)

        let sessionID = "root-session"
        let first = try await store.appendInteraction(
            InteractionItem(
                sessionID: sessionID,
                role: .user,
                modality: .text,
                content: "hello root"
            )
        )
        let second = try await store.appendInteraction(
            InteractionItem(
                sessionID: sessionID,
                role: .assistant,
                modality: .chat,
                content: "hello worker"
            )
        )

        try await store.saveSummary(
            ConversationSummary(
                sessionID: sessionID,
                summaryText: "user greeted the root; assistant responded",
                hotWindowLimit: 1,
                lastCompactedSequence: first.sequenceNumber
            )
        )

        let notification = NotificationRecord(
            sessionID: sessionID,
            taskID: "task-1",
            title: "Task Completed",
            body: "Worker finished the delegated task.",
            importance: .important
        )
        _ = try await store.saveNotification(notification)
        _ = try await store.markNotificationDelivered(notificationID: notification.notificationID, at: Date())

        let reopened = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let restoredItems = try await reopened.interactions(sessionID: sessionID, limit: nil)
        let restoredSummary = try await reopened.loadSummary(sessionID: sessionID)
        let restoredNotifications = try await reopened.notifications(sessionID: sessionID, unresolvedOnly: true)

        #expect(first.sequenceNumber == 1)
        #expect(second.sequenceNumber == 2)
        #expect(restoredItems.count == 2)
        #expect(restoredItems.last?.content == "hello worker")
        #expect(restoredSummary?.lastCompactedSequence == 1)
        #expect(restoredNotifications.count == 1)
        #expect(restoredNotifications.first?.status == .delivered)
    }

    @Test
    func jobStoreReplaysEventsAndRecoversExpiredLeases() async throws {
        let stateRoot = try makeStateRoot()
        let store = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)

        let createdAt = Date(timeIntervalSince1970: 1_000)
        let task = TaskRecord(
            taskID: "task-1",
            rootSessionID: "root-session",
            capabilityRequirements: ["macOS", "swift"],
            historyProjection: HistoryProjection(
                taskBrief: "Run unit tests",
                summaries: ["current branch builds cleanly"],
                parentExcerpts: ["Please run the agent mesh tests"],
                constraints: ["keep output concise"],
                expectedOutputs: ["test-summary.txt"]
            ),
            priority: 7,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        _ = try await store.createTask(task, idempotencyKey: "submitted-task-1")
        try await store.upsertWorker(
            WorkerRecord(
                workerID: "worker-local",
                displayName: "local daemon",
                capabilities: ["macOS", "swift", "xcode"],
                lastHeartbeatAt: createdAt
            )
        )

        let claimed = try await store.claimNextTask(
            workerID: "worker-local",
            capabilities: ["macOS", "swift", "xcode"],
            leaseDuration: 5,
            now: createdAt.addingTimeInterval(1)
        )
        #expect(claimed?.status == .assigned)

        _ = try await store.startTask(
            taskID: task.taskID,
            workerID: "worker-local",
            now: createdAt.addingTimeInterval(2),
            idempotencyKey: "task-started"
        )
        _ = try await store.appendProgress(
            taskID: task.taskID,
            workerID: "worker-local",
            summary: "Tests are 50 percent complete",
            data: ["percent": "50"],
            idempotencyKey: "task-progress-1",
            now: createdAt.addingTimeInterval(3)
        )

        let reopened = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let replayedEvents = try await reopened.events(taskID: task.taskID, afterSequence: nil)
        #expect(replayedEvents.count == 4)
        #expect(replayedEvents.map(\.kind) == [.submitted, .assigned, .started, .progress])

        let recovered = try await reopened.recoverOrphanedTasks(now: createdAt.addingTimeInterval(30))
        let restoredTask = try await reopened.task(taskID: task.taskID)
        let recoveredEvents = try await reopened.events(taskID: task.taskID, afterSequence: nil)

        #expect(recovered.count == 1)
        #expect(restoredTask?.status == .waiting)
        #expect(recoveredEvents.map(\.kind).suffix(2) == [.resumed, .waiting])
    }

    @Test
    func artifactStorePersistsDataAcrossReopen() async throws {
        let stateRoot = try makeStateRoot()
        let store = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)

        let record = try await store.put(
            ArtifactPayload(
                taskID: "task-1",
                missionID: "mission-1",
                workspaceID: "workspace-alpha",
                channelID: "telegram-dm",
                name: "build log.txt",
                contentType: "text/plain",
                data: Data("build output".utf8)
            )
        )

        let reopened = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let restoredData = try await reopened.data(for: record.artifactID)
        let taskArtifacts = try await reopened.list(taskID: "task-1")

        #expect(restoredData.map { String(decoding: $0, as: UTF8.self) } == "build output")
        #expect(taskArtifacts.count == 1)
        #expect(taskArtifacts.first?.name == "build log.txt")
        #expect(taskArtifacts.first?.missionID == "mission-1")
        #expect(taskArtifacts.first?.workspaceID == "workspace-alpha")
        #expect(taskArtifacts.first?.channelID == "telegram-dm")
    }

    @Test
    func deploymentStoreKeepsReleaseStateSeparateFromJobState() async throws {
        let stateRoot = try makeStateRoot()
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let deploymentStore = try SQLiteDeploymentStore(fileURL: stateRoot.deploymentDatabaseURL)

        let task = TaskRecord(
            taskID: "task-keep",
            rootSessionID: "root-session",
            capabilityRequirements: ["linux"],
            historyProjection: HistoryProjection(taskBrief: "Keep running during release swap")
        )
        _ = try await jobStore.createTask(task, idempotencyKey: "submitted-task-keep")

        try await deploymentStore.saveRelease(
            DeploymentRecord(
                releaseID: "release-1",
                version: "1.0.0",
                state: .live,
                drainingTaskIDs: ["task-keep"],
                checkpointDirectory: stateRoot.checkpointsDirectoryURL.path()
            ),
            makeActive: true
        )

        let activeRelease = try await deploymentStore.activeRelease()
        let queuedTasks = try await jobStore.tasks(statuses: nil)

        #expect(activeRelease?.releaseID == "release-1")
        #expect(queuedTasks.count == 1)
        #expect(queuedTasks.first?.taskID == "task-keep")
    }

    private func makeStateRoot() throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-agent-mesh-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
