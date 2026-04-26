import Foundation

public protocol ScheduledPromptStore: Sendable {
    func save(_ record: ScheduledPromptRecord) async throws -> ScheduledPromptRecord
    func prompt(scheduleID: String) async throws -> ScheduledPromptRecord?
    func prompts(status: ScheduledPromptStatus?) async throws -> [ScheduledPromptRecord]
    func duePrompts(now: Date) async throws -> [ScheduledPromptRecord]
    func recordFire(scheduleID: String, firedAt: Date) async throws -> ScheduledPromptRecord?
    func recordFailure(scheduleID: String, error: String, retryAt: Date) async throws -> ScheduledPromptRecord?
    func cancel(scheduleID: String, at: Date) async throws -> ScheduledPromptRecord?
}

public actor FileScheduledPromptStore: ScheduledPromptStore {
    private struct Snapshot: Codable {
        var records: [ScheduledPromptRecord]
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func save(_ record: ScheduledPromptRecord) async throws -> ScheduledPromptRecord {
        var records = try loadRecords()
        var stored = record
        stored.updatedAt = Date()
        if let index = records.firstIndex(where: { $0.scheduleID == stored.scheduleID }) {
            records[index] = stored
        } else {
            records.append(stored)
        }
        try persist(records)
        return stored
    }

    public func prompt(scheduleID: String) async throws -> ScheduledPromptRecord? {
        try loadRecords().first { $0.scheduleID == scheduleID }
    }

    public func prompts(status: ScheduledPromptStatus? = nil) async throws -> [ScheduledPromptRecord] {
        let records = try loadRecords()
        guard let status else {
            return records.sorted(by: sortRecords)
        }
        return records.filter { $0.status == status }.sorted(by: sortRecords)
    }

    public func duePrompts(now: Date = Date()) async throws -> [ScheduledPromptRecord] {
        try loadRecords()
            .filter { record in
                guard record.status == .active, let nextFireAt = record.nextFireAt else {
                    return false
                }
                return nextFireAt <= now
            }
            .sorted(by: sortRecords)
    }

    public func recordFire(scheduleID: String, firedAt: Date = Date()) async throws -> ScheduledPromptRecord? {
        var records = try loadRecords()
        guard let index = records.firstIndex(where: { $0.scheduleID == scheduleID }) else {
            return nil
        }
        var record = records[index]
        record.lastFiredAt = firedAt
        record.fireCount += 1
        record.updatedAt = firedAt
        switch record.recurrence {
        case .none:
            record.status = .completed
            record.nextFireAt = nil
        default:
            record.nextFireAt = nextFireDate(after: firedAt, recurrence: record.recurrence, timezoneIdentifier: record.timezoneIdentifier)
        }
        records[index] = record
        try persist(records)
        return record
    }

    public func recordFailure(scheduleID: String, error: String, retryAt: Date) async throws -> ScheduledPromptRecord? {
        var records = try loadRecords()
        guard let index = records.firstIndex(where: { $0.scheduleID == scheduleID }) else {
            return nil
        }
        var record = records[index]
        record.metadata["last_error"] = error
        record.nextFireAt = retryAt
        record.updatedAt = Date()
        records[index] = record
        try persist(records)
        return record
    }

    public func cancel(scheduleID: String, at: Date = Date()) async throws -> ScheduledPromptRecord? {
        var records = try loadRecords()
        guard let index = records.firstIndex(where: { $0.scheduleID == scheduleID }) else {
            return nil
        }
        var record = records[index]
        record.status = .cancelled
        record.nextFireAt = nil
        record.updatedAt = at
        records[index] = record
        try persist(records)
        return record
    }

    private func loadRecords() throws -> [ScheduledPromptRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return []
        }
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        return snapshot.records
    }

    private func persist(_ records: [ScheduledPromptRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let snapshot = Snapshot(records: records.sorted(by: sortRecords))
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func sortRecords(lhs: ScheduledPromptRecord, rhs: ScheduledPromptRecord) -> Bool {
        switch (lhs.nextFireAt, rhs.nextFireAt) {
        case let (lhsDate?, rhsDate?):
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func nextFireDate(
        after firedAt: Date,
        recurrence: ScheduledPromptRecurrence,
        timezoneIdentifier: String
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current

        switch recurrence {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: firedAt)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: firedAt)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: firedAt)
        case .weekdays:
            var candidate = calendar.date(byAdding: .day, value: 1, to: firedAt)
            while let date = candidate {
                let weekday = calendar.component(.weekday, from: date)
                if weekday != 1 && weekday != 7 {
                    return date
                }
                candidate = calendar.date(byAdding: .day, value: 1, to: date)
            }
            return nil
        }
    }
}
