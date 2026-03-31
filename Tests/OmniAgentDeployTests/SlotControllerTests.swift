import Foundation
import Testing
import OmniAgentDeliveryCore
import OmniAgentMesh
@testable import OmniAgentDeployKit

@Suite
struct SlotControllerTests {
    @Test
    func slotControllerTracksCanaryPromotionAndRollback() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "slot-controller-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let controller = SlotController(rootDirectory: rootDirectory)
        let stable = DeploymentRecord(
            releaseID: "stable",
            version: "1.0.0",
            service: "the-agent",
            targetEnvironment: "prod",
            state: .live,
            slot: .active,
            healthStatus: .healthy
        )
        _ = try await controller.promote(stable, now: Date(timeIntervalSince1970: 10))

        let candidate = DeploymentRecord(
            releaseID: "candidate",
            version: "1.1.0",
            service: "the-agent",
            targetEnvironment: "prod",
            state: .prepared
        )

        let prepared = try await controller.prepare(candidate, now: Date(timeIntervalSince1970: 11))
        #expect(prepared.slot == .next)

        let canary = try await controller.beginCanary(prepared, now: Date(timeIntervalSince1970: 12))
        #expect(canary.state == .canary)
        #expect(canary.slot == .canary)

        let rollback = try await controller.rollback(
            failedRelease: canary,
            targetReleaseID: stable.releaseID,
            reason: "canary unhealthy",
            now: Date(timeIntervalSince1970: 13)
        )
        let snapshot = try await controller.snapshot(service: "the-agent", targetEnvironment: "prod")

        #expect(rollback.state == .rolledBack)
        #expect(rollback.rollbackTargetReleaseID == stable.releaseID)
        #expect(snapshot.activeReleaseID == stable.releaseID)
        #expect(snapshot.canaryReleaseID == nil)
        #expect(snapshot.nextReleaseID == nil)
    }
}
