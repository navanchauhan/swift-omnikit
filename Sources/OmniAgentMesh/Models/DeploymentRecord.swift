import Foundation

public struct DeploymentRecord: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case prepared
        case canary
        case live
        case draining
        case rollbackReady = "rollback_ready"
        case rolledBack = "rolled_back"
        case failed
    }

    public enum DeliveryMode: String, Codable, Sendable {
        case deployable
        case artifactOnly = "artifact_only"
        case blockedForTargeting = "blocked_for_targeting"
    }

    public enum Slot: String, Codable, Sendable {
        case active
        case next
        case canary
    }

    public enum HealthStatus: String, Codable, Sendable {
        case pending
        case healthy
        case unhealthy
        case inconclusive
    }

    public var releaseID: String
    public var releaseBundleID: String?
    public var version: String
    public var service: String?
    public var targetEnvironment: String?
    public var state: State
    public var deliveryMode: DeliveryMode
    public var slot: Slot?
    public var healthStatus: HealthStatus
    public var generation: Int
    public var rollbackTargetReleaseID: String?
    public var rollbackReason: String?
    public var drainingTaskIDs: [String]
    public var checkpointDirectory: String?
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        releaseID: String = UUID().uuidString,
        releaseBundleID: String? = nil,
        version: String,
        service: String? = nil,
        targetEnvironment: String? = nil,
        state: State,
        deliveryMode: DeliveryMode = .deployable,
        slot: Slot? = nil,
        healthStatus: HealthStatus = .pending,
        generation: Int = 0,
        rollbackTargetReleaseID: String? = nil,
        rollbackReason: String? = nil,
        drainingTaskIDs: [String] = [],
        checkpointDirectory: String? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.releaseID = releaseID
        self.releaseBundleID = releaseBundleID
        self.version = version
        self.service = service
        self.targetEnvironment = targetEnvironment
        self.state = state
        self.deliveryMode = deliveryMode
        self.slot = slot
        self.healthStatus = healthStatus
        self.generation = max(0, generation)
        self.rollbackTargetReleaseID = rollbackTargetReleaseID
        self.rollbackReason = rollbackReason
        self.drainingTaskIDs = drainingTaskIDs
        self.checkpointDirectory = checkpointDirectory
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case releaseID
        case releaseBundleID
        case version
        case service
        case targetEnvironment
        case state
        case deliveryMode
        case slot
        case healthStatus
        case generation
        case rollbackTargetReleaseID
        case rollbackReason
        case drainingTaskIDs
        case checkpointDirectory
        case metadata
        case createdAt
        case updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.releaseID = try container.decode(String.self, forKey: .releaseID)
        self.releaseBundleID = try container.decodeIfPresent(String.self, forKey: .releaseBundleID)
        self.version = try container.decode(String.self, forKey: .version)
        self.service = try container.decodeIfPresent(String.self, forKey: .service)
        self.targetEnvironment = try container.decodeIfPresent(String.self, forKey: .targetEnvironment)
        self.state = try container.decode(State.self, forKey: .state)
        self.deliveryMode = try container.decodeIfPresent(DeliveryMode.self, forKey: .deliveryMode) ?? .deployable
        self.slot = try container.decodeIfPresent(Slot.self, forKey: .slot)
        self.healthStatus = try container.decodeIfPresent(HealthStatus.self, forKey: .healthStatus) ?? .pending
        self.generation = try container.decodeIfPresent(Int.self, forKey: .generation) ?? 0
        self.rollbackTargetReleaseID = try container.decodeIfPresent(String.self, forKey: .rollbackTargetReleaseID)
        self.rollbackReason = try container.decodeIfPresent(String.self, forKey: .rollbackReason)
        self.drainingTaskIDs = try container.decodeIfPresent([String].self, forKey: .drainingTaskIDs) ?? []
        self.checkpointDirectory = try container.decodeIfPresent(String.self, forKey: .checkpointDirectory)
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(releaseID, forKey: .releaseID)
        try container.encodeIfPresent(releaseBundleID, forKey: .releaseBundleID)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(service, forKey: .service)
        try container.encodeIfPresent(targetEnvironment, forKey: .targetEnvironment)
        try container.encode(state, forKey: .state)
        try container.encode(deliveryMode, forKey: .deliveryMode)
        try container.encodeIfPresent(slot, forKey: .slot)
        try container.encode(healthStatus, forKey: .healthStatus)
        try container.encode(generation, forKey: .generation)
        try container.encodeIfPresent(rollbackTargetReleaseID, forKey: .rollbackTargetReleaseID)
        try container.encodeIfPresent(rollbackReason, forKey: .rollbackReason)
        try container.encode(drainingTaskIDs, forKey: .drainingTaskIDs)
        try container.encodeIfPresent(checkpointDirectory, forKey: .checkpointDirectory)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
