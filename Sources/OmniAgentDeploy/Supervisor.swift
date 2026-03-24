import Foundation
import OmniAgentMesh

public struct ManagedRelease: Codable, Sendable, Equatable {
    public var releaseID: String
    public var version: String
    public var installedAt: Date
    public var metadata: [String: String]

    public init(
        releaseID: String,
        version: String,
        installedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.releaseID = releaseID
        self.version = version
        self.installedAt = installedAt
        self.metadata = metadata
    }
}

public actor Supervisor {
    public typealias HealthCheck = @Sendable (DeploymentRecord) async -> Bool

    private let releasesDirectory: URL?
    private let healthCheck: HealthCheck
    private let encoder = JSONEncoder()
    private var installedReleases: [String: ManagedRelease] = [:]
    private var activeReleaseID: String?

    public init(
        releasesDirectory: URL? = nil,
        healthCheck: @escaping HealthCheck = { _ in true }
    ) {
        self.releasesDirectory = releasesDirectory
        self.healthCheck = healthCheck
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func install(_ release: DeploymentRecord) async throws {
        let managed = ManagedRelease(
            releaseID: release.releaseID,
            version: release.version,
            metadata: release.metadata
        )
        installedReleases[release.releaseID] = managed

        guard let releasesDirectory else {
            return
        }
        let releaseDirectory = releasesDirectory.appending(path: release.releaseID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: releaseDirectory, withIntermediateDirectories: true)
        let manifestURL = releaseDirectory.appending(path: "release.json")
        try encoder.encode(managed).write(to: manifestURL, options: .atomic)
    }

    public func activate(releaseID: String) throws {
        guard installedReleases[releaseID] != nil else {
            throw SupervisorError.releaseNotInstalled(releaseID)
        }
        activeReleaseID = releaseID
    }

    public func rollback(to releaseID: String) throws {
        try activate(releaseID: releaseID)
    }

    public func checkHealth(of release: DeploymentRecord) async -> Bool {
        await healthCheck(release)
    }

    public func activeReleaseIDValue() -> String? {
        activeReleaseID
    }
}

public enum SupervisorError: Error, Sendable, Equatable {
    case releaseNotInstalled(String)
}
