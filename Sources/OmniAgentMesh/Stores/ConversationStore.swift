import Foundation

public protocol ConversationStore: Sendable {
    func appendInteraction(_ item: InteractionItem) async throws -> InteractionItem
    func interactions(sessionID: String, limit: Int?) async throws -> [InteractionItem]
    func saveSummary(_ summary: ConversationSummary) async throws
    func loadSummary(sessionID: String) async throws -> ConversationSummary?
    func saveNotification(_ notification: NotificationRecord) async throws -> NotificationRecord
    func notifications(sessionID: String, unresolvedOnly: Bool) async throws -> [NotificationRecord]
    func markNotificationDelivered(notificationID: String, at: Date) async throws -> NotificationRecord?
    func markNotificationResolved(notificationID: String, at: Date) async throws -> NotificationRecord?
}

public actor SQLiteConversationStore: ConversationStore {
    private let connection: SQLiteConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) throws {
        self.connection = try SQLiteConnection(fileURL: fileURL)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        try Self.createSchema(on: connection)
    }

    public func appendInteraction(_ item: InteractionItem) async throws -> InteractionItem {
        try connection.transaction {
            let nextSequence = Int(
                (try connection.scalarInt(
                    "SELECT COALESCE(MAX(sequence), 0) AS value FROM interactions WHERE session_id = ?;",
                    bindings: [.text(item.sessionID)]
                ) ?? 0) + 1
            )

            var stored = item
            stored.sequenceNumber = nextSequence
            try connection.execute(
                """
                INSERT INTO interactions (session_id, sequence, item_id, created_at, payload_json)
                VALUES (?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(stored.sessionID),
                    .integer(Int64(stored.sequenceNumber)),
                    .text(stored.itemID),
                    .double(stored.createdAt.timeIntervalSince1970),
                    .blob(try encoder.encode(stored)),
                ]
            )
            return stored
        }
    }

    public func interactions(sessionID: String, limit: Int? = nil) async throws -> [InteractionItem] {
        let rows: [SQLiteRow]
        if let limit {
            rows = try connection.query(
                """
                SELECT payload_json
                FROM interactions
                WHERE session_id = ?
                ORDER BY sequence DESC
                LIMIT ?;
                """,
                bindings: [.text(sessionID), .integer(Int64(limit))]
            )
        } else {
            rows = try connection.query(
                """
                SELECT payload_json
                FROM interactions
                WHERE session_id = ?
                ORDER BY sequence ASC;
                """,
                bindings: [.text(sessionID)]
            )
        }

        let decoded = try rows.compactMap(decodeInteraction)
        return limit == nil ? decoded : decoded.reversed()
    }

    public func saveSummary(_ summary: ConversationSummary) async throws {
        try connection.execute(
            """
            INSERT OR REPLACE INTO conversation_summaries (session_id, updated_at, payload_json)
            VALUES (?, ?, ?);
            """,
            bindings: [
                .text(summary.sessionID),
                .double(summary.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(summary)),
            ]
        )
    }

    public func loadSummary(sessionID: String) async throws -> ConversationSummary? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM conversation_summaries
            WHERE session_id = ?;
            """,
            bindings: [.text(sessionID)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(ConversationSummary.self, from: data)
    }

    public func saveNotification(_ notification: NotificationRecord) async throws -> NotificationRecord {
        try connection.execute(
            """
            INSERT OR REPLACE INTO notifications (notification_id, session_id, status, created_at, payload_json)
            VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(notification.notificationID),
                .text(notification.sessionID),
                .text(notification.status.rawValue),
                .double(notification.createdAt.timeIntervalSince1970),
                .blob(try encoder.encode(notification)),
            ]
        )
        return notification
    }

    public func notifications(sessionID: String, unresolvedOnly: Bool = false) async throws -> [NotificationRecord] {
        let rows: [SQLiteRow]
        if unresolvedOnly {
            rows = try connection.query(
                """
                SELECT payload_json
                FROM notifications
                WHERE session_id = ? AND status != ?
                ORDER BY created_at ASC;
                """,
                bindings: [.text(sessionID), .text(NotificationRecord.Status.resolved.rawValue)]
            )
        } else {
            rows = try connection.query(
                """
                SELECT payload_json
                FROM notifications
                WHERE session_id = ?
                ORDER BY created_at ASC;
                """,
                bindings: [.text(sessionID)]
            )
        }

        return try rows.compactMap(decodeNotification)
    }

    public func markNotificationDelivered(notificationID: String, at: Date) async throws -> NotificationRecord? {
        guard var notification = try loadNotification(notificationID: notificationID) else {
            return nil
        }
        notification.status = .delivered
        notification.deliveredAt = at
        return try await saveNotification(notification)
    }

    public func markNotificationResolved(notificationID: String, at: Date) async throws -> NotificationRecord? {
        guard var notification = try loadNotification(notificationID: notificationID) else {
            return nil
        }
        notification.status = .resolved
        notification.resolvedAt = at
        return try await saveNotification(notification)
    }

    private static func createSchema(on connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS interactions (
                session_id TEXT NOT NULL,
                sequence INTEGER NOT NULL,
                item_id TEXT PRIMARY KEY,
                created_at REAL NOT NULL,
                payload_json BLOB NOT NULL,
                UNIQUE(session_id, sequence)
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS interactions_session_sequence_idx
            ON interactions(session_id, sequence);
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS conversation_summaries (
                session_id TEXT PRIMARY KEY,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS notifications (
                notification_id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS notifications_session_status_idx
            ON notifications(session_id, status, created_at);
            """
        )
    }

    private func loadNotification(notificationID: String) throws -> NotificationRecord? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM notifications
            WHERE notification_id = ?;
            """,
            bindings: [.text(notificationID)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(NotificationRecord.self, from: data)
    }

    private func decodeInteraction(from row: SQLiteRow) throws -> InteractionItem? {
        guard let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(InteractionItem.self, from: data)
    }

    private func decodeNotification(from row: SQLiteRow) throws -> NotificationRecord? {
        guard let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(NotificationRecord.self, from: data)
    }
}
