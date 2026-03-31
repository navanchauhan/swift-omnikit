import Foundation
import OmniAgentMesh

public protocol DeploymentDriver: Sendable {
    func prepare(_ release: DeploymentRecord, now: Date) async throws -> DeploymentRecord
    func beginCanary(_ release: DeploymentRecord, now: Date) async throws -> DeploymentRecord
    func promote(_ release: DeploymentRecord, now: Date) async throws -> DeploymentRecord
    func fail(_ release: DeploymentRecord, reason: String?, now: Date) async throws -> DeploymentRecord
    func rollback(
        failedRelease: DeploymentRecord,
        targetReleaseID: String?,
        reason: String?,
        now: Date
    ) async throws -> DeploymentRecord
}
