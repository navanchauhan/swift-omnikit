import Foundation
import Testing
import OmniAIAttractor
import OmniAgentMesh
import OmniSkills
@testable import TheAgentControlPlaneKit
@testable import TheAgentWorkerKit

@Suite
struct OmniSkillRemoteWorkerProofTests {
    @Test
    func activatedWorkspaceSkillAffectsRemoteAttractorExecutionOverHTTPMesh() async throws {
        let stateRoot = try makeStateRoot(prefix: "skill-remote-proof")
        let scope = SessionScope(actorID: "chief", workspaceID: "workspace-remote", channelID: "dm-remote")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.deliveriesDatabaseURL)
        let skillStore = try SQLiteSkillStore(fileURL: stateRoot.skillsDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let rootServer = RootAgentServer(
            scope: scope,
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            skillStore: skillStore,
            skillsRootDirectory: stateRoot.skillsDirectoryURL,
            runtimeRootDirectory: stateRoot.runtimeDirectoryURL,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore,
            workingDirectory: stateRoot.rootDirectory.path()
        )

        let skillSource = try writeSkillPackage(
            root: stateRoot.rootDirectory.appending(path: "remote-skill-source", directoryHint: .isDirectory),
            manifest: OmniSkillManifest(
                skillID: "remote.reviewer",
                version: "1.0.0",
                displayName: "Remote Reviewer",
                summary: "Remote worker review skill.",
                projectionSurfaces: [.rootPrompt, .codergen, .attractor],
                budgetHints: OmniSkillBudgetHints(preferredModelTier: "reviewer"),
                promptFile: "prompt.md",
                codergenPromptFile: "codergen.md",
                attractorPromptFile: "attractor.md"
            ),
            assets: [
                "prompt.md": "Remote reviewer skill overlay.",
                "codergen.md": "Prefer remote-safe patches.",
                "attractor.md": "Validate remote artifacts before completion.",
            ]
        )
        _ = try await rootServer.installSkill(from: skillSource.path(), scope: .workspace)
        _ = try await rootServer.activateSkill(
            skillID: "remote.reviewer",
            activationScope: .workspace,
            approved: true
        )

        let meshServer = HTTPMeshServer(
            jobStore: jobStore,
            artifactStore: artifactStore,
            host: "127.0.0.1",
            port: 0
        )
        let listeningAddress = try await meshServer.start()
        defer {
            Task { try? await meshServer.stop() }
        }

        let remoteStore = HTTPMeshClient(baseURL: listeningAddress.baseURL)
        let backend = RecordingCodergenBackend(
            results: Array(
                repeating: CodergenResult(response: "Remote proof stage complete.", status: .success),
                count: 5
            )
        )
        let workerDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-remote-worker-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: workerDirectory, withIntermediateDirectories: true)
        let executionMode = WorkerExecutionMode.attractor(
            AttractorWorkerRuntimeOptions(
                provider: "",
                model: "",
                reasoningEffort: "",
                workingDirectory: workerDirectory.path(),
                logsRoot: workerDirectory.path(),
                backend: backend
            )
        )
        let remoteWorker = WorkerDaemon(
            displayName: "remote-attractor-worker",
            capabilities: WorkerCapabilities(["linux", "execution:attractor"]),
            jobStore: remoteStore,
            artifactStore: remoteStore,
            executor: WorkerExecutorFactory.makeExecutor(mode: executionMode),
            leaseDuration: 5
        )
        _ = try await remoteWorker.register(metadata: WorkerExecutorFactory.metadata(for: executionMode))

        let started = try await rootServer.startMission(
            MissionStartRequest(
                title: "Remote skill proof",
                brief: "Run the remote attractor workflow.",
                executionMode: .attractorWorkflow,
                capabilityRequirements: ["linux"],
                expectedOutputs: ["artifact"]
            )
        )

        let workerLoop = Task {
            try await remoteWorker.runLoop(pollInterval: Duration.milliseconds(100), maxIdlePolls: 10)
        }
        defer { workerLoop.cancel() }

        let finished = try await rootServer.waitForMission(
            missionID: started.mission.missionID,
            timeoutSeconds: 10
        )
        let calls = await backend.calls()
        let firstCall = try #require(calls.first)
        let artifacts = try await artifactStore.list(
            taskID: nil,
            missionID: started.mission.missionID,
            workspaceID: scope.workspaceID
        )

        #expect(finished.mission.status == .completed)
        #expect(finished.task?.status == .completed)
        #expect(firstCall.prompt.localizedStandardContains("Active skills"))
        #expect(firstCall.prompt.localizedStandardContains("Remote reviewer skill overlay"))
        #expect(firstCall.prompt.localizedStandardContains("Prefer remote-safe patches"))
        #expect(firstCall.contextSnapshot["task.skill_codergen_overlay"]?.localizedStandardContains("Prefer remote-safe patches") == true)
        #expect(firstCall.contextSnapshot["task.skill_attractor_overlay"]?.localizedStandardContains("Validate remote artifacts before completion") == true)
        #expect(!artifacts.isEmpty)
        #expect(artifacts.contains { $0.name.localizedStandardContains("pipeline-result") || $0.name.localizedStandardContains("response.md") })
    }

    private func writeSkillPackage(
        root: URL,
        manifest: OmniSkillManifest,
        assets: [String: String]
    ) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: root.appending(path: "omniskill.json"))
        for (relativePath, contents) in assets {
            let url = root.appending(path: relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
        return root
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
