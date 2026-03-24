import Foundation
import OmniAIAgent
import OmniAgentMesh

public actor RootAgentToolbox {
    private let server: RootAgentServer

    public init(server: RootAgentServer) {
        self.server = server
    }

    public func registeredTools() -> [RegisteredTool] {
        [
            delegateTaskTool(),
            listWorkersTool(),
            listTasksTool(),
            getTaskStatusTool(),
            waitForTaskTool(),
            listNotificationsTool(),
            resolveNotificationTool(),
        ]
    }

    private func delegateTaskTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "delegate_task",
                description: "Submit a durable task to the worker fabric for execution on an appropriate worker.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "brief": [
                            "type": "string",
                            "description": "Clear task brief for the worker.",
                        ],
                        "capability_requirements": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Capability labels that must be advertised by the worker.",
                        ],
                        "expected_outputs": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Short labels describing the expected outputs or artifacts.",
                        ],
                        "constraints": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Important constraints the worker must respect.",
                        ],
                        "priority": [
                            "type": "integer",
                            "description": "Optional integer priority. Higher numbers run first.",
                        ],
                        "parent_task_id": [
                            "type": "string",
                            "description": "Optional durable parent task ID for child-task lineage.",
                        ],
                    ],
                    "required": ["brief"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let brief = try Self.requiredString("brief", in: arguments)
                let capabilityRequirements = try Self.stringArray("capability_requirements", in: arguments)
                let expectedOutputs = try Self.stringArray("expected_outputs", in: arguments)
                let constraints = try Self.stringArray("constraints", in: arguments)
                let priority = try Self.intValue("priority", in: arguments) ?? 0
                let parentTaskID = try Self.optionalString("parent_task_id", in: arguments)

                let task = try await server.delegateTask(
                    brief: brief,
                    capabilityRequirements: capabilityRequirements,
                    expectedOutputs: expectedOutputs,
                    constraints: constraints,
                    priority: priority,
                    parentTaskID: parentTaskID
                )
                let latest = try await server.task(taskID: task.taskID)
                let startedImmediately = latest?.status != .submitted

                return try Self.renderJSON([
                    "task": Self.serialize(task: latest ?? task),
                    "local_dispatch_started": startedImmediately,
                ])
            }
        )
    }

    private func listWorkersTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "list_workers",
                description: "List currently registered workers and their capabilities.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "required_capabilities": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "If provided, only workers that satisfy all listed capabilities are returned.",
                        ],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let requiredCapabilities = Set(try Self.stringArray("required_capabilities", in: arguments))
                let workers = try await server.listWorkers()
                let filtered = workers.filter { worker in
                    requiredCapabilities.isSubset(of: Set(worker.capabilities))
                }

                return try Self.renderJSON([
                    "workers": filtered.map(Self.serialize(worker:)),
                ])
            }
        )
    }

    private func listTasksTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "list_tasks",
                description: "List durable tasks owned by the root orchestrator session.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "statuses": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Optional task statuses to include: submitted, assigned, running, waiting, completed, failed, cancelled.",
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of tasks to return. Defaults to 20.",
                        ],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let statuses = try Self.statusArray("statuses", in: arguments)
                let limit = max(0, try Self.intValue("limit", in: arguments) ?? 20)
                let tasks = try await server.listTasks(statuses: statuses, limit: limit, currentRootOnly: true)

                return try Self.renderJSON([
                    "tasks": tasks.map(Self.serialize(task:)),
                ])
            }
        )
    }

    private func getTaskStatusTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "get_task_status",
                description: "Inspect one durable task or, if omitted, the latest task owned by the root session.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "task_id": [
                            "type": "string",
                            "description": "Optional task ID. When omitted, the latest root-owned task is used.",
                        ],
                        "event_limit": [
                            "type": "integer",
                            "description": "Maximum number of recent task events to include. Defaults to 10.",
                        ],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let taskID = try Self.optionalString("task_id", in: arguments)
                let eventLimit = max(0, try Self.intValue("event_limit", in: arguments) ?? 10)
                let resolvedTask = try await Self.resolveTask(taskID: taskID, via: server)
                let events = try await server.taskEvents(taskID: resolvedTask.taskID, afterSequence: nil)

                return try Self.renderJSON([
                    "task": Self.serialize(task: resolvedTask),
                    "recent_events": Array(events.suffix(eventLimit)).map(Self.serialize(event:)),
                ])
            }
        )
    }

    private func waitForTaskTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "wait_for_task",
                description: "Wait for a task to reach a terminal status. When task_id is omitted, waits for the latest root-owned task.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "task_id": [
                            "type": "string",
                            "description": "Optional task ID. When omitted, the latest root-owned task is used.",
                        ],
                        "timeout_seconds": [
                            "type": "number",
                            "description": "Maximum time to wait before returning with timed_out=true. Defaults to 60.",
                        ],
                        "poll_interval_seconds": [
                            "type": "number",
                            "description": "Polling interval while waiting. Defaults to 0.25 seconds.",
                        ],
                        "event_limit": [
                            "type": "integer",
                            "description": "Maximum number of recent task events to include in the response. Defaults to 20.",
                        ],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let taskID = try Self.optionalString("task_id", in: arguments)
                let timeoutSeconds = max(0.1, try Self.doubleValue("timeout_seconds", in: arguments) ?? 60)
                let pollIntervalSeconds = max(0.05, try Self.doubleValue("poll_interval_seconds", in: arguments) ?? 0.25)
                let eventLimit = max(0, try Self.intValue("event_limit", in: arguments) ?? 20)
                let result = try await server.waitForTask(
                    taskID: taskID,
                    timeoutSeconds: timeoutSeconds,
                    pollInterval: .milliseconds(Int64(pollIntervalSeconds * 1_000))
                )

                return try Self.renderJSON([
                    "task": result.task.map(Self.serialize(task:)) ?? NSNull(),
                    "timed_out": result.timedOut,
                    "recent_events": Array(result.events.suffix(eventLimit)).map(Self.serialize(event:)),
                    "unresolved_notifications": result.unresolvedNotifications.map(Self.serialize(notification:)),
                ])
            }
        )
    }

    private func listNotificationsTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "list_notifications",
                description: "List notification inbox items for the root orchestrator.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "refresh": [
                            "type": "boolean",
                            "description": "Refresh task-derived notifications before listing. Defaults to true.",
                        ],
                        "unresolved_only": [
                            "type": "boolean",
                            "description": "Only return unresolved notifications. Defaults to true.",
                        ],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let refresh = try Self.boolValue("refresh", in: arguments) ?? true
                let unresolvedOnly = try Self.boolValue("unresolved_only", in: arguments) ?? true
                let notifications = try await server.listNotifications(
                    refresh: refresh,
                    unresolvedOnly: unresolvedOnly
                )

                return try Self.renderJSON([
                    "notifications": notifications.map(Self.serialize(notification:)),
                ])
            }
        )
    }

    private func resolveNotificationTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "resolve_notification",
                description: "Resolve one notification or, if omitted, the oldest unresolved notification.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "notification_id": [
                            "type": "string",
                            "description": "Optional notification ID. When omitted, resolves the oldest unresolved notification.",
                        ],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let notificationID = try Self.optionalString("notification_id", in: arguments)
                let notification = try await server.resolveNotification(notificationID: notificationID)

                return try Self.renderJSON([
                    "notification": Self.serialize(notification: notification),
                ])
            }
        )
    }
}

