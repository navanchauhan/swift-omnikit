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
            startMissionTool(),
            listMissionsTool(),
            missionStatusTool(),
            waitForMissionTool(),
            listInboxTool(),
            approveRequestTool(),
            answerQuestionTool(),
            cancelMissionTool(),
            pauseMissionTool(),
            resumeMissionTool(),
            retryMissionStageTool(),
            delegateTaskTool(),
            listWorkersTool(),
            listTasksTool(),
            getTaskStatusTool(),
            waitForTaskTool(),
            listNotificationsTool(),
            resolveNotificationTool(),
        ]
    }

    private func startMissionTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "start_mission",
                description: "Create and start a durable mission owned by the root orchestrator.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "brief": ["type": "string"],
                        "execution_mode": [
                            "type": "string",
                            "description": "Optional execution mode: direct, worker_task, attractor_workflow.",
                        ],
                        "capability_requirements": [
                            "type": "array",
                            "items": ["type": "string"],
                        ],
                        "expected_outputs": [
                            "type": "array",
                            "items": ["type": "string"],
                        ],
                        "constraints": [
                            "type": "array",
                            "items": ["type": "string"],
                        ],
                        "priority": ["type": "integer"],
                        "budget_units": ["type": "integer"],
                        "max_recursion_depth": ["type": "integer"],
                        "require_approval": ["type": "boolean"],
                        "approval_prompt": ["type": "string"],
                    ],
                    "required": ["title", "brief"],
                    "additionalProperties": true,
                ]
            ),
            executor: { [server] arguments, _ in
                let title = try Self.requiredString("title", in: arguments)
                let brief = try Self.requiredString("brief", in: arguments)
                let executionMode = try Self.missionExecutionMode("execution_mode", in: arguments)
                let capabilityRequirements = try Self.stringArray("capability_requirements", in: arguments)
                let expectedOutputs = try Self.stringArray("expected_outputs", in: arguments)
                let constraints = try Self.stringArray("constraints", in: arguments)
                let priority = try Self.intValue("priority", in: arguments) ?? 0
                let budgetUnits = try Self.intValue("budget_units", in: arguments) ?? 1
                let maxRecursionDepth = try Self.intValue("max_recursion_depth", in: arguments)
                let requireApproval = try Self.boolValue("require_approval", in: arguments) ?? false
                let approvalPrompt = try Self.optionalString("approval_prompt", in: arguments)
                let metadata = try Self.stringDictionary(excluding: [
                    "title",
                    "brief",
                    "execution_mode",
                    "capability_requirements",
                    "expected_outputs",
                    "constraints",
                    "priority",
                    "budget_units",
                    "max_recursion_depth",
                    "require_approval",
                    "approval_prompt",
                ], in: arguments)

                let snapshot = try await server.startMission(
                    MissionStartRequest(
                        title: title,
                        brief: brief,
                        executionMode: executionMode,
                        capabilityRequirements: capabilityRequirements,
                        expectedOutputs: expectedOutputs,
                        constraints: constraints,
                        priority: priority,
                        budgetUnits: budgetUnits,
                        maxRecursionDepth: maxRecursionDepth,
                        requireApproval: requireApproval,
                        approvalPrompt: approvalPrompt,
                        metadata: metadata
                    )
                )

                return try Self.renderJSON([
                    "mission": Self.serialize(mission: snapshot.mission),
                    "stages": snapshot.stages.map(Self.serialize(stage:)),
                    "task": snapshot.task.map(Self.serialize(task:)) ?? NSNull(),
                    "approvals": snapshot.approvals.map(Self.serialize(approval:)),
                    "questions": snapshot.questions.map(Self.serialize(question:)),
                    "recent_events": snapshot.recentEvents.map(Self.serialize(event:)),
                ])
            }
        )
    }

    private func listMissionsTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "list_missions",
                description: "List durable missions owned by the current root scope.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "statuses": [
                            "type": "array",
                            "items": ["type": "string"],
                        ],
                        "limit": ["type": "integer"],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let statuses = try Self.missionStatusArray("statuses", in: arguments)
                let limit = max(0, try Self.intValue("limit", in: arguments) ?? 20)
                let missions = try await server.listMissions(statuses: statuses, limit: limit)
                return try Self.renderJSON([
                    "missions": missions.map(Self.serialize(mission:)),
                ])
            }
        )
    }

    private func missionStatusTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "mission_status",
                description: "Inspect the latest mission or one specific mission.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "mission_id": ["type": "string"],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let missionID = try Self.optionalString("mission_id", in: arguments)
                let snapshot = try await server.missionStatus(missionID: missionID)
                return try Self.renderJSON([
                    "mission": Self.serialize(mission: snapshot.mission),
                    "stages": snapshot.stages.map(Self.serialize(stage:)),
                    "task": snapshot.task.map(Self.serialize(task:)) ?? NSNull(),
                    "approvals": snapshot.approvals.map(Self.serialize(approval:)),
                    "questions": snapshot.questions.map(Self.serialize(question:)),
                    "recent_events": snapshot.recentEvents.map(Self.serialize(event:)),
                ])
            }
        )
    }

    private func waitForMissionTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "wait_for_mission",
                description: "Wait for a mission to reach a terminal state.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "mission_id": ["type": "string"],
                        "timeout_seconds": ["type": "number"],
                        "poll_interval_seconds": ["type": "number"],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let missionID = try Self.optionalString("mission_id", in: arguments)
                let timeoutSeconds = max(0.1, try Self.doubleValue("timeout_seconds", in: arguments) ?? 60)
                let pollIntervalSeconds = max(0.05, try Self.doubleValue("poll_interval_seconds", in: arguments) ?? 0.25)
                let snapshot = try await server.waitForMission(
                    missionID: missionID,
                    timeoutSeconds: timeoutSeconds,
                    pollInterval: .milliseconds(Int64(pollIntervalSeconds * 1_000))
                )
                return try Self.renderJSON([
                    "mission": Self.serialize(mission: snapshot.mission),
                    "stages": snapshot.stages.map(Self.serialize(stage:)),
                    "task": snapshot.task.map(Self.serialize(task:)) ?? NSNull(),
                    "approvals": snapshot.approvals.map(Self.serialize(approval:)),
                    "questions": snapshot.questions.map(Self.serialize(question:)),
                    "recent_events": snapshot.recentEvents.map(Self.serialize(event:)),
                ])
            }
        )
    }

    private func listInboxTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "list_inbox",
                description: "List root-owned inbox items, including notifications, approvals, and questions.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "unresolved_only": ["type": "boolean"],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let unresolvedOnly = try Self.boolValue("unresolved_only", in: arguments) ?? true
                let items = try await server.listInbox(unresolvedOnly: unresolvedOnly)
                return try Self.renderJSON([
                    "items": items.map(Self.serialize(inboxItem:)),
                ])
            }
        )
    }

    private func approveRequestTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "approve_request",
                description: "Approve or reject a pending approval request.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "request_id": ["type": "string"],
                        "approved": ["type": "boolean"],
                        "response_text": ["type": "string"],
                    ],
                    "required": ["request_id", "approved"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let requestID = try Self.requiredString("request_id", in: arguments)
                let approved = try Self.boolValue("approved", in: arguments) ?? false
                let responseText = try Self.optionalString("response_text", in: arguments)
                let request = try await server.approveRequest(
                    requestID: requestID,
                    approved: approved,
                    responseText: responseText
                )
                return try Self.renderJSON([
                    "approval": Self.serialize(approval: request),
                ])
            }
        )
    }

    private func answerQuestionTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "answer_question",
                description: "Provide the answer for a pending mission question.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "request_id": ["type": "string"],
                        "answer_text": ["type": "string"],
                    ],
                    "required": ["request_id", "answer_text"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let requestID = try Self.requiredString("request_id", in: arguments)
                let answerText = try Self.requiredString("answer_text", in: arguments)
                let question = try await server.answerQuestion(
                    requestID: requestID,
                    answerText: answerText
                )
                return try Self.renderJSON([
                    "question": Self.serialize(question: question),
                ])
            }
        )
    }

    private func cancelMissionTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "cancel_mission",
                description: "Cancel a mission and its primary task if one exists.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "mission_id": ["type": "string"],
                    ],
                    "required": ["mission_id"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let missionID = try Self.requiredString("mission_id", in: arguments)
                let mission = try await server.cancelMission(missionID: missionID)
                return try Self.renderJSON([
                    "mission": Self.serialize(mission: mission),
                ])
            }
        )
    }

    private func pauseMissionTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "pause_mission",
                description: "Mark a mission as paused.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "mission_id": ["type": "string"],
                    ],
                    "required": ["mission_id"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let missionID = try Self.requiredString("mission_id", in: arguments)
                let mission = try await server.pauseMission(missionID: missionID)
                return try Self.renderJSON([
                    "mission": Self.serialize(mission: mission),
                ])
            }
        )
    }

    private func resumeMissionTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "resume_mission",
                description: "Resume a paused mission.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "mission_id": ["type": "string"],
                    ],
                    "required": ["mission_id"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let missionID = try Self.requiredString("mission_id", in: arguments)
                let mission = try await server.resumeMission(missionID: missionID)
                return try Self.renderJSON([
                    "mission": Self.serialize(mission: mission),
                ])
            }
        )
    }

    private func retryMissionStageTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "retry_mission_stage",
                description: "Retry a failed mission stage.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "stage_id": ["type": "string"],
                    ],
                    "required": ["stage_id"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let stageID = try Self.requiredString("stage_id", in: arguments)
                let stage = try await server.retryMissionStage(stageID: stageID)
                return try Self.renderJSON([
                    "stage": Self.serialize(stage: stage),
                ])
            }
        )
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

    static func missionExecutionMode(_ key: String, in arguments: [String: Any]) throws -> MissionRecord.ExecutionMode? {
        guard let rawValue = try optionalString(key, in: arguments) else {
            return nil
        }
        guard let mode = MissionRecord.ExecutionMode(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            throw RootToolboxError.invalidMissionExecutionMode(rawValue)
        }
        return mode
    }

    static func missionStatusArray(_ key: String, in arguments: [String: Any]) throws -> [MissionRecord.Status]? {
        let rawStatuses = try stringArray(key, in: arguments)
        guard !rawStatuses.isEmpty else {
            return nil
        }
        return try rawStatuses.map { rawValue in
            guard let status = MissionRecord.Status(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
                throw RootToolboxError.invalidMissionStatus(rawValue)
            }
            return status
        }
    }

    static func stringDictionary(excluding excludedKeys: Set<String>, in arguments: [String: Any]) throws -> [String: String] {
        arguments.reduce(into: [String: String]()) { partialResult, entry in
            guard !excludedKeys.contains(entry.key) else {
                return
            }
            switch entry.value {
            case let string as String:
                partialResult[entry.key] = string
            case let number as NSNumber:
                partialResult[entry.key] = number.stringValue
            case let bool as Bool:
                partialResult[entry.key] = bool ? "true" : "false"
            default:
                break
            }
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
            "mission_id": task.missionID ?? NSNull(),
            "parent_task_id": task.parentTaskID ?? NSNull(),
            "assigned_agent_id": task.assignedAgentID ?? NSNull(),
            "status": task.status.rawValue,
            "capability_requirements": task.capabilityRequirements,
            "task_brief": task.historyProjection.taskBrief,
            "expected_outputs": task.historyProjection.expectedOutputs,
            "constraints": task.historyProjection.constraints,
            "artifact_refs": task.artifactRefs,
            "attempt_count": task.attemptCount,
            "max_attempts": task.maxAttempts,
            "deadline_at": task.deadlineAt.map(Self.iso8601String) ?? NSNull(),
            "restart_policy": task.restartPolicy.rawValue,
            "escalation_policy": task.escalationPolicy.rawValue,
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

    static func serialize(mission: MissionRecord) -> [String: Any] {
        [
            "mission_id": mission.missionID,
            "root_session_id": mission.rootSessionID,
            "title": mission.title,
            "brief": mission.brief,
            "execution_mode": mission.executionMode.rawValue,
            "status": mission.status.rawValue,
            "primary_task_id": mission.primaryTaskID ?? NSNull(),
            "contract_artifact_id": mission.contractArtifactID ?? NSNull(),
            "progress_artifact_id": mission.progressArtifactID ?? NSNull(),
            "verification_artifact_id": mission.verificationArtifactID ?? NSNull(),
            "budget_units": mission.budgetUnits,
            "max_recursion_depth": mission.maxRecursionDepth,
            "metadata": mission.metadata,
            "created_at": iso8601String(mission.createdAt),
            "updated_at": iso8601String(mission.updatedAt),
            "completed_at": mission.completedAt.map(Self.iso8601String) ?? NSNull(),
        ]
    }

    static func serialize(stage: MissionStageRecord) -> [String: Any] {
        [
            "stage_id": stage.stageID,
            "mission_id": stage.missionID,
            "task_id": stage.taskID ?? NSNull(),
            "parent_stage_id": stage.parentStageID ?? NSNull(),
            "kind": stage.kind.rawValue,
            "execution_mode": stage.executionMode.rawValue,
            "title": stage.title,
            "status": stage.status.rawValue,
            "attempt_count": stage.attemptCount,
            "max_attempts": stage.maxAttempts,
            "deadline_at": stage.deadlineAt.map(Self.iso8601String) ?? NSNull(),
            "artifact_refs": stage.artifactRefs,
            "metadata": stage.metadata,
            "created_at": iso8601String(stage.createdAt),
            "updated_at": iso8601String(stage.updatedAt),
            "completed_at": stage.completedAt.map(Self.iso8601String) ?? NSNull(),
        ]
    }

    static func serialize(approval: ApprovalRequestRecord) -> [String: Any] {
        [
            "request_id": approval.requestID,
            "mission_id": approval.missionID ?? NSNull(),
            "task_id": approval.taskID ?? NSNull(),
            "title": approval.title,
            "prompt": approval.prompt,
            "sensitive": approval.sensitive,
            "delivery_preference": approval.deliveryPreference.rawValue,
            "status": approval.status.rawValue,
            "response_actor_id": approval.responseActorID?.rawValue ?? NSNull(),
            "response_text": approval.responseText ?? NSNull(),
            "metadata": approval.metadata,
            "created_at": iso8601String(approval.createdAt),
            "updated_at": iso8601String(approval.updatedAt),
            "responded_at": approval.respondedAt.map(Self.iso8601String) ?? NSNull(),
        ]
    }

    static func serialize(question: QuestionRequestRecord) -> [String: Any] {
        [
            "request_id": question.requestID,
            "mission_id": question.missionID ?? NSNull(),
            "task_id": question.taskID ?? NSNull(),
            "title": question.title,
            "prompt": question.prompt,
            "kind": question.kind.rawValue,
            "options": question.options,
            "status": question.status.rawValue,
            "answer_actor_id": question.answerActorID?.rawValue ?? NSNull(),
            "answer_text": question.answerText ?? NSNull(),
            "metadata": question.metadata,
            "created_at": iso8601String(question.createdAt),
            "updated_at": iso8601String(question.updatedAt),
            "answered_at": question.answeredAt.map(Self.iso8601String) ?? NSNull(),
        ]
    }

    static func serialize(inboxItem: InteractionInboxItem) -> [String: Any] {
        [
            "id": inboxItem.id,
            "kind": inboxItem.kind.rawValue,
            "title": inboxItem.title,
            "body": inboxItem.body,
            "status": inboxItem.status,
            "created_at": iso8601String(inboxItem.createdAt),
            "metadata": inboxItem.metadata,
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
    case invalidMissionStatus(String)
    case invalidMissionExecutionMode(String)

    var description: String {
        switch self {
        case .missingRequiredArgument(let key):
            return "Missing required argument '\(key)'."
        case .invalidArgument(let key, let expected):
            return "Invalid argument '\(key)'; expected \(expected)."
        case .invalidStatus(let rawValue):
            return "Unknown task status '\(rawValue)'."
        case .invalidMissionStatus(let rawValue):
            return "Unknown mission status '\(rawValue)'."
        case .invalidMissionExecutionMode(let rawValue):
            return "Unknown mission execution mode '\(rawValue)'."
        }
    }
}
