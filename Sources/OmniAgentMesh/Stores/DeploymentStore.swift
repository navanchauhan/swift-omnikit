import Foundation

public protocol DeploymentStore: Sendable {
    func saveRelease(_ release: DeploymentRecord, makeActive: Bool) async throws
    func release(releaseID: String) async throws -> DeploymentRecord?
    func activeRelease() async throws -> DeploymentRecord?
    func listReleases() async throws -> [DeploymentRecord]
    func markActiveRelease(_ releaseID: String) async throws
}

public actor SQLiteDeploymentStore: DeploymentStore {
    private let connection: SQLiteConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) throws {
        self.connection = try SQLiteConnection(fileURL: fileURL)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        try Self.createSchema(on: connection)
    }

    public func saveRelease(_ release: DeploymentRecord, makeActive: Bool = false) async throws {
        try connection.transaction {
            if makeActive {
                try connection.execute("UPDATE releases SET is_active = 0;")
            }
            try connection.execute(
                """
                INSERT OR REPLACE INTO releases (release_id, is_active, updated_at, payload_json)
                VALUES (?, ?, ?, ?);
                """,
                bindings: [
                    .text(release.releaseID),
                    .integer(makeActive ? 1 : 0),
                    .double(release.updatedAt.timeIntervalSince1970),
                    .blob(try encoder.encode(release)),
                ]
            )
        }
    }

    public func release(releaseID: String) async throws -> DeploymentRecord? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM releases
            WHERE release_id = ?;
            """,
            bindings: [.text(releaseID)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(DeploymentRecord.self, from: data)
    }

    public func activeRelease() async throws -> DeploymentRecord? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM releases
            WHERE is_active = 1
            ORDER BY updated_at DESC
            LIMIT 1;
            """
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(DeploymentRecord.self, from: data)
    }

    public func listReleases() async throws -> [DeploymentRecord] {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM releases
            ORDER BY updated_at DESC;
            """
        )
        return try rows.compactMap { row in
            guard let data = row["payload_json"]?.dataValue else {
                return nil
            }
            return try decoder.decode(DeploymentRecord.self, from: data)
        }
    }

    public func markActiveRelease(_ releaseID: String) async throws {
        guard let release = try await release(releaseID: releaseID) else {
            return
        }
        try await saveRelease(release, makeActive: true)
    }

    private static func createSchema(on connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS releases (
                release_id TEXT PRIMARY KEY,
                is_active INTEGER NOT NULL,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS releases_active_updated_idx
            ON releases(is_active, updated_at DESC);
            """
        )
    }
}
