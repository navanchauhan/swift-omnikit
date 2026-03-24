import Foundation
import OmniAgentMesh

public enum ReleaseControllerError: Error, Sendable, Equatable {
    case releaseNotFound(String)
}

public struct ReleaseDeploymentResult: Sendable, Equatable {
    public var releaseID: String
    public var deployed: Bool
    public var rolledBackToReleaseID: String?
    public var attempts: Int

    public init(
        releaseID: String,
        deployed: Bool,
        rolledBackToReleaseID: String? = nil,
        attempts: Int
    ) {
        self.releaseID = releaseID
        self.deployed = deployed
        self.rolledBackToReleaseID = rolledBackToReleaseID
        self.attempts = attempts
    }
}

public actor ReleaseController {
    private let deploymentStore: any DeploymentStore
    private let supervisor: Supervisor

    public init(
        deploymentStore: any DeploymentStore,
        supervisor: Supervisor
    ) {
        self.deploymentStore = deploymentStore
        self.supervisor = supervisor
    }

    public func prepareRelease(
        version: String,
        drainingTaskIDs: [String] = [],
        checkpointDirectory: String? = nil,
        metadata: [String: String] = [:],
        now: Date = Date()
    ) async throws -> DeploymentRecord {
        let release = DeploymentRecord(
            version: version,
            state: .prepared,
            drainingTaskIDs: drainingTaskIDs,
            checkpointDirectory: checkpointDirectory,
            metadata: metadata,
            createdAt: now,
            updatedAt: now
        )
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
            candidate.state = .draining
            candidate.updatedAt = now
            try await deploymentStore.saveRelease(candidate, makeActive: false)
            try await supervisor.install(candidate)
            try await supervisor.activate(releaseID: candidate.releaseID)

            if await supervisor.checkHealth(of: candidate) {
                candidate.state = .live
                candidate.updatedAt = now
                try await deploymentStore.saveRelease(candidate, makeActive: true)
                return ReleaseDeploymentResult(
                    releaseID: candidate.releaseID,
                    deployed: true,
                    attempts: attempts
                )
            }
        }

        candidate.state = .failed
        candidate.updatedAt = now
        try await deploymentStore.saveRelease(candidate, makeActive: false)

        if let previousActive {
            var rolledBack = candidate
            rolledBack.state = .rolledBack
            rolledBack.updatedAt = now
            rolledBack.metadata["rollback_to_release_id"] = previousActive.releaseID
            try await deploymentStore.saveRelease(rolledBack, makeActive: false)
            try await supervisor.rollback(to: previousActive.releaseID)
            try await deploymentStore.markActiveRelease(previousActive.releaseID)
            return ReleaseDeploymentResult(
                releaseID: candidate.releaseID,
                deployed: false,
                rolledBackToReleaseID: previousActive.releaseID,
                attempts: attempts
            )
        }

        return ReleaseDeploymentResult(
            releaseID: candidate.releaseID,
            deployed: false,
            attempts: attempts
        )
    }
}
