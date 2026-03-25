import Foundation
import Testing
@testable import TheAgentControlPlaneKit

@Suite
struct ModelRouterTests {
    @Test
    func routerUsesVisionForAttachmentsAndCodergenForCodingWork() async {
        let router = ModelRouter()

        let visionDecision = await router.route(
            for: ModelRoutingRequest(hasAttachments: true)
        )
        let codingDecision = await router.route(
            for: ModelRoutingRequest(requiresCoding: true, budgetUnits: 3)
        )

        #expect(visionDecision.tier == .vision)
        #expect(codingDecision.tier == .codergen)
        #expect(codingDecision.metadata["model_route_model"] == "gpt-5.3-codex")
    }
}
