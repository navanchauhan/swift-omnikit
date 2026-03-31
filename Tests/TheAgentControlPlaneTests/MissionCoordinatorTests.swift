import Foundation
import Testing
import OmniAgentDeliveryCore
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
            let data = try await harness.artifactStore.data(for: verificationArtifactID)
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            #expect(data != nil)
            #expect(text?.localizedStandardContains("Mission verification pending") == false)
            #expect(text?.localizedStandardContains("Status: completed") == true)
            #expect(text?.localizedStandardContains(finished.task?.taskID ?? "") == true)
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
                title: "Run gated worker mission",
                brief: "Only continue once approved.",
                capabilityRequirements: ["macOS"],
                expectedOutputs: ["report"],
                requireApproval: true,
                approvalPrompt: "Approve the mission?"
            )
        )

        #expect(started.mission.status == MissionRecord.Status.awaitingApproval)
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

        #expect(finished.mission.status == MissionRecord.Status.completed)
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

    @Test
    func deployableCodeChangeMissionCarriesDeliveryMetadataAndApproval() async throws {
        let harness = try makeHarness(
            prefix: "mission-deployable",
            scope: SessionScope(actorID: "chief", workspaceID: "workspace-deploy", channelID: "dm-deploy"),
            workspacePolicy: WorkspacePolicy(
                defaultRepoChangesDeployable: true,
                defaultDeploymentTarget: "canary",
                allowedDeploymentTargets: ["canary", "prod"],
                requireDeploymentApproval: true,
                allowAutomaticRollout: true
            )
        )

        let started = try await harness.server.startMission(
            MissionStartRequest(
                title: "Ship the feature",
                brief: "Implement the feature and deploy it",
                expectedOutputs: ["implementation", "deploy"],
                metadata: ["mission_kind": "code_change"]
            )
        )

        #expect(started.mission.status == .awaitingApproval)
        #expect(started.approvals.count == 1)
        #expect(started.mission.metadata["delivery_mode"] == "deployable")
        #expect(started.mission.metadata["deploy_target"] == "canary")
        #expect(started.mission.metadata["deploy_approval_required"] == "true")
        #expect(started.mission.metadata["auto_rollout_eligible"] == "true")
    }

    @Test
    func deployableCodeChangeMissionWithoutTargetBlocksForTargeting() async throws {
        let harness = try makeHarness(
            prefix: "mission-blocked-target",
            scope: SessionScope(actorID: "chief", workspaceID: "workspace-target", channelID: "dm-target"),
            workspacePolicy: WorkspacePolicy(
                defaultRepoChangesDeployable: true,
                allowedDeploymentTargets: ["staging", "prod"],
                requireDeploymentApproval: true
            )
        )

        let started = try await harness.server.startMission(
            MissionStartRequest(
                title: "Ship the feature",
                brief: "Implement the feature and deploy it",
                expectedOutputs: ["implementation", "deploy"],
                metadata: ["mission_kind": "code_change", "deployable": "true"]
            )
        )

        #expect(started.questions.count == 1)
        #expect(started.mission.metadata["delivery_mode"] == "blocked_for_targeting")
        #expect(started.mission.status == .awaitingUserInput || started.mission.status == .blocked)
        #expect(started.questions.first?.options == ["staging", "prod"])
    }

    @Test
    func deployableCodeChangeMissionCompletesWithReleaseBundleAndDeploymentState() async throws {
        let harness = try makeHarness(
            prefix: "mission-deploy-success",
            scope: SessionScope(actorID: "chief", workspaceID: "workspace-release", channelID: "dm-release"),
            workspacePolicy: WorkspacePolicy(
                defaultRepoChangesDeployable: true,
                defaultDeploymentTarget: "canary",
                allowedDeploymentTargets: ["canary", "prod"],
                requireDeploymentApproval: false,
                allowAutomaticRollout: true
            )
        )

        let implementationWorker = WorkerDaemon(
            displayName: "implementation-worker",
            capabilities: WorkerCapabilities(["lane:implementation", "swift"]),
            jobStore: harness.jobStore,
            artifactStore: harness.artifactStore,
            executor: LocalTaskExecutor { _, reportProgress in
                try await reportProgress("implementation running", [:])
                return LocalTaskExecutionResult(
                    summary: "implementation complete",
                    artifacts: [
                        LocalTaskExecutionArtifact(
                            name: "feature.swift",
                            contentType: "text/plain",
                            data: Data("func shippedFeature() -> Bool { true }\n".utf8)
                        ),
                    ]
                )
            }
        )
        let reviewWorker = WorkerDaemon(
            displayName: "review-worker",
            capabilities: WorkerCapabilities(["lane:review"]),
            jobStore: harness.jobStore,
            artifactStore: harness.artifactStore,
            executor: ReviewWorker().makeExecutor(artifactStore: harness.artifactStore)
        )
        let scenarioWorker = WorkerDaemon(
            displayName: "scenario-worker",
            capabilities: WorkerCapabilities(["lane:scenario"]),
            jobStore: harness.jobStore,
            artifactStore: harness.artifactStore,
            executor: ScenarioEvalWorker().makeExecutor()
        )
        try await harness.server.registerLocalWorker(implementationWorker)
        try await harness.server.registerLocalWorker(reviewWorker)
        try await harness.server.registerLocalWorker(scenarioWorker)

        let started = try await harness.server.startMission(
            MissionStartRequest(
                title: "Ship the feature",
                brief: "Implement the feature and deploy it",
                expectedOutputs: ["unit-tests", "smoke-tests"],
                metadata: [
                    "mission_kind": "code_change",
                    "version": "2.1.0",
                    "service": "the-agent",
                ]
            )
        )

        let finished = try await harness.server.waitForMission(
            missionID: started.mission.missionID,
            timeoutSeconds: 8
        )
        let activeRelease = try await harness.deploymentStore.activeRelease()

        #expect(finished.mission.status == .completed)
        #expect(finished.mission.metadata["delivery_mode"] == "deployable")
        #expect(finished.mission.metadata["release_bundle_id"] != nil)
        #expect(finished.mission.metadata["release_id"] != nil)
        #expect(finished.mission.metadata["deployment_state"] == DeploymentRecord.State.live.rawValue)
        #expect(finished.mission.metadata["health_status"] == DeploymentRecord.HealthStatus.healthy.rawValue)
        #expect(finished.mission.metadata["delivery_summary"]?.localizedStandardContains("deployed") == true)
        #expect(finished.stages.contains { $0.kind == .implement && $0.status == .completed })
        #expect(finished.stages.contains { $0.kind == .review && $0.status == .completed })
        #expect(finished.stages.contains { $0.kind == .scenario && $0.status == .completed })
        #expect(finished.stages.contains { $0.kind == .judge && $0.status == .completed })
        #expect(finished.stages.contains { $0.kind == .finalize && $0.status == .completed })
        #expect(activeRelease?.releaseID == finished.mission.metadata["release_id"])
        #expect(activeRelease?.releaseBundleID == finished.mission.metadata["release_bundle_id"])
        #expect(activeRelease?.state == .live)
        #expect(activeRelease?.slot == .active)
    }

    private func makeHarness(
        prefix: String,
        scope: SessionScope,
        workspacePolicy: WorkspacePolicy = WorkspacePolicy()
    ) throws -> MissionHarness {
        let stateRoot = try makeStateRoot(prefix: prefix)
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.missionsDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let deploymentStore = try SQLiteDeploymentStore(fileURL: stateRoot.deploymentDatabaseURL)
        let releaseBundleStore = try FileReleaseBundleStore(
            rootDirectory: stateRoot.releasesDirectoryURL.appending(path: "bundles", directoryHint: .isDirectory)
        )
        let releaseController = ReleaseController(
            deploymentStore: deploymentStore,
            supervisor: Supervisor(releasesDirectory: stateRoot.releasesDirectoryURL),
            healthService: DeployHealthService { _ in
                DeployHealthOutcome(status: .healthy, summary: "healthy")
            }
        )
        let server = RootAgentServer(
            scope: scope,
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore,
            releaseBundleStore: releaseBundleStore,
            releaseController: releaseController,
            workspacePolicy: workspacePolicy
        )
        return MissionHarness(
            scope: scope,
            stateRoot: stateRoot,
            conversationStore: conversationStore,
            missionStore: missionStore,
            deliveryStore: deliveryStore,
            jobStore: jobStore,
            artifactStore: artifactStore,
            deploymentStore: deploymentStore,
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
    let deploymentStore: SQLiteDeploymentStore
    let server: RootAgentServer
}
