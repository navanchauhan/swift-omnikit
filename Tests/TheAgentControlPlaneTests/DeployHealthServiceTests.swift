import Foundation
import Testing
import OmniAgentDeliveryCore
import OmniAgentMesh

@Suite
struct DeployHealthServiceTests {
    @Test
    func healthServicePreservesOutcomeAndTimeoutMetadata() async throws {
        let service = DeployHealthService(
            warmupTimeout: 15,
            steadyStateTimeout: 90
        ) { release in
            DeployHealthOutcome(
                status: release.version == "good" ? .healthy : .inconclusive,
                summary: "checked \(release.version)"
            )
        }

        let healthy = await service.evaluateCanary(
            DeploymentRecord(version: "good", state: .prepared)
        )
        let inconclusive = await service.evaluateCanary(
            DeploymentRecord(version: "unknown", state: .prepared)
        )

        #expect(healthy.status == .healthy)
        #expect(healthy.metadata["warmup_timeout_seconds"] == "15")
        #expect(healthy.metadata["steady_state_timeout_seconds"] == "90")
        #expect(inconclusive.status == .inconclusive)
    }
}
