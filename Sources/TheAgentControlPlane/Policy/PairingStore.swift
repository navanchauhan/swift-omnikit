import Foundation
import OmniAgentMesh

public struct PairingRecord: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case pending
        case claimed
        case expired
    }

    public var pairingID: String
    public var code: String
    public var transport: ChannelBinding.Transport
    public var actorExternalID: String
    public var workspaceID: WorkspaceID?
    public var status: Status
    public var createdAt: Date
    public var expiresAt: Date
    public var claimedActorID: ActorID?
    public var claimedAt: Date?

    public init(
        pairingID: String = UUID().uuidString,
        code: String,
        transport: ChannelBinding.Transport,
        actorExternalID: String,
        workspaceID: WorkspaceID? = nil,
        status: Status = .pending,
        createdAt: Date = Date(),
        expiresAt: Date,
        claimedActorID: ActorID? = nil,
        claimedAt: Date? = nil
    ) {
        self.pairingID = pairingID
        self.code = code
        self.transport = transport
        self.actorExternalID = actorExternalID
        self.workspaceID = workspaceID
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.claimedActorID = claimedActorID
        self.claimedAt = claimedAt
    }
}

public actor PairingStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var recordsByCode: [String: PairingRecord] = [:]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.recordsByCode = (try? Self.loadRecords(from: fileURL, decoder: decoder)) ?? [:]
    }

    public func issueCode(
        transport: ChannelBinding.Transport,
        actorExternalID: String,
        workspaceID: WorkspaceID? = nil,
        ttl: TimeInterval = 900,
        now: Date = Date()
    ) async throws -> PairingRecord {
        if let existing = activeRecord(transport: transport, actorExternalID: actorExternalID, now: now) {
            return existing
        }
        let record = PairingRecord(
            code: Self.randomCode(),
            transport: transport,
            actorExternalID: actorExternalID,
            workspaceID: workspaceID,
            createdAt: now,
            expiresAt: now.addingTimeInterval(ttl)
        )
        recordsByCode[record.code] = record
        try persist()
        return record
    }

    public func activeRecord(
        transport: ChannelBinding.Transport,
        actorExternalID: String,
        now: Date = Date()
    ) -> PairingRecord? {
        recordsByCode.values.first { record in
            record.transport == transport &&
            record.actorExternalID == actorExternalID &&
            record.status == .pending &&
            record.expiresAt > now
        }
    }

    public func claim(code: String, actorID: ActorID, now: Date = Date()) async throws -> PairingRecord? {
        guard var record = recordsByCode[code] else {
            return nil
        }
        guard record.status == .pending, record.expiresAt > now else {
            record.status = .expired
            recordsByCode[code] = record
            try persist()
            return nil
        }
        record.status = .claimed
        record.claimedActorID = actorID
        record.claimedAt = now
        recordsByCode[code] = record
        try persist()
        return record
    }

    public func pendingRecords(now: Date = Date()) async -> [PairingRecord] {
        recordsByCode.values
            .map { record in
                guard record.status == .pending, record.expiresAt <= now else {
                    return record
                }
                var expired = record
                expired.status = .expired
                return expired
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func persist() throws {
        let data = try encoder.encode(recordsByCode)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func loadRecords(
        from fileURL: URL,
        decoder: JSONDecoder
    ) throws -> [String: PairingRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([String: PairingRecord].self, from: data)
    }

    private static func randomCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement() ?? "A" })
    }
}
