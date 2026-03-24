import Foundation

public enum JobStoreError: Error, Sendable {
    case taskNotFound(String)
    case workerNotFound(String)
}

public protocol JobStore: Sendable {
    func createTask(_ task: TaskRecord, idempotencyKey: String?) async throws -> TaskRecord
    func task(taskID: String) async throws -> TaskRecord?
    func tasks(statuses: [TaskRecord.Status]?) async throws -> [TaskRecord]
    func claimNextTask(workerID: String, capabilities: [String], leaseDuration: TimeInterval, now: Date) async throws -> TaskRecord?
    func renewLease(taskID: String, workerID: String, leaseDuration: TimeInterval, now: Date) async throws -> TaskRecord
    func startTask(taskID: String, workerID: String, now: Date, idempotencyKey: String) async throws -> TaskEvent
    func appendProgress(taskID: String, workerID: String?, summary: String, data: [String: String], idempotencyKey: String, now: Date) async throws -> TaskEvent
    func completeTask(taskID: String, workerID: String?, summary: String, artifactRefs: [String], idempotencyKey: String, now: Date) async throws -> TaskEvent
    func failTask(taskID: String, workerID: String?, summary: String, idempotencyKey: String, now: Date) async throws -> TaskEvent
    func cancelTask(taskID: String, workerID: String?, summary: String, idempotencyKey: String, now: Date) async throws -> TaskEvent
    func events(taskID: String, afterSequence: Int?) async throws -> [TaskEvent]
    func upsertWorker(_ worker: WorkerRecord) async throws
    func worker(workerID: String) async throws -> WorkerRecord?
    func workers() async throws -> [WorkerRecord]
    func recordHeartbeat(workerID: String, state: WorkerRecord.State?, at: Date) async throws -> WorkerRecord?
    func recoverOrphanedTasks(now: Date) async throws -> [TaskRecord]
}

