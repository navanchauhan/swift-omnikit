import Foundation
import OmniAgentMesh

public struct SlotSnapshot: Codable, Sendable, Equatable {
    public var service: String
    public var targetEnvironment: String
    public var activeReleaseID: String?
    public var nextReleaseID: String?
    public var canaryReleaseID: String?
    public var updatedAt: Date

    public init(
        service: String,
        targetEnvironment: String,
        activeReleaseID: String? = nil,
        nextReleaseID: String? = nil,
        canaryReleaseID: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.service = service
        self.targetEnvironment = targetEnvironment
        self.activeReleaseID = activeReleaseID
        self.nextReleaseID = nextReleaseID
        self.canaryReleaseID = canaryReleaseID
        self.updatedAt = updatedAt
    }
}

public actor SlotController: DeploymentDriver {
    private let rootDirectory: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var snapshots: [String: SlotSnapshot] = [:]

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func snapshot(service: String, targetEnvironment: String) async throws -> SlotSnapshot {
        let key = slotKey(service: service, targetEnvironment: targetEnvironment)
        if let snapshot = snapshots[key] {
            return snapshot
        }
        if let stored = try loadSnapshot(key: key) {
            snapshots[key] = stored
            return stored
        }
        let fresh = SlotSnapshot(service: service, targetEnvironment: targetEnvironment)
        snapshots[key] = fresh
        return fresh
    }

    public func prepare(_ release: DeploymentRecord, now: Date) async throws -> DeploymentRecord {
        var updated = release
        let key = slotKey(for: release)
        var slots = try await snapshot(service: release.service ?? "default", targetEnvironment: release.targetEnvironment ?? "default")
        slots.nextReleaseID = release.releaseID
        slots.updatedAt = now
        snapshots[key] = slots
        try persistSnapshot(slots, key: key)
        updated.state = .prepared
        updated.slot = .next
        updated.updatedAt = now
        return updated
    }

    public func beginCanary(_ release: DeploymentRecord, now: Date) async throws -> DeploymentRecord {
        var updated = release
        let key = slotKey(for: release)
        var slots = try await snapshot(service: release.service ?? "default", targetEnvironment: release.targetEnvironment ?? "default")
        slots.nextReleaseID = release.releaseID
        slots.canaryReleaseID = release.releaseID
        slots.updatedAt = now
        snapshots[key] = slots
        try persistSnapshot(slots, key: key)
        updated.state = .canary
        updated.slot = .canary
        updated.updatedAt = now
        return updated
    }

    public func promote(_ release: DeploymentRecord, now: Date) async throws -> DeploymentRecord {
        var updated = release
        let key = slotKey(for: release)
        var slots = try await snapshot(service: release.service ?? "default", targetEnvironment: release.targetEnvironment ?? "default")
        slots.activeReleaseID = release.releaseID
        slots.nextReleaseID = nil
        slots.canaryReleaseID = nil
        slots.updatedAt = now
        snapshots[key] = slots
        try persistSnapshot(slots, key: key)
        updated.state = .live
        updated.slot = .active
        updated.updatedAt = now
        return updated
    }

    public func fail(_ release: DeploymentRecord, reason: String?, now: Date) async throws -> DeploymentRecord {
        var updated = release
        let key = slotKey(for: release)
        var slots = try await snapshot(service: release.service ?? "default", targetEnvironment: release.targetEnvironment ?? "default")
        if slots.canaryReleaseID == release.releaseID {
            slots.canaryReleaseID = nil
        }
        if slots.nextReleaseID == release.releaseID {
            slots.nextReleaseID = nil
        }
        slots.updatedAt = now
        snapshots[key] = slots
        try persistSnapshot(slots, key: key)
        updated.state = .failed
        updated.slot = nil
        updated.rollbackReason = reason
        updated.updatedAt = now
        return updated
    }

    public func rollback(
        failedRelease: DeploymentRecord,
        targetReleaseID: String?,
        reason: String?,
        now: Date
    ) async throws -> DeploymentRecord {
        var updated = failedRelease
        let key = slotKey(for: failedRelease)
        var slots = try await snapshot(service: failedRelease.service ?? "default", targetEnvironment: failedRelease.targetEnvironment ?? "default")
        slots.activeReleaseID = targetReleaseID
        slots.nextReleaseID = nil
        slots.canaryReleaseID = nil
        slots.updatedAt = now
        snapshots[key] = slots
        try persistSnapshot(slots, key: key)
        updated.state = .rolledBack
        updated.slot = nil
        updated.rollbackTargetReleaseID = targetReleaseID
        updated.rollbackReason = reason
        updated.updatedAt = now
        return updated
    }

    private func slotKey(for release: DeploymentRecord) -> String {
        slotKey(service: release.service ?? "default", targetEnvironment: release.targetEnvironment ?? "default")
    }

    private func slotKey(service: String, targetEnvironment: String) -> String {
        "\(service)::\(targetEnvironment)"
    }

    private func persistSnapshot(_ snapshot: SlotSnapshot, key: String) throws {
        guard let rootDirectory else {
            return
        }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let fileURL = rootDirectory.appending(path: "\(key.replacing("/", with: "_")).json")
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private func loadSnapshot(key: String) throws -> SlotSnapshot? {
        guard let rootDirectory else {
            return nil
        }
        let fileURL = rootDirectory.appending(path: "\(key.replacing("/", with: "_")).json")
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(SlotSnapshot.self, from: data)
    }
}
