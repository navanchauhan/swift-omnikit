import Foundation
import Testing
import OmniAgentMesh
import TheAgentWorkerKit
@testable import TheAgentControlPlaneKit

@Suite
struct MissionCoordinatorTests {
    @Test
    func workerMissionCompletesWithDurableArtifactsAndStages() async throws {
        let harness = try makeHarness(prefix: "mission-complete", scope: SessionScope(actorID: "chief", workspaceID: "workspace-a", channelID: "dm-a"))

        let worker = WorkerDaemon(
            displayName: "mission-worker",
            capabilities: WorkerCapabilities(["macOS", "swift"]),
            jobStore: harness.jobStore,
            artifactStore: harness.artifactStore,
            executor: LocalTaskExecutor { task, reportProgress in
                try await reportProgress("Working on mission", ["mission_id": task.missionID ?? ""])
                return LocalTaskExecutionResult(
                    summary: "Mission worker finished successfully.",
                    artifacts: [
                        LocalTaskExecutionArtifact(
                            name: "mission-note.txt",
                            contentType: "text/plain",
                            data: Data("worker artifact".utf8)
                        ),
                    ]
                )
            }
        )
        try await harness.server.registerLocalWorker(worker)

        let started = try await harness.server.startMission(
            MissionStartRequest(
                title: "Implement feature",
                brief: "Do the durable worker mission.",
                capabilityRequirements: ["macOS"],
                expectedOutputs: ["mission-note"]
            )
        )
        let finished = try await harness.server.waitForMission(
            missionID: started.mission.missionID,
            timeoutSeconds: 5
        )

        #expect(finished.mission.status == .completed)
        #expect(finished.task?.status == .completed)
        #expect(finished.stages.contains { $0.kind == .plan && $0.status == .completed })
        #expect(finished.stages.contains { $0.kind == .implement && $0.status == .completed })
        #expect(finished.mission.contractArtifactID != nil)
        #expect(finished.mission.progressArtifactID != nil)
        #expect(finished.mission.verificationArtifactID != nil)

        if let contractArtifactID = finished.mission.contractArtifactID {
            #expect(try await harness.artifactStore.data(for: contractArtifactID) != nil)
        } else {
            Issue.record("Expected a contract artifact to be created.")
        }
        if let progressArtifactID = finished.mission.progressArtifactID {
            #expect(try await harness.artifactStore.data(for: progressArtifactID) != nil)
        } else {
            Issue.record("Expected a progress artifact to be created.")
        }
        if let verificationArtifactID = finished.mission.verificationArtifactID {
            #expect(try await harness.artifactStore.data(for: verificationArtifactID) != nil)
        } else {
            Issue.record("Expected a verification artifact to be created.")
        }
    }

    @Test
    func approvalGatedMissionResumesAfterApprovalWithoutLosingExecutionContract() async throws {
        let harness = try makeHarness(prefix: "mission-approval", scope: SessionScope(actorID: "chief", workspaceID: "workspace-b", channelID: "dm-b"))

        let worker = WorkerDaemon(
            displayName: "approval-worker",
            capabilities: WorkerCapabilities(["macOS"]),
            jobStore: harness.jobStore,
            artifactStore: harness.artifactStore,
            executor: LocalTaskExecutor { task, reportProgress in
                try await reportProgress("Approval received", ["task_id": task.taskID])
                return LocalTaskExecutionResult(summary: "Approved mission finished.")
            }
        )
        try await harness.server.registerLocalWorker(worker)

        let started = try await harness.server.startMission(
            MissionStartRequest(
                title: "Deploy change",
                brief: "Only continue once approved.",
                capabilityRequirements: ["macOS"],
                expectedOutputs: ["deploy-report"],
                requireApproval: true,
                approvalPrompt: "Approve the deploy mission?"
            )
        )

        #expect(started.mission.status == .awaitingApproval)
        #expect(started.approvals.count == 1)

        let inbox = try await harness.server.listInbox()
        #expect(inbox.contains { $0.kind == .approval && $0.id == started.approvals.first?.requestID })

        let deferredDeliveries = try await harness.deliveryStore.deliveries(
            direction: .outbound,
            sessionID: harness.scope.sessionID,
            status: .deferred
        )
        #expect(deferredDeliveries.count == 1)

        let requestID = try #require(started.approvals.first?.requestID)
        _ = try await harness.server.approveRequest(
            requestID: requestID,
            approved: true,
            responseText: "Approved by test"
        )

        let finished = try await harness.server.waitForMission(
            missionID: started.mission.missionID,
            timeoutSeconds: 5
        )

        #expect(finished.mission.status == .completed)
        #expect(finished.task?.status == .completed)
        #expect(finished.task?.capabilityRequirements == ["macOS"])
    }

    @Test
    func inboxIsolationHoldsAcrossWorkspaceScopedServers() async throws {
        let sharedRoot = try makeStateRoot(prefix: "mission-isolation")
        let conversationStore = try SQLiteConversationStore(fileURL: sharedRoot.conversationDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: sharedRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: sharedRoot.missionsDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: sharedRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: sharedRoot.artifactsDirectoryURL)

        let serverA = RootAgentServer(
            scope: SessionScope(actorID: "chief-a", workspaceID: "workspace-a", channelID: "dm-a"),
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore
        )
        let serverB = RootAgentServer(
            scope: SessionScope(actorID: "chief-b", workspaceID: "workspace-b", channelID: "dm-b"),
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore
        )

        let missionA = try await serverA.startMission(
            MissionStartRequest(
                title: "Workspace A mission",
                brief: "Await approval in workspace A",
                requireApproval: true
            )
        )
        let missionB = try await serverB.startMission(
            MissionStartRequest(
                title: "Workspace B mission",
                brief: "Await approval in workspace B",
                requireApproval: true
            )
        )

        let inboxA = try await serverA.listInbox()
        let inboxB = try await serverB.listInbox()

        #expect(inboxA.count == 2)
        #expect(inboxB.count == 2)
        #expect(inboxA.allSatisfy { $0.body.localizedStandardContains("workspace A") || $0.body.localizedStandardContains("Await approval in workspace A") || $0.kind == .notification })
        #expect(inboxB.allSatisfy { $0.body.localizedStandardContains("workspace B") || $0.body.localizedStandardContains("Await approval in workspace B") || $0.kind == .notification })
        #expect(missionA.approvals.first?.requestID != missionB.approvals.first?.requestID)
    }

    private func makeHarness(prefix: String, scope: SessionScope) throws -> MissionHarness {
        let stateRoot = try makeStateRoot(prefix: prefix)
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.missionsDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let server = RootAgentServer(
            scope: scope,
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore
        )
        return MissionHarness(
            scope: scope,
            stateRoot: stateRoot,
            conversationStore: conversationStore,
            missionStore: missionStore,
            deliveryStore: deliveryStore,
            jobStore: jobStore,
            artifactStore: artifactStore,
            server: server
        )
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

private struct MissionHarness {
    let scope: SessionScope
    let stateRoot: AgentFabricStateRoot
    let conversationStore: SQLiteConversationStore
    let missionStore: SQLiteMissionStore
    let deliveryStore: SQLiteDeliveryStore
    let jobStore: SQLiteJobStore
    let artifactStore: FileArtifactStore
    let server: RootAgentServer
}