private extension RootAgentToolbox {
    static func requiredString(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = try optionalString(key, in: arguments), !value.isEmpty else {
            throw RootToolboxError.missingRequiredArgument(key)
        }
        return value
    }

    static func optionalString(_ key: String, in arguments: [String: Any]) throws -> String? {
        guard let value = arguments[key] else {
            return nil
        }
        guard let string = value as? String else {
            throw RootToolboxError.invalidArgument(key: key, expected: "string")
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func stringArray(_ key: String, in arguments: [String: Any]) throws -> [String] {
        guard let value = arguments[key] else {
            return []
        }
        if let strings = value as? [String] {
            return strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let rawItems = value as? [Any] {
            return try rawItems.map { item in
                guard let string = item as? String else {
                    throw RootToolboxError.invalidArgument(key: key, expected: "array of strings")
                }
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        }
        if let string = value as? String {
            return string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        throw RootToolboxError.invalidArgument(key: key, expected: "array of strings")
    }

    static func boolValue(_ key: String, in arguments: [String: Any]) throws -> Bool? {
        guard let value = arguments[key] else {
            return nil
        }
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                break
            }
        }
        throw RootToolboxError.invalidArgument(key: key, expected: "boolean")
    }

    static func intValue(_ key: String, in arguments: [String: Any]) throws -> Int? {
        guard let value = arguments[key] else {
            return nil
        }
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String, let parsed = Int(string) {
            return parsed
        }
        throw RootToolboxError.invalidArgument(key: key, expected: "integer")
    }

    static func doubleValue(_ key: String, in arguments: [String: Any]) throws -> Double? {
        guard let value = arguments[key] else {
            return nil
        }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String, let parsed = Double(string) {
            return parsed
        }
        throw RootToolboxError.invalidArgument(key: key, expected: "number")
    }

    static func statusArray(_ key: String, in arguments: [String: Any]) throws -> [TaskRecord.Status]? {
        let rawStatuses = try stringArray(key, in: arguments)
        guard !rawStatuses.isEmpty else {
            return nil
        }
        return try rawStatuses.map { rawValue in
            guard let status = TaskRecord.Status(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
                throw RootToolboxError.invalidStatus(rawValue)
            }
            return status
        }
    }

    static func resolveTask(taskID: String?, via server: RootAgentServer) async throws -> TaskRecord {
        if let taskID {
            guard let task = try await server.task(taskID: taskID) else {
                throw RootAgentServerError.taskNotFound(taskID)
            }
            return task
        }
        guard let task = try await server.latestTask(currentRootOnly: true) else {
            throw RootAgentServerError.noManagedTasks(sessionID: server.sessionID)
        }
        return task
    }

    static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func serialize(task: TaskRecord) -> [String: Any] {
        [
            "task_id": task.taskID,
            "root_session_id": task.rootSessionID,
            "parent_task_id": task.parentTaskID ?? NSNull(),
            "assigned_agent_id": task.assignedAgentID ?? NSNull(),
            "status": task.status.rawValue,
            "capability_requirements": task.capabilityRequirements,
            "task_brief": task.historyProjection.taskBrief,
            "expected_outputs": task.historyProjection.expectedOutputs,
            "constraints": task.historyProjection.constraints,
            "artifact_refs": task.artifactRefs,
            "priority": task.priority,
            "lease": serialize(lease: task.lease) ?? NSNull(),
            "created_at": iso8601String(task.createdAt),
            "updated_at": iso8601String(task.updatedAt),
        ]
    }

    static func serialize(worker: WorkerRecord) -> [String: Any] {
        [
            "worker_id": worker.workerID,
            "display_name": worker.displayName,
            "capabilities": worker.capabilities,
            "state": worker.state.rawValue,
            "last_heartbeat_at": iso8601String(worker.lastHeartbeatAt),
            "metadata": worker.metadata,
        ]
    }

    static func serialize(event: TaskEvent) -> [String: Any] {
        [
            "task_id": event.taskID,
            "sequence_number": event.sequenceNumber,
            "kind": event.kind.rawValue,
            "worker_id": event.workerID ?? NSNull(),
            "summary": event.summary ?? NSNull(),
            "data": event.data,
            "created_at": iso8601String(event.createdAt),
        ]
    }

    static func serialize(notification: NotificationRecord) -> [String: Any] {
        [
            "notification_id": notification.notificationID,
            "task_id": notification.taskID ?? NSNull(),
            "title": notification.title,
            "body": notification.body,
            "importance": notification.importance.rawValue,
            "status": notification.status.rawValue,
            "metadata": notification.metadata,
            "created_at": iso8601String(notification.createdAt),
            "delivered_at": notification.deliveredAt.map(Self.iso8601String) ?? NSNull(),
            "resolved_at": notification.resolvedAt.map(Self.iso8601String) ?? NSNull(),
        ]
    }

    static func serialize(lease: TaskRecord.Lease?) -> [String: Any]? {
        guard let lease else {
            return nil
        }
        return [
            "owner_id": lease.ownerID,
            "issued_at": iso8601String(lease.issuedAt),
            "expires_at": iso8601String(lease.expiresAt),
        ]
    }

    static func iso8601String(_ date: Date) -> String {
        date.ISO8601Format()
    }
}

private enum RootToolboxError: Error, CustomStringConvertible {
    case missingRequiredArgument(String)
    case invalidArgument(key: String, expected: String)
    case invalidStatus(String)

    var description: String {
        switch self {
        case .missingRequiredArgument(let key):
            return "Missing required argument '\(key)'."
        case .invalidArgument(let key, let expected):
            return "Invalid argument '\(key)'; expected \(expected)."
        case .invalidStatus(let rawValue):
            return "Unknown task status '\(rawValue)'."
        }
    }
}
