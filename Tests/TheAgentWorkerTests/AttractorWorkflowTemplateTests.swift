import Foundation
import Testing
import OmniAgentMesh
@testable import TheAgentWorkerKit

@Suite
struct AttractorWorkflowTemplateTests {
    @Test
    func dotIncludesRetryBudgetAndStructuredStatusContract() {
        let template = AttractorWorkflowTemplate(provider: "openai", model: "gpt-test", reasoningEffort: "high")
        let task = TaskRecord(
            rootSessionID: SessionScope(
                actorID: ActorID(rawValue: "chief"),
                workspaceID: WorkspaceID(rawValue: "workspace-template"),
                channelID: ChannelID(rawValue: "dm-template")
            ).sessionID,
            missionID: "mission-template",
            historyProjection: HistoryProjection(
                taskBrief: "prove the tpu worker is real",
                constraints: ["repo", "tpu"],
                expectedOutputs: ["tpu-worker-proof.md"]
            )
        )

        let dot = template.dot(for: task)

        #expect(dot.contains("default_max_retry=2"))
        #expect(dot.contains("Implement or execute the task for real."))
        #expect(dot.contains("end with a fenced ```json status block"))
        #expect(dot.contains("return outcome \\\"retry\\\" or \\\"fail\\\""))
    }
}
