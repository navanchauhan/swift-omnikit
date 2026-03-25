import Foundation

public protocol SkillStore: Sendable {
    func saveInstallation(_ installation: SkillInstallationRecord) async throws -> SkillInstallationRecord
    func installation(installationID: String) async throws -> SkillInstallationRecord?
    func installations(
        scope: SkillInstallationRecord.Scope?,
        workspaceID: WorkspaceID?,
        skillID: String?
    ) async throws -> [SkillInstallationRecord]

    func saveActivation(_ activation: SkillActivationRecord) async throws -> SkillActivationRecord
    func activation(activationID: String) async throws -> SkillActivationRecord?
    func activations(
        rootSessionID: String?,
        workspaceID: WorkspaceID?,
        missionID: String?,
        statuses: [SkillActivationRecord.Status]?
    ) async throws -> [SkillActivationRecord]
}

public actor SQLiteSkillStore: SkillStore {
    private let connection: SQLiteConnection
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) throws {
        self.connection = try SQLiteConnection(fileURL: fileURL)
        try Self.createSchema(on: connection)
    }

    public func saveInstallation(_ installation: SkillInstallationRecord) async throws -> SkillInstallationRecord {
        var stored = installation
        stored.updatedAt = Date()
        try connection.execute(
            """
            INSERT OR REPLACE INTO skill_installations (
                installation_id,
                skill_id,
                scope,
                workspace_id,
                updated_at,
                payload_json
            ) VALUES (?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(stored.installationID),
                .text(stored.skillID),
                .text(stored.scope.rawValue),
                stored.workspaceID.map { .text($0.rawValue) } ?? .null,
                .double(stored.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(stored)),
            ]
        )
        return stored
    }

    public func installation(installationID: String) async throws -> SkillInstallationRecord? {
        try loadRecord(
            table: "skill_installations",
            idColumn: "installation_id",
            idValue: installationID,
            as: SkillInstallationRecord.self
        )
    }

    public func installations(
        scope: SkillInstallationRecord.Scope? = nil,
        workspaceID: WorkspaceID? = nil,
        skillID: String? = nil
    ) async throws -> [SkillInstallationRecord] {
        try loadRecords(table: "skill_installations", as: SkillInstallationRecord.self)
            .filter { record in
                if let scope, record.scope != scope {
                    return false
                }
                if let workspaceID, record.workspaceID != workspaceID {
                    return false
                }
                if let skillID, record.skillID != skillID {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.installationID < rhs.installationID
            }
    }

    public func saveActivation(_ activation: SkillActivationRecord) async throws -> SkillActivationRecord {
        var stored = activation
        stored.updatedAt = Date()
        try connection.execute(
            """
            INSERT OR REPLACE INTO skill_activations (
                activation_id,
                skill_id,
                root_session_id,
                workspace_id,
                mission_id,
                status,
                updated_at,
                payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(stored.activationID),
                .text(stored.skillID),
                .text(stored.rootSessionID),
                stored.workspaceID.map { .text($0.rawValue) } ?? .null,
                stored.missionID.map(SQLiteValue.text) ?? .null,
                .text(stored.status.rawValue),
                .double(stored.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(stored)),
            ]
        )
        return stored
    }

    public func activation(activationID: String) async throws -> SkillActivationRecord? {
        try loadRecord(
            table: "skill_activations",
            idColumn: "activation_id",
            idValue: activationID,
            as: SkillActivationRecord.self
        )
    }

    public func activations(
        rootSessionID: String? = nil,
        workspaceID: WorkspaceID? = nil,
        missionID: String? = nil,
        statuses: [SkillActivationRecord.Status]? = nil
    ) async throws -> [SkillActivationRecord] {
        let allowed = statuses.map(Set.init)
        return try loadRecords(table: "skill_activations", as: SkillActivationRecord.self)
            .filter { record in
                if let rootSessionID, record.rootSessionID != rootSessionID {
                    return false
                }
                if let workspaceID, record.workspaceID != workspaceID {
                    return false
                }
                if let missionID, record.missionID != missionID {
                    return false
                }
                if let allowed, !allowed.contains(record.status) {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.activationID < rhs.activationID
            }
    }

    private static func createSchema(on connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS skill_installations (
                installation_id TEXT PRIMARY KEY,
                skill_id TEXT NOT NULL,
                scope TEXT NOT NULL,
                workspace_id TEXT,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS skill_installations_scope_workspace_idx
            ON skill_installations(scope, workspace_id, updated_at);
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS skill_activations (
                activation_id TEXT PRIMARY KEY,
                skill_id TEXT NOT NULL,
                root_session_id TEXT NOT NULL,
                workspace_id TEXT,
                mission_id TEXT,
                status TEXT NOT NULL,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS skill_activations_scope_status_idx
            ON skill_activations(root_session_id, workspace_id, mission_id, status, updated_at);
            """
        )
    }

    private func loadRecord<T: Decodable>(
        table: String,
        idColumn: String,
        idValue: String,
        as type: T.Type
    ) throws -> T? {
        let rows = try connection.query(
            "SELECT payload_json FROM \(table) WHERE \(idColumn) = ? LIMIT 1;",
            bindings: [.text(idValue)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(T.self, from: data)
    }

    private func loadRecords<T: Decodable>(
        table: String,
        as type: T.Type
    ) throws -> [T] {
        let rows = try connection.query(
            "SELECT payload_json FROM \(table);"
        )
        return try rows.compactMap { row in
            guard let data = row["payload_json"]?.dataValue else {
                return nil
            }
            return try decoder.decode(T.self, from: data)
        }
    }
}
