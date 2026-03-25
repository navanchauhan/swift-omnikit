import Foundation
import Testing
import OmniAIAttractor

@Suite
struct OmniSkillCodergenBridgeTests {
    @Test
    func codergenHandlerInjectsOmniSkillOverlaysAndRouteMetadata() async throws {
        let logsRoot = try makeDirectory(prefix: "skill-codergen-bridge")
        let backend = RecordingCodergenBackend(
            results: [
                CodergenResult(
                    response: "Codergen bridge succeeded.",
                    status: .success,
                    contextUpdates: ["bridge": "ok"]
                ),
            ]
        )
        let handler = CodergenHandler(backend: backend)
        let node = Node(
            id: "implement",
            label: "Implement",
            prompt: "Implement the requested change.",
            reasoningEffort: ""
        )
        let context = PipelineContext([
            "task.active_skill_ids": "repo.helper",
            "task.skill_prompt_overlay": "Follow repository conventions before editing.",
            "task.skill_codergen_overlay": "Prefer small, reviewable patches.",
            "task.model_route_tier": "codergen",
            "task.model_route_provider": "openai",
            "task.model_route_model": "gpt-5.4",
            "task.model_route_reasoning_effort": "xhigh",
        ])

        let outcome = try await handler.execute(
            node: node,
            context: context,
            graph: Graph(id: "skill-bridge"),
            logsRoot: logsRoot
        )
        let call = try #require(await backend.calls().first)

        #expect(outcome.status == .success)
        #expect(outcome.contextUpdates["bridge"] == "ok")
        #expect(call.prompt.localizedStandardContains("Active skills: repo.helper"))
        #expect(call.prompt.localizedStandardContains("Follow repository conventions"))
        #expect(call.prompt.localizedStandardContains("Prefer small, reviewable patches"))
        #expect(call.prompt.localizedStandardContains("Model route tier: codergen"))
        #expect(call.model == "gpt-5.4")
        #expect(call.provider == "openai")
        #expect(call.reasoningEffort == "xhigh")
        #expect(call.contextSnapshot["task.skill_prompt_overlay"] == "Follow repository conventions before editing.")
        #expect(call.contextSnapshot["task.skill_codergen_overlay"] == "Prefer small, reviewable patches.")
    }

    private func makeDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
