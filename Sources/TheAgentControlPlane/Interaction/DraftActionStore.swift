import Foundation
import OmniAICore

public enum DraftActionStatus: String, Codable, Sendable, CaseIterable {
    case pendingConfirmation = "pending_confirmation"
    case executed
    case cancelled
    case failed
}

public struct DraftActionRecord: Codable, Sendable, Equatable {
    public var draftID: String
    public var sourceSessionID: String
    public var title: String
    public var draftBody: String
    public var actionKind: String
    public var actionType: String?
    public var targetDescription: String?
    public var payload: JSONValue?
    public var status: DraftActionStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var executedAt: Date?
    public var cancelledAt: Date?
    public var failureReason: String?
    public var executionResult: JSONValue?
    public var channelTransport: String?
    public var channelTargetExternalID: String?
    public var actorExternalID: String?
}

public actor DraftActionStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func create(
        sourceSessionID: String,
        title: String,
        draftBody: String,
        actionKind: String,
        actionType: String?,
        targetDescription: String?,
        payload: JSONValue?,
        channelTransport: String?,
        channelTargetExternalID: String?,
        actorExternalID: String?
    ) throws -> DraftActionRecord {
        var records = try load()
        let now = Date()
        let record = DraftActionRecord(
            draftID: "draft.\(UUID().uuidString)",
            sourceSessionID: sourceSessionID,
            title: title,
            draftBody: draftBody,
            actionKind: actionKind,
            actionType: actionType?.nilIfBlank,
            targetDescription: targetDescription?.nilIfBlank,
            payload: payload,
            status: .pendingConfirmation,
            createdAt: now,
            updatedAt: now,
            executedAt: nil,
            cancelledAt: nil,
            failureReason: nil,
            executionResult: nil,
            channelTransport: channelTransport?.nilIfBlank,
            channelTargetExternalID: channelTargetExternalID?.nilIfBlank,
            actorExternalID: actorExternalID?.nilIfBlank
        )
        records.append(record)
        try save(records)
        return record
    }

    public func list(status: DraftActionStatus? = nil, limit: Int = 20) throws -> [DraftActionRecord] {
        let maxRecords = max(1, min(limit, 100))
        let records = try load()
            .filter { status == nil || $0.status == status }
            .sorted { $0.createdAt > $1.createdAt }
        return Array(records.prefix(maxRecords))
    }

    public func get(_ draftID: String) throws -> DraftActionRecord? {
        try load().first { $0.draftID == draftID }
    }

    @discardableResult
    public func cancel(_ draftID: String) throws -> DraftActionRecord? {
        try update(draftID) { record in
            guard record.status == .pendingConfirmation else {
                return record
            }
            let now = Date()
            record.status = .cancelled
            record.cancelledAt = now
            record.updatedAt = now
            return record
        }
    }

    @discardableResult
    public func markExecuted(_ draftID: String, result: JSONValue?) throws -> DraftActionRecord? {
        try update(draftID) { record in
            let now = Date()
            record.status = .executed
            record.executedAt = now
            record.updatedAt = now
            record.failureReason = nil
            record.executionResult = result
            return record
        }
    }

    @discardableResult
    public func recordFailure(_ draftID: String, reason: String) throws -> DraftActionRecord? {
        try update(draftID) { record in
            let now = Date()
            record.failureReason = reason
            record.updatedAt = now
            return record
        }
    }

    public func promptContext(limit: Int = 6) throws -> String? {
        let pending = try list(status: .pendingConfirmation, limit: limit)
        guard !pending.isEmpty else {
            return nil
        }
        let lines = pending.map { record in
            let type = record.actionType?.nilIfBlank ?? record.actionKind
            let target = record.targetDescription?.nilIfBlank.map { " -> \($0)" } ?? ""
            return "- [\(record.draftID)] \(record.title) (\(type))\(target)"
        }
        return """
        Pending draft actions awaiting user confirmation:
        \(lines.joined(separator: "\n"))
        """
    }

    private func update(
        _ draftID: String,
        transform: (inout DraftActionRecord) -> DraftActionRecord
    ) throws -> DraftActionRecord? {
        var records = try load()
        guard let index = records.firstIndex(where: { $0.draftID == draftID }) else {
            return nil
        }
        var record = records[index]
        record = transform(&record)
        records[index] = record
        try save(records)
        return record
    }

    private func load() throws -> [DraftActionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([DraftActionRecord].self, from: data)
    }

    private func save(_ records: [DraftActionRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
