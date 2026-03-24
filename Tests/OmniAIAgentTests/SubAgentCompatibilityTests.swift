import Testing
@testable import OmniAIAgent

@Suite
struct SubAgentCompatibilityTests {
    @Test
    func lineageAndArtifactDefaultsRemainOptional() {
        let lineage = SubAgentLineage(taskID: "task-1", parentTaskID: "parent-1", historyProjectionSummary: "focused brief")
        let result = SubAgentResult(output: "done", success: true, turnsUsed: 3, taskID: "task-1", artifactRefs: ["artifact-1"])

        #expect(lineage.taskID == "task-1")
        #expect(lineage.parentTaskID == "parent-1")
        #expect(result.taskID == "task-1")
        #expect(result.artifactRefs == ["artifact-1"])
    }

    @Test
    func worktreeIsolationEncodesIntent() {
        let inherited = WorktreeIsolation.inherited
        let dedicated = WorktreeIsolation.dedicated(path: "/tmp/worktree")
        let ephemeral = WorktreeIsolation.ephemeral(parentPath: "/tmp/project")

        #expect(inherited == .inherited)
        #expect(dedicated == .dedicated(path: "/tmp/worktree"))
        #expect(ephemeral == .ephemeral(parentPath: "/tmp/project"))
    }
}
