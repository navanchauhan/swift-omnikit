import Foundation

public struct ReleaseBundleArtifact: Codable, Sendable, Equatable {
    public var artifactID: String
    public var name: String
    public var contentType: String
    public var byteCount: Int
    public var contentHash: String

    public init(
        artifactID: String,
        name: String,
        contentType: String,
        byteCount: Int,
        contentHash: String
    ) {
        self.artifactID = artifactID
        self.name = name
        self.contentType = contentType
        self.byteCount = max(0, byteCount)
        self.contentHash = contentHash
    }
}

public struct ReleaseBundle: Codable, Sendable, Equatable {
    public var bundleID: String
    public var changeID: String
    public var rootSessionID: String
    public var service: String
    public var targetEnvironment: String
    public var version: String
    public var commitish: String?
    public var artifactRefs: [ReleaseBundleArtifact]
    public var healthPlan: [String]
    public var rollbackEligible: Bool
    public var metadata: [String: String]
    public var createdAt: Date

    public init(
        bundleID: String = UUID().uuidString,
        changeID: String,
        rootSessionID: String,
        service: String,
        targetEnvironment: String,
        version: String,
        commitish: String? = nil,
        artifactRefs: [ReleaseBundleArtifact],
        healthPlan: [String] = [],
        rollbackEligible: Bool = true,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.bundleID = bundleID
        self.changeID = changeID
        self.rootSessionID = rootSessionID
        self.service = service
        self.targetEnvironment = targetEnvironment
        self.version = version
        self.commitish = commitish
        self.artifactRefs = artifactRefs
        self.healthPlan = healthPlan
        self.rollbackEligible = rollbackEligible
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public enum ReleaseBundleHash {
    public static func hash(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
