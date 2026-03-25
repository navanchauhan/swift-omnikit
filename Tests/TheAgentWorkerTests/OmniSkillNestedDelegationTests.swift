import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentWorkerKit

@Suite
struct OmniSkillNestedDelegationTests {
    @Test
    func childDelegationPreservesOmniSkillAndRouteMetadata() async throws {
        let stateRoot = try makeStateRoot(prefix: "skill-nested-delegation")
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let rawWorkerTools = #" [{"skill_id":"repo.helper","name":"review_findings","description":"Return findings","instruction":"List blockers first."}] "#
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parentTask = TaskRecord(
            taskID: "parent-skill-task",
            rootSessionID: "root",
            missionID: "mission-42",
            historyProjection: HistoryProjection(
                taskBrief: "Parent task",
                constraints: [
                    "max_recursion_depth=2",
                    "budget_units_remaining=4",
                ]
            ),
            metadata: [
                "omni_skills.active_ids": "repo.helper",
                "omni_skills.prompt_overlay": "Use repo helper guidance.",
                "omni_skills.codergen_overlay": "Prefer safe patches.",
                "omni_skills.worker_tools_json": rawWorkerTools,
                "model_route_tier": "implementer",
                "model_route_provider": "openai",
                "model_route_model": "gpt-5.4",
            ],
            status: .running,
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 500)
        )
        _ = try await jobStore.createTask(parentTask, idempotencyKey: "task.submitted.parent-skill-task")

        let manager = ChildWorkerManager(jobStore: jobStore)
        let childTask = try await manager.spawnChildTask(
            parentTaskID: parentTask.taskID,
            request: ChildTaskRequest(
                brief: "Inspect the delegated skill context.",
                capabilityRequirements: ["review"],
                expectedOutputs: ["review.txt"]
            ),
            createdAt: Date(timeIntervalSince1970: 501)
        )

        #expect(childTask.parentTaskID == parentTask.taskID)
        #expect(childTask.missionID == "mission-42")
        #expect(childTask.metadata["omni_skills.active_ids"] == "repo.helper")
        #expect(childTask.metadata["omni_skills.prompt_overlay"] == "Use repo helper guidance.")
        #expect(childTask.metadata["omni_skills.codergen_overlay"] == "Prefer safe patches.")
        #expect(childTask.metadata["omni_skills.worker_tools_json"] == rawWorkerTools)
        #expect(childTask.metadata["model_route_tier"] == "implementer")
        #expect(childTask.metadata["model_route_model"] == "gpt-5.4")
        #expect(childTask.historyProjection.constraints.contains("delegation_depth=1"))
        #expect(childTask.historyProjection.constraints.contains("mission_id=mission-42"))
        #expect(childTask.historyProjection.constraints.contains("budget_units_remaining=3"))
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
