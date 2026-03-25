import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentControlPlaneKit

@Suite
struct DoctorServiceTests {
    @Test
    func doctorAggregatesPairingsWorkersSkillsMissionsDeliveriesAndRoutePolicy() async throws {
        let stateRoot = try makeStateRoot(prefix: "doctor-service")
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.deliveriesDatabaseURL)
        let skillStore = try SQLiteSkillStore(fileURL: stateRoot.skillsDatabaseURL)
        let pairingStore = PairingStore(fileURL: stateRoot.runtimeDirectoryURL.appending(path: "pairings.json"))
        let scope = SessionScope(actorID: "chief", workspaceID: "workspace-a", channelID: "dm-a")
        let now = Date(timeIntervalSince1970: 1_000)

        try await identityStore.saveWorkspace(
            WorkspaceRecord(workspaceID: scope.workspaceID, displayName: "Workspace A", kind: .personal)
        )
        try await identityStore.saveChannelBinding(
            ChannelBinding(
                transport: .telegram,
                externalID: "dm:alice",
                workspaceID: scope.workspaceID,
                channelID: scope.channelID,
                actorID: scope.actorID
            )
        )
        _ = try await pairingStore.issueCode(
            transport: .telegram,
            actorExternalID: "alice",
            workspaceID: scope.workspaceID,
            ttl: 600,
            now: now
        )
        try await jobStore.upsertWorker(
            WorkerRecord(
                workerID: "worker-1",
                displayName: "linux-worker",
                capabilities: ["linux"],
                state: .idle,
                lastHeartbeatAt: now.addingTimeInterval(-300)
            )
        )
        _ = try await jobStore.createTask(
            TaskRecord(
                taskID: "stalled-task",
                rootSessionID: scope.sessionID,
                requesterActorID: scope.actorID,
                workspaceID: scope.workspaceID,
                channelID: scope.channelID,
                historyProjection: HistoryProjection(taskBrief: "Needs attention"),
                metadata: ["heartbeat_grace_seconds": "5"],
                createdAt: now.addingTimeInterval(-20),
                updatedAt: now.addingTimeInterval(-20)
            ),
            idempotencyKey: "task.submitted.stalled-task"
        )
        _ = try await missionStore.saveMission(
            MissionRecord(
                missionID: "mission-1",
                rootSessionID: scope.sessionID,
                requesterActorID: scope.actorID,
                workspaceID: scope.workspaceID,
                channelID: scope.channelID,
                title: "Active mission",
                brief: "Do the thing",
                executionMode: .workerTask,
                status: .executing
            )
        )
        _ = try await deliveryStore.saveDelivery(
            DeliveryRecord(
                idempotencyKey: "delivery-1",
                direction: .outbound,
                transport: .telegram,
                sessionID: scope.sessionID,
                actorID: scope.actorID,
                workspaceID: scope.workspaceID,
                channelID: scope.channelID,
                status: .deferred,
                summary: "Deferred delivery"
            )
        )
        _ = try await skillStore.saveInstallation(
            SkillInstallationRecord(
                skillID: "repo-helper",
                version: "1.0.0",
                scope: .workspace,
                workspaceID: scope.workspaceID,
                sourceType: .localDirectory,
                sourcePath: "/tmp/repo-helper",
                installedPath: "/tmp/repo-helper",
                digest: "abc"
            )
        )
        _ = try await skillStore.saveActivation(
            SkillActivationRecord(
                skillID: "repo-helper",
                version: "1.0.0",
                scope: .workspace,
                rootSessionID: scope.sessionID,
                workspaceID: scope.workspaceID,
                channelID: scope.channelID,
                actorID: scope.actorID,
                status: .active,
                reason: "test"
            )
        )

        let report = try await DoctorService(
            scope: scope,
            identityStore: identityStore,
            jobStore: jobStore,
            missionStore: missionStore,
            deliveryStore: deliveryStore,
            skillStore: skillStore,
            pairingStore: pairingStore,
            watchdog: TimeoutWatchdog(jobStore: jobStore),
            modelRouter: ModelRouter()
        ).report(now: now)

        #expect(report.channelBindings == 1)
        #expect(report.pendingPairings == 1)
        #expect(report.registeredWorkers == 1)
        #expect(report.staleWorkers == 1)
        #expect(report.stalledTasks == 1)
        #expect(report.installedSkills == 1)
        #expect(report.activeSkillActivations == 1)
        #expect(report.activeMissions == 1)
        #expect(report.deferredDeliveries == 1)
        #expect(report.routeTiers.contains("chat_light"))
        #expect(report.warnings.contains { $0.localizedStandardContains("Stalled tasks detected") })
        _ = conversationStore
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
