import Foundation
import Testing
import OmniAgentMesh
import OmniSkills
@testable import TheAgentControlPlaneKit

@Suite
struct OmniSkillActivationTests {
    @Test
    func rootInstallActivateApprovalAndProjectionFlowIsDurable() async throws {
        let stateRoot = try makeStateRoot(prefix: "root-skill-activation")
        let scope = SessionScope(actorID: "chief", workspaceID: "workspace-skills", channelID: "dm-skills")
        let server = try makeServer(stateRoot: stateRoot, scope: scope)
        let source = try writeSkillPackage(
            root: stateRoot.rootDirectory.appending(path: "skill-source", directoryHint: .isDirectory),
            manifest: OmniSkillManifest(
                skillID: "repo.helper",
                version: "1.0.0",
                displayName: "Repo Helper",
                summary: "Repository-aware coding guidance.",
                projectionSurfaces: [.rootPrompt, .toolRegistry, .shellEnv, .codergen, .attractor],
                requiredCapabilities: ["filesystem"],
                promptFile: "prompt.md",
                codergenPromptFile: "codergen.md",
                attractorPromptFile: "attractor.md",
                shellPaths: ["shell/bootstrap.sh"],
                workerTools: [
                    OmniSkillToolDefinition(
                        name: "review_findings",
                        description: "Return the repo review rubric.",
                        instructionFile: "tools/review.md"
                    ),
                ]
            ),
            assets: [
                "prompt.md": "Use repo helper instructions before making changes.",
                "codergen.md": "Prefer small, reviewable patches.",
                "attractor.md": "Validate the repository state before completion.",
                "shell/bootstrap.sh": "#!/bin/sh\necho bootstrap\n",
                "tools/review.md": "List blocking findings first.",
            ]
        )

        let pending = try await server.installSkill(
            from: source.path(),
            scope: .workspace,
            activateAfterInstall: true,
            activationScope: .workspace,
            reason: "Need repository guidance."
        )
        let pendingActivation = try #require(pending.activation)
        let approval = try #require(pending.approvalRequest)
        let preApprovalStatus = try await server.listSkills(skillID: "repo.helper")

        #expect(pending.installation?.scope == .workspace)
        #expect(pendingActivation.status == .pendingApproval)
        #expect(approval.metadata["skill_activation_id"] == pendingActivation.activationID)
        #expect(preApprovalStatus.projection.activeSkillIDs.isEmpty)

        let approvalResult = try await server.approveRequest(
            requestID: approval.requestID,
            approved: true,
            actorID: scope.actorID,
            responseText: "approved"
        )
        let finalStatus = try await server.listSkills(skillID: "repo.helper")
        let promptContext = try await server.activeSkillPromptContext()

        #expect(approvalResult.status == .approved)
        #expect(finalStatus.installed.count == 1)
        #expect(finalStatus.activations.last?.status == .active)
        #expect(finalStatus.projection.activeSkillIDs == ["repo.helper"])
        #expect(finalStatus.projection.shellSkills.count == 1)
        #expect(finalStatus.projection.workerTools.map(\.name) == ["review_findings"])
        #expect(promptContext["omni_skills.active_ids"] == "repo.helper")
        #expect(promptContext["omni_skills.prompt_overlay"]?.localizedStandardContains("repo helper") == true)
        #expect(promptContext["omni_skills.codergen_overlay"]?.localizedStandardContains("Prefer small") == true)
    }

    @Test
    func missionScopedProjectionStaysIsolatedWhileSystemScopeRemainsGlobal() async throws {
        let stateRoot = try makeStateRoot(prefix: "root-skill-scopes")
        let scope = SessionScope(actorID: "chief", workspaceID: "workspace-scopes", channelID: "dm-scopes")
        let server = try makeServer(stateRoot: stateRoot, scope: scope)

        let globalSkill = try writeSkillPackage(
            root: stateRoot.rootDirectory.appending(path: "global-skill", directoryHint: .isDirectory),
            manifest: OmniSkillManifest(
                skillID: "global.helper",
                version: "1.0.0",
                displayName: "Global Helper",
                summary: "Always-available low privilege skill.",
                projectionSurfaces: [.rootPrompt],
                requiredCapabilities: []
            ),
            assets: ["prompt.md": "Global helper guidance."]
        )
        let missionSkill = try writeSkillPackage(
            root: stateRoot.rootDirectory.appending(path: "mission-skill", directoryHint: .isDirectory),
            manifest: OmniSkillManifest(
                skillID: "mission.helper",
                version: "1.0.0",
                displayName: "Mission Helper",
                summary: "Mission-scoped helper.",
                projectionSurfaces: [.rootPrompt],
                requiredCapabilities: []
            ),
            assets: ["prompt.md": "Mission helper guidance."]
        )

        _ = try await server.installSkill(from: globalSkill.path(), scope: .system)
        _ = try await server.activateSkill(
            skillID: "global.helper",
            activationScope: .system,
            approved: true
        )

        _ = try await server.installSkill(from: missionSkill.path(), scope: .workspace)
        _ = try await server.activateSkill(
            skillID: "mission.helper",
            activationScope: .mission,
            missionID: "mission-1",
            approved: true
        )

        let rootProjection = try await server.activeSkillProjection()
        let missionProjection = try await server.activeSkillProjection(missionID: "mission-1")
        let otherMissionProjection = try await server.activeSkillProjection(missionID: "mission-2")

        #expect(rootProjection.activeSkillIDs == ["global.helper"])
        #expect(missionProjection.activeSkillIDs.sorted() == ["global.helper", "mission.helper"])
        #expect(otherMissionProjection.activeSkillIDs == ["global.helper"])
    }

    private func makeServer(
        stateRoot: AgentFabricStateRoot,
        scope: SessionScope
    ) throws -> RootAgentServer {
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.deliveriesDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let skillStore = try SQLiteSkillStore(fileURL: stateRoot.skillsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let skillsRoot = stateRoot.runtimeDirectoryURL.appending(path: "skills", directoryHint: .isDirectory)
        return RootAgentServer(
            scope: scope,
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            skillStore: skillStore,
            skillsRootDirectory: skillsRoot,
            runtimeRootDirectory: stateRoot.runtimeDirectoryURL,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore,
            workingDirectory: stateRoot.rootDirectory.path()
        )
    }

    private func writeSkillPackage(
        root: URL,
        manifest: OmniSkillManifest,
        assets: [String: String]
    ) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: root.appending(path: "omniskill.json"))
        for (relativePath, contents) in assets {
            let assetURL = root.appending(path: relativePath)
            try FileManager.default.createDirectory(at: assetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: assetURL)
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
