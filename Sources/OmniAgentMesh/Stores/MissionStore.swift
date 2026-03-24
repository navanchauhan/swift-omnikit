import Foundation

public protocol MissionStore: Sendable {
    func saveMission(_ mission: MissionRecord) async throws -> MissionRecord
    func mission(missionID: String) async throws -> MissionRecord?
    func missions(
        sessionID: String?,
        workspaceID: WorkspaceID?,
        statuses: [MissionRecord.Status]?
    ) async throws -> [MissionRecord]

    func saveStage(_ stage: MissionStageRecord) async throws -> MissionStageRecord
    func stage(stageID: String) async throws -> MissionStageRecord?
    func stages(missionID: String) async throws -> [MissionStageRecord]

    func saveApprovalRequest(_ request: ApprovalRequestRecord) async throws -> ApprovalRequestRecord
    func approvalRequest(requestID: String) async throws -> ApprovalRequestRecord?
    func approvalRequests(
        sessionID: String?,
        workspaceID: WorkspaceID?,
        statuses: [ApprovalRequestRecord.Status]?
    ) async throws -> [ApprovalRequestRecord]

    func saveQuestionRequest(_ request: QuestionRequestRecord) async throws -> QuestionRequestRecord
    func questionRequest(requestID: String) async throws -> QuestionRequestRecord?
    func questionRequests(
        sessionID: String?,
        workspaceID: WorkspaceID?,
        statuses: [QuestionRequestRecord.Status]?
    ) async throws -> [QuestionRequestRecord]
}