public actor SQLiteJobStore: JobStore {
    private let connection: SQLiteConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) throws {
        self.connection = try SQLiteConnection(fileURL: fileURL)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        try Self.createSchema(on: connection)
    }

    public func createTask(_ task: TaskRecord, idempotencyKey: String? = nil) async throws -> TaskRecord {
        if let existing = try loadTask(taskID: task.taskID) {
            return existing
        }

        var created = task
        created.updatedAt = task.createdAt

        try connection.transaction {
            try storeTask(created)
            _ = try insertEvent(
                taskID: created.taskID,
                kind: .submitted,
                idempotencyKey: idempotencyKey ?? "task.submitted.\(created.taskID)",
                workerID: nil,
                summary: created.historyProjection.taskBrief,
                data: ["root_session_id": created.rootSessionID],
                createdAt: created.createdAt
            )
        }

        return created
    }

    public func task(taskID: String) async throws -> TaskRecord? {
        try loadTask(taskID: taskID)
    }

    public func tasks(statuses: [TaskRecord.Status]? = nil) async throws -> [TaskRecord] {
        let decoded = try loadAllTasks()
        guard let statuses else {
            return decoded
        }
        let allowed = Set(statuses)
        return decoded.filter { allowed.contains($0.status) }
    }

    public func claimNextTask(
        workerID: String,
        capabilities: [String],
        leaseDuration: TimeInterval,
        now: Date = Date()
    ) async throws -> TaskRecord? {
        let capabilitySet = Set(capabilities)
        return try connection.transaction {
            let candidates = try loadAllTasks().filter { task in
                switch task.status {
                case .submitted, .waiting:
                    return Set(task.capabilityRequirements).isSubset(of: capabilitySet)
                default:
                    return false
                }
            }

            guard var claimed = candidates.first else {
                return nil
            }

            claimed.assignedAgentID = workerID
            claimed.status = .assigned
            claimed.lease = TaskRecord.Lease(
                ownerID: workerID,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(leaseDuration)
            )
            claimed.updatedAt = now
            try storeTask(claimed)
            _ = try insertEvent(
                taskID: claimed.taskID,
                kind: .assigned,
                idempotencyKey: "task.assigned.\(claimed.taskID).\(workerID).\(Int(now.timeIntervalSince1970 * 1_000))",
                workerID: workerID,
                summary: "Assigned to \(workerID)",
                data: ["lease_expires_at": claimed.lease?.expiresAt.ISO8601Format() ?? ""],
                createdAt: now
            )
            return claimed
        }
    }

    public func renewLease(
        taskID: String,
        workerID: String,
        leaseDuration: TimeInterval,
        now: Date = Date()
    ) async throws -> TaskRecord {
        try connection.transaction {
            guard var task = try loadTask(taskID: taskID) else {
                throw JobStoreError.taskNotFound(taskID)
            }

            task.lease = TaskRecord.Lease(
                ownerID: workerID,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(leaseDuration)
            )
            task.updatedAt = now
            try storeTask(task)
            return task
        }
    }

    public func startTask(
        taskID: String,
        workerID: String,
        now: Date = Date(),
        idempotencyKey: String
    ) async throws -> TaskEvent {
        try connection.transaction {
            guard var task = try loadTask(taskID: taskID) else {
                throw JobStoreError.taskNotFound(taskID)
            }

            task.status = .running
            task.updatedAt = now
            try storeTask(task)
            return try insertEvent(
                taskID: taskID,
                kind: .started,
                idempotencyKey: idempotencyKey,
                workerID: workerID,
                summary: "Task started",
                data: [:],
                createdAt: now
            )
        }
    }

    public func appendProgress(
        taskID: String,
        workerID: String?,
        summary: String,
        data: [String: String],
        idempotencyKey: String,
        now: Date = Date()
    ) async throws -> TaskEvent {
        try connection.transaction {
            guard var task = try loadTask(taskID: taskID) else {
                throw JobStoreError.taskNotFound(taskID)
            }

            task.updatedAt = now
            try storeTask(task)
            return try insertEvent(
                taskID: taskID,
                kind: .progress,
                idempotencyKey: idempotencyKey,
                workerID: workerID,
                summary: summary,
                data: data,
                createdAt: now
            )
        }
    }

    public func completeTask(
        taskID: String,
        workerID: String?,
        summary: String,
        artifactRefs: [String],
        idempotencyKey: String,
        now: Date = Date()
    ) async throws -> TaskEvent {
        try connection.transaction {
            guard var task = try loadTask(taskID: taskID) else {
                throw JobStoreError.taskNotFound(taskID)
            }

            task.status = .completed
            task.artifactRefs = Array(Set(task.artifactRefs + artifactRefs)).sorted()
            task.lease = nil
            task.updatedAt = now
            try storeTask(task)
            return try insertEvent(
                taskID: taskID,
                kind: .completed,
                idempotencyKey: idempotencyKey,
                workerID: workerID,
                summary: summary,
                data: ["artifacts": task.artifactRefs.joined(separator: ",")],
                createdAt: now
            )
        }
    }

    public func failTask(
        taskID: String,
        workerID: String?,
        summary: String,
        idempotencyKey: String,
        now: Date = Date()
    ) async throws -> TaskEvent {
        try connection.transaction {
            guard var task = try loadTask(taskID: taskID) else {
                throw JobStoreError.taskNotFound(taskID)
            }

            task.status = .failed
            task.lease = nil
            task.updatedAt = now
            try storeTask(task)
            return try insertEvent(
                taskID: taskID,
                kind: .failed,
                idempotencyKey: idempotencyKey,
                workerID: workerID,
                summary: summary,
                data: [:],
                createdAt: now
            )
        }
    }

    public func cancelTask(
        taskID: String,
        workerID: String?,
        summary: String,
        idempotencyKey: String,
        now: Date = Date()
    ) async throws -> TaskEvent {
        try connection.transaction {
            guard var task = try loadTask(taskID: taskID) else {
                throw JobStoreError.taskNotFound(taskID)
            }

            task.status = .cancelled
            task.lease = nil
            task.updatedAt = now
            try storeTask(task)
            return try insertEvent(
                taskID: taskID,
                kind: .cancelled,
                idempotencyKey: idempotencyKey,
                workerID: workerID,
                summary: summary,
                data: [:],
                createdAt: now
            )
        }
    }

    public func events(taskID: String, afterSequence: Int? = nil) async throws -> [TaskEvent] {
        let rows: [SQLiteRow]
        if let afterSequence {
            rows = try connection.query(
                """
                SELECT payload_json
                FROM task_events
                WHERE task_id = ? AND sequence > ?
                ORDER BY sequence ASC;
                """,
                bindings: [.text(taskID), .integer(Int64(afterSequence))]
            )
        } else {
            rows = try connection.query(
                """
                SELECT payload_json
                FROM task_events
                WHERE task_id = ?
                ORDER BY sequence ASC;
                """,
                bindings: [.text(taskID)]
            )
        }

        return try rows.compactMap(decodeEvent)
    }

    public func upsertWorker(_ worker: WorkerRecord) async throws {
        try storeWorker(worker)
    }

    public func worker(workerID: String) async throws -> WorkerRecord? {
        try loadWorker(workerID: workerID)
    }

    public func workers() async throws -> [WorkerRecord] {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM workers
            ORDER BY last_heartbeat_at DESC;
            """
        )
        return try rows.compactMap(decodeWorker)
    }

    public func recordHeartbeat(
        workerID: String,
        state: WorkerRecord.State? = nil,
        at: Date = Date()
    ) async throws -> WorkerRecord? {
        guard var worker = try loadWorker(workerID: workerID) else {
            return nil
        }
        worker.lastHeartbeatAt = at
        if let state {
            worker.state = state
        }
        try storeWorker(worker)
        return worker
    }

    public func recoverOrphanedTasks(now: Date = Date()) async throws -> [TaskRecord] {
        try connection.transaction {
            let candidates = try loadAllTasks().filter { task in
                switch task.status {
                case .assigned, .running:
                    return task.lease?.expiresAt ?? .distantFuture < now
                default:
                    return false
                }
            }

            var recovered: [TaskRecord] = []
            for var task in candidates {
                task.status = .waiting
                task.assignedAgentID = nil
                task.lease = nil
                task.updatedAt = now
                try storeTask(task)
                _ = try insertEvent(
                    taskID: task.taskID,
                    kind: .resumed,
                    idempotencyKey: "task.resumed.\(task.taskID).\(Int(now.timeIntervalSince1970 * 1_000))",
                    workerID: nil,
                    summary: "Recovered orphaned task lease",
                    data: [:],
                    createdAt: now
                )
                _ = try insertEvent(
                    taskID: task.taskID,
                    kind: .waiting,
                    idempotencyKey: "task.waiting.\(task.taskID).\(Int(now.timeIntervalSince1970 * 1_000))",
                    workerID: nil,
                    summary: "Task returned to waiting queue",
                    data: [:],
                    createdAt: now
                )
                recovered.append(task)
            }
            return recovered
        }
    }

    private static func createSchema(on connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                task_id TEXT PRIMARY KEY,
                status TEXT NOT NULL,
                assigned_agent_id TEXT,
                lease_owner TEXT,
                lease_expires_at REAL,
                priority INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS tasks_status_priority_idx
            ON tasks(status, priority DESC, created_at ASC);
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS task_events (
                task_id TEXT NOT NULL,
                sequence INTEGER NOT NULL,
                idempotency_key TEXT NOT NULL,
                created_at REAL NOT NULL,
                payload_json BLOB NOT NULL,
                PRIMARY KEY(task_id, sequence),
                UNIQUE(task_id, idempotency_key)
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS task_events_task_sequence_idx
            ON task_events(task_id, sequence);
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS workers (
                worker_id TEXT PRIMARY KEY,
                state TEXT NOT NULL,
                last_heartbeat_at REAL NOT NULL,
                payload_json BLOB NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS workers_state_heartbeat_idx
            ON workers(state, last_heartbeat_at DESC);
            """
        )
    }

    private func loadTask(taskID: String) throws -> TaskRecord? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM tasks
            WHERE task_id = ?;
            """,
            bindings: [.text(taskID)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(TaskRecord.self, from: data)
    }

    private func loadAllTasks() throws -> [TaskRecord] {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM tasks
            ORDER BY priority DESC, created_at ASC;
            """
        )
        return try rows.compactMap(decodeTask)
    }

    private func storeTask(_ task: TaskRecord) throws {
        try connection.execute(
            """
            INSERT OR REPLACE INTO tasks (
                task_id,
                status,
                assigned_agent_id,
                lease_owner,
                lease_expires_at,
                priority,
                created_at,
                updated_at,
                payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(task.taskID),
                .text(task.status.rawValue),
                task.assignedAgentID.map(SQLiteValue.text) ?? .null,
                task.lease.map { SQLiteValue.text($0.ownerID) } ?? .null,
                task.lease.map { .double($0.expiresAt.timeIntervalSince1970) } ?? .null,
                .integer(Int64(task.priority)),
                .double(task.createdAt.timeIntervalSince1970),
                .double(task.updatedAt.timeIntervalSince1970),
                .blob(try encoder.encode(task)),
            ]
        )
    }

    private func loadWorker(workerID: String) throws -> WorkerRecord? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM workers
            WHERE worker_id = ?;
            """,
            bindings: [.text(workerID)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(WorkerRecord.self, from: data)
    }

    private func storeWorker(_ worker: WorkerRecord) throws {
        try connection.execute(
            """
            INSERT OR REPLACE INTO workers (worker_id, state, last_heartbeat_at, payload_json)
            VALUES (?, ?, ?, ?);
            """,
            bindings: [
                .text(worker.workerID),
                .text(worker.state.rawValue),
                .double(worker.lastHeartbeatAt.timeIntervalSince1970),
                .blob(try encoder.encode(worker)),
            ]
        )
    }

    private func loadEvent(taskID: String, idempotencyKey: String) throws -> TaskEvent? {
        let rows = try connection.query(
            """
            SELECT payload_json
            FROM task_events
            WHERE task_id = ? AND idempotency_key = ?;
            """,
            bindings: [.text(taskID), .text(idempotencyKey)]
        )
        guard let row = rows.first, let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(TaskEvent.self, from: data)
    }

    private func insertEvent(
        taskID: String,
        kind: TaskEvent.Kind,
        idempotencyKey: String,
        workerID: String?,
        summary: String?,
        data: [String: String],
        createdAt: Date
    ) throws -> TaskEvent {
        if let existing = try loadEvent(taskID: taskID, idempotencyKey: idempotencyKey) {
            return existing
        }

        let nextSequence = Int(
            (try connection.scalarInt(
                "SELECT COALESCE(MAX(sequence), 0) AS value FROM task_events WHERE task_id = ?;",
                bindings: [.text(taskID)]
            ) ?? 0) + 1
        )

        let event = TaskEvent(
            taskID: taskID,
            sequenceNumber: nextSequence,
            idempotencyKey: idempotencyKey,
            kind: kind,
            workerID: workerID,
            summary: summary,
            data: data,
            createdAt: createdAt
        )

        try connection.execute(
            """
            INSERT INTO task_events (task_id, sequence, idempotency_key, created_at, payload_json)
            VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(taskID),
                .integer(Int64(nextSequence)),
                .text(idempotencyKey),
                .double(createdAt.timeIntervalSince1970),
                .blob(try encoder.encode(event)),
            ]
        )
        return event
    }

    private func decodeTask(from row: SQLiteRow) throws -> TaskRecord? {
        guard let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(TaskRecord.self, from: data)
    }

    private func decodeEvent(from row: SQLiteRow) throws -> TaskEvent? {
        guard let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(TaskEvent.self, from: data)
    }

    private func decodeWorker(from row: SQLiteRow) throws -> WorkerRecord? {
        guard let data = row["payload_json"]?.dataValue else {
            return nil
        }
        return try decoder.decode(WorkerRecord.self, from: data)
    }
}
