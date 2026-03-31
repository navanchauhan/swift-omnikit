import Foundation
import OmniAgentMesh

public enum ReleaseControllerError: Error, Sendable, Equatable {
    case releaseNotFound(String)
}

public struct ReleaseDeploymentResult: Sendable, Equatable {
    public var releaseID: String
    public var state: DeploymentRecord.State
    public var healthStatus: DeploymentRecord.HealthStatus
    public var deployed: Bool
    public var rolledBackToReleaseID: String?
    public var summary: String
    public var attempts: Int

    public init(
        releaseID: String,
        state: DeploymentRecord.State,
        healthStatus: DeploymentRecord.HealthStatus,
        deployed: Bool,
        rolledBackToReleaseID: String? = nil,
        summary: String,
        attempts: Int
    ) {
        self.releaseID = releaseID
        self.state = state
        self.healthStatus = healthStatus
        self.deployed = deployed
        self.rolledBackToReleaseID = rolledBackToReleaseID
        self.summary = summary
        self.attempts = attempts
    }
}

public actor ReleaseController {
    private let deploymentStore: any DeploymentStore
    private let supervisor: Supervisor
    private let slotController: SlotController
    private let healthService: DeployHealthService?

    public init(
        deploymentStore: any DeploymentStore,
        supervisor: Supervisor,
        slotController: SlotController? = nil,
        healthService: DeployHealthService? = nil
    ) {
        self.deploymentStore = deploymentStore
        self.supervisor = supervisor
        self.slotController = slotController ?? SlotController(
            rootDirectory: supervisor.releasesDirectoryURL?.appending(path: "slots", directoryHint: .isDirectory)
        )
        self.healthService = healthService
    }

    public func prepareRelease(
        version: String,
        releaseBundleID: String? = nil,
        service: String = "default",
        targetEnvironment: String? = nil,
        deliveryMode: DeploymentRecord.DeliveryMode = .deployable,
        autoRolloutEligible: Bool = true,
        drainingTaskIDs: [String] = [],
        checkpointDirectory: String? = nil,
        metadata: [String: String] = [:],
        now: Date = Date()
    ) async throws -> DeploymentRecord {
        let generation = ((try await deploymentStore.activeRelease()?.generation) ?? -1) + 1
        var release = DeploymentRecord(
            version: version,
            service: service,
            targetEnvironment: targetEnvironment,
            state: .prepared,
            deliveryMode: deliveryMode,
            slot: .next,
            healthStatus: .pending,
            generation: generation,
            drainingTaskIDs: drainingTaskIDs,
            checkpointDirectory: checkpointDirectory,
            metadata: metadata.merging([
                "auto_rollout_eligible": String(autoRolloutEligible),
            ]) { _, new in new },
            createdAt: now,
            updatedAt: now
        )
        release.releaseBundleID = releaseBundleID
        release = try await slotController.prepare(release, now: now)
        try await deploymentStore.saveRelease(release, makeActive: false)
        return release
    }

    public func deployCanary(
        releaseID: String,
        maxAttempts: Int = 1,
        now: Date = Date()
    ) async throws -> ReleaseDeploymentResult {
        guard var candidate = try await deploymentStore.release(releaseID: releaseID) else {
            throw ReleaseControllerError.releaseNotFound(releaseID)
        }
        let previousActive = try await deploymentStore.activeRelease()
        var attempts = 0

        while attempts < max(1, maxAttempts) {
            attempts += 1
            candidate = try await slotController.beginCanary(candidate, now: now)
            try await deploymentStore.saveRelease(candidate, makeActive: false)
            try await supervisor.install(candidate)
            try await supervisor.activate(releaseID: candidate.releaseID)

            let outcome = await evaluateHealth(for: candidate)
            candidate.healthStatus = outcome.status
            candidate.updatedAt = now
            candidate.metadata.merge(outcome.metadata) { _, new in new }
            candidate.metadata["health_summary"] = outcome.summary

            if outcome.status == .healthy {
                candidate = try await slotController.promote(candidate, now: now)
                candidate.healthStatus = .healthy
                try await deploymentStore.saveRelease(candidate, makeActive: true)
                return ReleaseDeploymentResult(
                    releaseID: candidate.releaseID,
                    state: candidate.state,
                    healthStatus: candidate.healthStatus,
                    deployed: true,
                    summary: outcome.summary,
                    attempts: attempts
                )
            }
        }

        let failureSummary = candidate.metadata["health_summary"] ?? "Canary health verification failed."
        candidate = try await slotController.fail(candidate, reason: failureSummary, now: now)
        try await deploymentStore.saveRelease(candidate, makeActive: false)

        if let previousActive {
            var rolledBack = try await slotController.rollback(
                failedRelease: candidate,
                targetReleaseID: previousActive.releaseID,
                reason: failureSummary,
                now: now
            )
            rolledBack.healthStatus = candidate.healthStatus
            rolledBack.metadata["rollback_to_release_id"] = previousActive.releaseID
            try await deploymentStore.saveRelease(rolledBack, makeActive: false)
            try await supervisor.rollback(to: previousActive.releaseID)
            try await deploymentStore.markActiveRelease(previousActive.releaseID)
            return ReleaseDeploymentResult(
                releaseID: candidate.releaseID,
                state: rolledBack.state,
                healthStatus: rolledBack.healthStatus,
                deployed: false,
                rolledBackToReleaseID: previousActive.releaseID,
                summary: failureSummary,
                attempts: attempts
            )
        }

        return ReleaseDeploymentResult(
            releaseID: candidate.releaseID,
            state: candidate.state,
            healthStatus: candidate.healthStatus,
            deployed: false,
            summary: failureSummary,
            attempts: attempts
        )
    }

    private func evaluateHealth(for release: DeploymentRecord) async -> DeployHealthOutcome {
        if let healthService {
            return await healthService.evaluateCanary(release)
        }
        let healthy = await supervisor.checkHealth(of: release)
        return DeployHealthOutcome(
            status: healthy ? .healthy : .unhealthy,
            summary: healthy ? "Supervisor health check passed." : "Supervisor health check failed."
        )
    }
}