public actor SQLiteMissionStore: MissionStore {
    private let connection: SQLiteConnection
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) throws {
        self.connection = try SQLiteConnection(fileURL: fileURL)
        try Self.createSchema(on: connection)
    }

    public func saveMission(_ mission: MissionRecord) async throws -> MissionRecord {
        var stored = mission
        stored.updatedAt = Date()
        try connection.execute(
            """
            INSERT OR REPLACE INTO missions (
                mission_id,
                session_id,
                workspace_id,
                status,
                updated_at,
                payload_json
            ) VALUES (?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(stored.missionID),
                .text(stored.rootSessionID),
                stored.workspaceID.map { .text($0.rawValue) } ?? .null,
                .text(stored.status.rawValue),
                .double(stored.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(stored)),
            ]
        )
        return stored
    }

    public func mission(missionID: String) async throws -> MissionRecord? {
        try loadRecord(
            table: "missions",
            idColumn: "mission_id",
            idValue: missionID,
            as: MissionRecord.self
        )
    }

    public func missions(
        sessionID: String? = nil,
        workspaceID: WorkspaceID? = nil,
        statuses: [MissionRecord.Status]? = nil
    ) async throws -> [MissionRecord] {
        try loadRecords(table: "missions", as: MissionRecord.self)
            .filter { record in
                if let sessionID, record.rootSessionID != sessionID {
                    return false
                }
                if let workspaceID, record.workspaceID != workspaceID {
                    return false
                }
                if let statuses, !statuses.contains(record.status) {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.missionID < rhs.missionID
            }
    }

    public func saveStage(_ stage: MissionStageRecord) async throws -> MissionStageRecord {
        var stored = stage
        stored.updatedAt = Date()
        try connection.execute(
            """
            INSERT OR REPLACE INTO mission_stages (
                stage_id,
                mission_id,
                session_id,
                workspace_id,
                status,
                updated_at,
                payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(stored.stageID),
                .text(stored.missionID),
                .text(stored.rootSessionID),
                stored.workspaceID.map { .text($0.rawValue) } ?? .null,
                .text(stored.status.rawValue),
                .double(stored.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(stored)),
            ]
        )
        return stored
    }

    public func stage(stageID: String) async throws -> MissionStageRecord? {
        try loadRecord(
            table: "mission_stages",
            idColumn: "stage_id",
            idValue: stageID,
            as: MissionStageRecord.self
        )
    }

    public func stages(missionID: String) async throws -> [MissionStageRecord] {
        try loadRecords(table: "mission_stages", as: MissionStageRecord.self)
            .filter { $0.missionID == missionID }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.stageID < rhs.stageID
            }
    }

    public func saveApprovalRequest(_ request: ApprovalRequestRecord) async throws -> ApprovalRequestRecord {
        var stored = request
        stored.updatedAt = Date()
        try connection.execute(
            """
            INSERT OR REPLACE INTO approval_requests (
                request_id,
                mission_id,
                session_id,
                workspace_id,
                status,
                updated_at,
                payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(stored.requestID),
                stored.missionID.map(SQLiteValue.text) ?? .null,
                .text(stored.rootSessionID),
                stored.workspaceID.map { .text($0.rawValue) } ?? .null,
                .text(stored.status.rawValue),
                .double(stored.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(stored)),
            ]
        )
        return stored
    }

    public func approvalRequest(requestID: String) async throws -> ApprovalRequestRecord? {
        try loadRecord(
            table: "approval_requests",
            idColumn: "request_id",
            idValue: requestID,
            as: ApprovalRequestRecord.self
        )
    }

    public func approvalRequests(
        sessionID: String? = nil,
        workspaceID: WorkspaceID? = nil,
        statuses: [ApprovalRequestRecord.Status]? = nil
    ) async throws -> [ApprovalRequestRecord] {
        try loadRecords(table: "approval_requests", as: ApprovalRequestRecord.self)
            .filter { record in
                if let sessionID, record.rootSessionID != sessionID {
                    return false
                }
                if let workspaceID, record.workspaceID != workspaceID {
                    return false
                }
                if let statuses, !statuses.contains(record.status) {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.requestID < rhs.requestID
            }
    }

    public func saveQuestionRequest(_ request: QuestionRequestRecord) async throws -> QuestionRequestRecord {
        var stored = request
        stored.updatedAt = Date()
        try connection.execute(
            """
            INSERT OR REPLACE INTO question_requests (
                request_id,
                mission_id,
                session_id,
                workspace_id,
                status,
                updated_at,
                payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(stored.requestID),
                stored.missionID.map(SQLiteValue.text) ?? .null,
                .text(stored.rootSessionID),
                stored.workspaceID.map { .text($0.rawValue) } ?? .null,
                .text(stored.status.rawValue),
                .double(stored.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(stored)),
            ]
        )
        return stored
    }

    public func questionRequest(requestID: String) async throws -> QuestionRequestRecord? {
        try loadRecord(
            table: "question_requests",
            idColumn: "request_id",
            idValue: requestID,
            as: QuestionRequestRecord.self
        )
    }

    public func questionRequests(
        sessionID: String? = nil,
        workspaceID: WorkspaceID? = nil,
        statuses: [QuestionRequestRecord.Status]? = nil
    ) async throws -> [QuestionRequestRecord] {
        try loadRecords(table: "question_requests", as: QuestionRequestRecord.self)
            .filter { record in
                if let sessionID, record.rootSessionID != sessionID {
                    return false
                }
                if let workspaceID, record.workspaceID != workspaceID {
                    return false
                }
                if let statuses, !statuses.contains(record.status) {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.requestID < rhs.requestID
            }
    }

    private static func createSchema(on connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS missions (
                mission_id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                workspace_id TEXT,
                status TEXT NOT NULL,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS missions_session_workspace_status_idx
            ON missions(session_id, workspace_id, status, updated_at);
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS mission_stages (
                stage_id TEXT PRIMARY KEY,
                mission_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                workspace_id TEXT,
                status TEXT NOT NULL,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS mission_stages_mission_updated_idx
            ON mission_stages(mission_id, updated_at);
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS approval_requests (
                request_id TEXT PRIMARY KEY,
                mission_id TEXT,
                session_id TEXT NOT NULL,
                workspace_id TEXT,
                status TEXT NOT NULL,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS approval_requests_session_workspace_status_idx
            ON approval_requests(session_id, workspace_id, status, updated_at);
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS question_requests (
                request_id TEXT PRIMARY KEY,
                mission_id TEXT,
                session_id TEXT NOT NULL,
                workspace_id TEXT,
                status TEXT NOT NULL,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS question_requests_session_workspace_status_idx
            ON question_requests(session_id, workspace_id, status, updated_at);
            """
        )
    }

    private func loadRecord<Record: Decodable>(
        table: String,
        idColumn: String,
        idValue: String,
        as type: Record.Type
    ) throws -> Record? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM \(table)
            WHERE \(idColumn) = ?;
            """,
            bindings: [.text(idValue)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(type, from: data)
    }

    private func loadRecords<Record: Decodable>(
        table: String,
        as type: Record.Type
    ) throws -> [Record] {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM \(table);
            """
        )
        return try rows.compactMap { row in
            guard let data = row["payload_json"]?.dataValue else {
                return nil
            }
            return try decoder.decode(type, from: data)
        }
    }
}
