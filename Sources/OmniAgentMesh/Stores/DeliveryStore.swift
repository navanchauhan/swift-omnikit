import Foundation

public protocol DeliveryStore: Sendable {
    func saveDelivery(_ delivery: DeliveryRecord) async throws -> DeliveryRecord
    func delivery(idempotencyKey: String) async throws -> DeliveryRecord?
    func deliveries(
        direction: DeliveryRecord.Direction?,
        sessionID: String?,
        status: DeliveryRecord.Status?
    ) async throws -> [DeliveryRecord]
}

public actor SQLiteDeliveryStore: DeliveryStore {
    private let connection: SQLiteConnection
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) throws {
        self.connection = try SQLiteConnection(fileURL: fileURL)
        try Self.createSchema(on: connection)
    }

    public func saveDelivery(_ delivery: DeliveryRecord) async throws -> DeliveryRecord {
        var stored = delivery
        stored.updatedAt = Date()
        try connection.execute(
            """
            INSERT OR REPLACE INTO deliveries (
                delivery_id,
                idempotency_key,
                direction,
                session_id,
                status,
                created_at,
                updated_at,
                payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(stored.deliveryID),
                .text(stored.idempotencyKey),
                .text(stored.direction.rawValue),
                stored.sessionID.map(SQLiteValue.text) ?? .null,
                .text(stored.status.rawValue),
                .double(stored.createdAt.timeIntervalSince1970),
                .double(stored.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(stored)),
            ]
        )
        return stored
    }

    public func delivery(idempotencyKey: String) async throws -> DeliveryRecord? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM deliveries
            WHERE idempotency_key = ?
            LIMIT 1;
            """,
            bindings: [.text(idempotencyKey)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(DeliveryRecord.self, from: data)
    }

    public func deliveries(
        direction: DeliveryRecord.Direction? = nil,
        sessionID: String? = nil,
        status: DeliveryRecord.Status? = nil
    ) async throws -> [DeliveryRecord] {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM deliveries
            ORDER BY created_at ASC;
            """
        )

        return try rows.compactMap { row in
            guard let data = row["payload_json"]?.dataValue else {
                return nil
            }
            let record = try decoder.decode(DeliveryRecord.self, from: data)
            if let direction, record.direction != direction {
                return nil
            }
            if let sessionID, record.sessionID != sessionID {
                return nil
            }
            if let status, record.status != status {
                return nil
            }
            return record
        }
    }

    private static func createSchema(on connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS deliveries (
                delivery_id TEXT PRIMARY KEY,
                idempotency_key TEXT NOT NULL UNIQUE,
                direction TEXT NOT NULL,
                session_id TEXT,
                status TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS deliveries_session_status_created_idx
            ON deliveries(session_id, status, created_at);
            """
        )
    }
}
