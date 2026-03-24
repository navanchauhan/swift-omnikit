import Foundation

public protocol IdentityStore: Sendable {
    func saveActor(_ actor: ActorRecord) async throws
    func actor(actorID: ActorID) async throws -> ActorRecord?
    func saveWorkspace(_ workspace: WorkspaceRecord) async throws
    func workspace(workspaceID: WorkspaceID) async throws -> WorkspaceRecord?
    func saveMembership(_ membership: WorkspaceMembership) async throws
    func membership(workspaceID: WorkspaceID, actorID: ActorID) async throws -> WorkspaceMembership?
    func memberships(workspaceID: WorkspaceID) async throws -> [WorkspaceMembership]
    func saveChannelBinding(_ binding: ChannelBinding) async throws
    func channelBinding(bindingID: String) async throws -> ChannelBinding?
    func channelBinding(transport: ChannelBinding.Transport, externalID: String) async throws -> ChannelBinding?
    func channelBindings(workspaceID: WorkspaceID) async throws -> [ChannelBinding]
}

public actor SQLiteIdentityStore: IdentityStore {
    private let connection: SQLiteConnection
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) throws {
        self.connection = try SQLiteConnection(fileURL: fileURL)
        try Self.createSchema(on: connection)
    }

    public func saveActor(_ actor: ActorRecord) async throws {
        try connection.execute(
            """
            INSERT OR REPLACE INTO actors (actor_id, updated_at, payload_json)
            VALUES (?, ?, ?);
            """,
            bindings: [
                .text(actor.actorID.rawValue),
                .double(actor.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(actor)),
            ]
        )
    }

    public func actor(actorID: ActorID) async throws -> ActorRecord? {
        try loadActor(actorID: actorID)
    }

    public func saveWorkspace(_ workspace: WorkspaceRecord) async throws {
        try connection.execute(
            """
            INSERT OR REPLACE INTO workspaces (workspace_id, updated_at, payload_json)
            VALUES (?, ?, ?);
            """,
            bindings: [
                .text(workspace.workspaceID.rawValue),
                .double(workspace.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(workspace)),
            ]
        )
    }

    public func workspace(workspaceID: WorkspaceID) async throws -> WorkspaceRecord? {
        try loadWorkspace(workspaceID: workspaceID)
    }

    public func saveMembership(_ membership: WorkspaceMembership) async throws {
        try connection.execute(
            """
            INSERT OR REPLACE INTO workspace_memberships (workspace_id, actor_id, updated_at, payload_json)
            VALUES (?, ?, ?, ?);
            """,
            bindings: [
                .text(membership.workspaceID.rawValue),
                .text(membership.actorID.rawValue),
                .double(membership.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(membership)),
            ]
        )
    }

    public func membership(workspaceID: WorkspaceID, actorID: ActorID) async throws -> WorkspaceMembership? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM workspace_memberships
            WHERE workspace_id = ? AND actor_id = ?;
            """,
            bindings: [.text(workspaceID.rawValue), .text(actorID.rawValue)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(WorkspaceMembership.self, from: data)
    }

    public func memberships(workspaceID: WorkspaceID) async throws -> [WorkspaceMembership] {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM workspace_memberships
            WHERE workspace_id = ?
            ORDER BY actor_id ASC;
            """,
            bindings: [.text(workspaceID.rawValue)]
        )
        return try rows.compactMap { row in
            guard let data = row["payload_json"]?.dataValue else {
                return nil
            }
            return try decoder.decode(WorkspaceMembership.self, from: data)
        }
    }

    public func saveChannelBinding(_ binding: ChannelBinding) async throws {
        try connection.execute(
            """
            INSERT OR REPLACE INTO channel_bindings (
                binding_id,
                transport,
                external_id,
                workspace_id,
                channel_id,
                updated_at,
                payload_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(binding.bindingID),
                .text(binding.transport.rawValue),
                .text(binding.externalID),
                .text(binding.workspaceID.rawValue),
                .text(binding.channelID.rawValue),
                .double(binding.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(binding)),
            ]
        )
    }

    public func channelBinding(bindingID: String) async throws -> ChannelBinding? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM channel_bindings
            WHERE binding_id = ?;
            """,
            bindings: [.text(bindingID)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(ChannelBinding.self, from: data)
    }

    public func channelBinding(transport: ChannelBinding.Transport, externalID: String) async throws -> ChannelBinding? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM channel_bindings
            WHERE transport = ? AND external_id = ?
            ORDER BY updated_at DESC
            LIMIT 1;
            """,
            bindings: [.text(transport.rawValue), .text(externalID)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(ChannelBinding.self, from: data)
    }

    public func channelBindings(workspaceID: WorkspaceID) async throws -> [ChannelBinding] {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM channel_bindings
            WHERE workspace_id = ?
            ORDER BY updated_at ASC;
            """,
            bindings: [.text(workspaceID.rawValue)]
        )
        return try rows.compactMap { row in
            guard let data = row["payload_json"]?.dataValue else {
                return nil
            }
            return try decoder.decode(ChannelBinding.self, from: data)
        }
    }

    private static func createSchema(on connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS actors (
                actor_id TEXT PRIMARY KEY,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS workspaces (
                workspace_id TEXT PRIMARY KEY,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS workspace_memberships (
                workspace_id TEXT NOT NULL,
                actor_id TEXT NOT NULL,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL,
                PRIMARY KEY (workspace_id, actor_id)
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS channel_bindings (
                binding_id TEXT PRIMARY KEY,
                transport TEXT NOT NULL,
                external_id TEXT NOT NULL,
                workspace_id TEXT NOT NULL,
                channel_id TEXT NOT NULL,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS channel_bindings_transport_external_id_idx
            ON channel_bindings(transport, external_id, updated_at);
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS channel_bindings_workspace_id_idx
            ON channel_bindings(workspace_id, updated_at);
            """
        )
    }

    private func loadActor(actorID: ActorID) throws -> ActorRecord? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM actors
            WHERE actor_id = ?;
            """,
            bindings: [.text(actorID.rawValue)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(ActorRecord.self, from: data)
    }

    private func loadWorkspace(workspaceID: WorkspaceID) throws -> WorkspaceRecord? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM workspaces
            WHERE workspace_id = ?;
            """,
            bindings: [.text(workspaceID.rawValue)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(WorkspaceRecord.self, from: data)
    }
}
