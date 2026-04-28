import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OmniAIAgent
import OmniAICore
import OmniAgentMesh
import OmniSkills

public actor RootAgentToolbox {
    private let server: RootAgentServer
    private let scheduledPromptStore: (any ScheduledPromptStore)?
    private let draftActionStore: DraftActionStore?

    public init(
        server: RootAgentServer,
        scheduledPromptStore: (any ScheduledPromptStore)? = nil,
        draftActionStore: DraftActionStore? = nil
    ) {
        self.server = server
        self.scheduledPromptStore = scheduledPromptStore
        self.draftActionStore = draftActionStore
    }

    static func testingSerializeDeliveryMetadata(_ metadata: [String: String]) -> [String: Any] {
        serialize(deliveryMetadata: metadata)
    }

    public func registeredTools() -> [RegisteredTool] {
        [
            listSkillsTool(),
            installSkillTool(),
            activateSkillTool(),
            deactivateSkillTool(),
            skillStatusTool(),
            doctorTool(),
            manageTPUExperimentTool(),
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
            listArtifactsTool(),
            getArtifactTool(),
            emailAccountsListTool(),
            emailTriageNeedsReplyTool(),
            emailListRecentTool(),
            emailSearchTool(),
            emailGetMessageTool(),
            emailCreateDraftTool(),
            emailSendTool(),
            emailReplyTool(),
            davAccountsListTool(),
            calendarListTool(),
            calendarListEventsTool(),
            calendarFindFreeTimeTool(),
            calendarCreateEventTool(),
            calendarDeleteEventTool(),
            contactsSearchTool(),
            contactsCreateTool(),
            webDAVListFilesTool(),
            webDAVPutTextFileTool(),
            memorySearchTool(),
            dailyBriefingSnapshotTool(),
            channelSendMessageTool(),
            channelSendArtifactTool(),
            imageGenerateTool(),
            imageEditTool(),
            imageDownloadTool(),
            noResponseTool(),
            channelReactTool(),
            channelSetReplyEffectTool(),
            displayDraftTool(),
            draftActionListTool(),
            draftActionCancelTool(),
            draftActionExecuteTool(),
            schedulePromptTool(),
            listScheduledPromptsTool(),
            cancelScheduledPromptTool(),
            listNotificationsTool(),
            resolveNotificationTool(),
        ]
    }

    private func listSkillsTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "list_skills",
                description: "List installed and active OmniSkills for the current workspace or mission.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "skill_id": ["type": "string"],
                        "mission_id": ["type": "string"],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let skillID = try Self.optionalString("skill_id", in: arguments)
                let missionID = try Self.optionalString("mission_id", in: arguments)
                return try Self.renderJSON(
                    Self.serialize(
                        skillStatus: try await server.listSkills(skillID: skillID, missionID: missionID)
                    )
                )
            }
        )
    }

    private func installSkillTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "install_skill",
                description: "Install an OmniSkill from a local directory or zip archive.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "source_path": ["type": "string"],
                        "scope": ["type": "string"],
                        "activate_after_install": ["type": "boolean"],
                        "activation_scope": ["type": "string"],
                        "mission_id": ["type": "string"],
                        "reason": ["type": "string"],
                        "approved": ["type": "boolean"],
                    ],
                    "required": ["source_path"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let sourcePath = try Self.requiredString("source_path", in: arguments)
                let installationScope = try Self.installationScope("scope", in: arguments) ?? .workspace
                let activateAfterInstall = try Self.boolValue("activate_after_install", in: arguments) ?? false
                let activationScope = try Self.activationScope("activation_scope", in: arguments) ?? .workspace
                let missionID = try Self.optionalString("mission_id", in: arguments)
                let reason = try Self.optionalString("reason", in: arguments) ?? "Installed by root agent."
                let approved = try Self.boolValue("approved", in: arguments) ?? false
                return try Self.renderJSON(
                    Self.serialize(
                        skillOperation: try await server.installSkill(
                            from: sourcePath,
                            scope: installationScope,
                            activateAfterInstall: activateAfterInstall,
                            activationScope: activationScope,
                            missionID: missionID,
                            reason: reason,
                            approved: approved
                        )
                    )
                )
            }
        )
    }

    private func activateSkillTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "activate_skill",
                description: "Activate an OmniSkill for workspace or mission scope.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "skill_id": ["type": "string"],
                        "scope": ["type": "string"],
                        "mission_id": ["type": "string"],
                        "reason": ["type": "string"],
                        "approved": ["type": "boolean"],
                    ],
                    "required": ["skill_id"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let skillID = try Self.requiredString("skill_id", in: arguments)
                let activationScope = try Self.activationScope("scope", in: arguments) ?? .workspace
                let missionID = try Self.optionalString("mission_id", in: arguments)
                let reason = try Self.optionalString("reason", in: arguments) ?? "Activated by root agent."
                let approved = try Self.boolValue("approved", in: arguments) ?? false
                return try Self.renderJSON(
                    Self.serialize(
                        skillOperation: try await server.activateSkill(
                            skillID: skillID,
                            activationScope: activationScope,
                            missionID: missionID,
                            reason: reason,
                            approved: approved
                        )
                    )
                )
            }
        )
    }

    private func deactivateSkillTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "deactivate_skill",
                description: "Deactivate an OmniSkill for workspace or mission scope.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "skill_id": ["type": "string"],
                        "scope": ["type": "string"],
                        "mission_id": ["type": "string"],
                        "reason": ["type": "string"],
                    ],
                    "required": ["skill_id"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let skillID = try Self.requiredString("skill_id", in: arguments)
                let activationScope = try Self.activationScope("scope", in: arguments) ?? .workspace
                let missionID = try Self.optionalString("mission_id", in: arguments)
                let reason = try Self.optionalString("reason", in: arguments) ?? "Deactivated by root agent."
                return try Self.renderJSON(
                    Self.serialize(
                        skillOperation: try await server.deactivateSkill(
                            skillID: skillID,
                            activationScope: activationScope,
                            missionID: missionID,
                            reason: reason
                        )
                    )
                )
            }
        )
    }

    private func skillStatusTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "skill_status",
                description: "Inspect detailed OmniSkill installation, activation, and projection state.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "skill_id": ["type": "string"],
                        "mission_id": ["type": "string"],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let skillID = try Self.optionalString("skill_id", in: arguments)
                let missionID = try Self.optionalString("mission_id", in: arguments)
                return try Self.renderJSON(
                    Self.serialize(
                        skillStatus: try await server.listSkills(skillID: skillID, missionID: missionID)
                    )
                )
            }
        )
    }

    private func doctorTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "doctor",
                description: "Generate a root-owned diagnostics report covering channels, workers, skills, missions, and deliveries.",
                parameters: [
                    "type": "object",
                    "properties": [:],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] _, _ in
                return try Self.renderJSON(
                    [
                        "report": Self.serialize(doctorReport: try await server.doctorReport()),
                    ]
                )
            }
        )
    }

    private func manageTPUExperimentTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "manage_tpu_experiment",
                description: "Start a durable TPU experiment mission for status, comparison, evaluation, sample export, reruns, or improvement work.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "operation": [
                            "type": "string",
                            "description": "One of: inspect_status, compare_best_runs, evaluate_best_checkpoint, export_best_validation_samples, rerun_best_known_config, improve_singing_results.",
                        ],
                        "domain": ["type": "string"],
                        "notes": ["type": "string"],
                        "extra_capabilities": [
                            "type": "array",
                            "items": ["type": "string"],
                        ],
                        "execution_mode": ["type": "string"],
                        "require_approval": ["type": "boolean"],
                    ],
                    "required": ["operation"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let operation = try Self.tpuExperimentOperation("operation", in: arguments)
                let domain = try Self.optionalString("domain", in: arguments) ?? "singing"
                let notes = try Self.optionalString("notes", in: arguments)
                let extraCapabilities = try Self.stringArray("extra_capabilities", in: arguments)
                let executionMode = try Self.missionExecutionMode("execution_mode", in: arguments)
                let requireApproval = try Self.boolValue("require_approval", in: arguments)
                let template = TPUExperimentRunbook.template(
                    for: operation,
                    domain: domain,
                    notes: notes,
                    extraCapabilityRequirements: extraCapabilities,
                    executionModeOverride: executionMode,
                    requireApprovalOverride: requireApproval
                )
                let snapshot = try await server.startTPUExperimentMission(
                    operation: operation,
                    domain: domain,
                    notes: notes,
                    extraCapabilityRequirements: extraCapabilities,
                    executionMode: executionMode,
                    requireApproval: requireApproval
                )

                return try Self.renderJSON([
                    "operation": operation.rawValue,
                    "template": Self.serialize(tpuMissionTemplate: template),
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

    private func listArtifactsTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "list_artifacts",
                description: "List stored artifacts for the current workspace, or narrow by task or mission.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string"],
                        "mission_id": ["type": "string"],
                        "limit": ["type": "integer"],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let taskID = try Self.optionalString("task_id", in: arguments)
                let missionID = try Self.optionalString("mission_id", in: arguments)
                let limit = try Self.intValue("limit", in: arguments)
                let artifacts = try await server.listArtifacts(taskID: taskID, missionID: missionID, limit: limit)
                return try Self.renderJSON([
                    "artifacts": artifacts.map(Self.serialize(artifact:)),
                ])
            }
        )
    }

    private func getArtifactTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "get_artifact",
                description: "Read stored artifact metadata and, when UTF-8 decodable, its text content.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "artifact_id": ["type": "string"],
                        "max_bytes": ["type": "integer"],
                    ],
                    "required": ["artifact_id"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let artifactID = try Self.requiredString("artifact_id", in: arguments)
                let maxBytes = try Self.intValue("max_bytes", in: arguments) ?? 128 * 1_024
                let result = try await server.getArtifact(artifactID: artifactID, maxBytes: maxBytes)
                return try Self.renderJSON([
                    "artifact": Self.serialize(artifactRead: result),
                ])
            }
        )
    }

    private func emailListRecentTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "email_list_recent",
                description: "List recent messages from a configured email account. Defaults to Jeff's account; use email_accounts_list to discover delegated account IDs.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional configured email account ID such as jeff, icloud, gmail, migadu, or boulderwala."],
                        "mailbox": ["type": "string", "description": "Mailbox name, defaults to INBOX."],
                        "limit": ["type": "integer", "description": "Number of recent messages to return, capped at 50."],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                let accountID = try Self.optionalString("account_id", in: arguments)
                let mailbox = try Self.optionalString("mailbox", in: arguments) ?? "INBOX"
                let limit = try Self.intValue("limit", in: arguments) ?? 10
                return try Self.renderJSON(try await JeffEmailClient.listRecent(accountID: accountID, mailbox: mailbox, limit: limit))
            }
        )
    }

    private func emailAccountsListTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "email_accounts_list",
                description: "List configured email accounts that can be used for IMAP/SMTP tools. Secrets are never returned.",
                parameters: [
                    "type": "object",
                    "properties": [:],
                    "additionalProperties": false,
                ]
            ),
            executor: { _, _ in
                try Self.renderJSON(JeffEmailClient.listAccounts())
            }
        )
    }

    private func emailSearchTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "email_search",
                description: "Search recent IMAP mail by local text match over sender, recipients, subject, and preview. Use account_id for delegated inboxes.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional configured email account ID."],
                        "query": ["type": "string"],
                        "mailbox": ["type": "string", "description": "Mailbox name, defaults to INBOX."],
                        "limit": ["type": "integer", "description": "Number of matches to return, capped at 50."],
                        "recent_window": ["type": "integer", "description": "How many recent messages to scan, capped at 250."],
                    ],
                    "required": ["query"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                let accountID = try Self.optionalString("account_id", in: arguments)
                let query = try Self.requiredString("query", in: arguments)
                let mailbox = try Self.optionalString("mailbox", in: arguments) ?? "INBOX"
                let limit = try Self.intValue("limit", in: arguments) ?? 10
                let recentWindow = try Self.intValue("recent_window", in: arguments) ?? 100
                return try Self.renderJSON(
                    try await JeffEmailClient.search(
                        accountID: accountID,
                        mailbox: mailbox,
                        query: query,
                        limit: limit,
                        recentWindow: recentWindow
                    )
                )
            }
        )
    }

    private func emailTriageNeedsReplyTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "email_triage_needs_reply",
                description: "One-call bounded scan across configured email accounts for recent human-sent messages that might need a reply. Prefer this over repeated email_list_recent/email_search calls for inbox triage.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_ids": ["type": "array", "items": ["type": "string"], "description": "Optional account IDs to scan. Defaults to all configured accounts."],
                        "mailbox": ["type": "string", "description": "Mailbox name, defaults to INBOX."],
                        "limit_per_account": ["type": "integer", "description": "Recent messages to scan per account, capped at 25. Defaults to 12."],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                let accountIDs = try Self.stringArray("account_ids", in: arguments)
                let mailbox = try Self.optionalString("mailbox", in: arguments) ?? "INBOX"
                let limit = try Self.intValue("limit_per_account", in: arguments) ?? 12
                return try Self.renderJSON(
                    try await JeffEmailClient.triageNeedsReply(
                        accountIDs: accountIDs.isEmpty ? nil : accountIDs,
                        mailbox: mailbox,
                        limitPerAccount: limit
                    )
                )
            }
        )
    }

    private func emailGetMessageTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "email_get_message",
                description: "Fetch one email by account and IMAP UID, including body preview/content, threading headers, and attachment metadata.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional configured email account ID."],
                        "uid": ["type": "string"],
                        "mailbox": ["type": "string", "description": "Mailbox name, defaults to INBOX."],
                    ],
                    "required": ["uid"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                let accountID = try Self.optionalString("account_id", in: arguments)
                let uid = try Self.requiredString("uid", in: arguments)
                let mailbox = try Self.optionalString("mailbox", in: arguments) ?? "INBOX"
                return try Self.renderJSON(try await JeffEmailClient.getMessage(accountID: accountID, mailbox: mailbox, uid: uid))
            }
        )
    }

    private func emailCreateDraftTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "email_create_draft",
                description: "Create an email draft in the selected account's IMAP Drafts mailbox. This writes external email state; only call after explicit user confirmation to store a mailbox draft. For review-only composition, use display_draft.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional configured email account ID."],
                        "to": ["type": "array", "items": ["type": "string"]],
                        "cc": ["type": "array", "items": ["type": "string"]],
                        "bcc": ["type": "array", "items": ["type": "string"]],
                        "subject": ["type": "string"],
                        "body": ["type": "string"],
                        "confirmed": ["type": "boolean", "description": "Must be true only after explicit user confirmation to write an IMAP Drafts entry."],
                    ],
                    "required": ["to", "subject", "body", "confirmed"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                guard try Self.boolValue("confirmed", in: arguments) == true else {
                    throw RootToolboxError.invalidArgument(key: "confirmed", expected: "true after explicit user confirmation")
                }
                let accountID = try Self.optionalString("account_id", in: arguments)
                let to = try Self.stringArray("to", in: arguments)
                let cc = try Self.stringArray("cc", in: arguments)
                let bcc = try Self.stringArray("bcc", in: arguments)
                let subject = try Self.requiredString("subject", in: arguments)
                let body = try Self.requiredString("body", in: arguments)
                guard !to.isEmpty else {
                    throw RootToolboxError.invalidArgument(key: "to", expected: "at least one recipient")
                }
                return try Self.renderJSON(
                    try await JeffEmailClient.createDraft(accountID: accountID, to: to, cc: cc, bcc: bcc, subject: subject, body: body)
                )
            }
        )
    }

    private func emailSendTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "email_send",
                description: "Send an email through the selected account's configured SMTP account. Only call after explicit user confirmation for the exact recipients, subject, and body.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional configured email account ID."],
                        "to": ["type": "array", "items": ["type": "string"]],
                        "cc": ["type": "array", "items": ["type": "string"]],
                        "bcc": ["type": "array", "items": ["type": "string"]],
                        "subject": ["type": "string"],
                        "body": ["type": "string"],
                        "confirmed": ["type": "boolean", "description": "Must be true only after explicit user confirmation."],
                    ],
                    "required": ["to", "subject", "body", "confirmed"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                guard try Self.boolValue("confirmed", in: arguments) == true else {
                    throw RootToolboxError.invalidArgument(key: "confirmed", expected: "true after explicit user confirmation")
                }
                let accountID = try Self.optionalString("account_id", in: arguments)
                let to = try Self.stringArray("to", in: arguments)
                let cc = try Self.stringArray("cc", in: arguments)
                let bcc = try Self.stringArray("bcc", in: arguments)
                let subject = try Self.requiredString("subject", in: arguments)
                let body = try Self.requiredString("body", in: arguments)
                guard !to.isEmpty else {
                    throw RootToolboxError.invalidArgument(key: "to", expected: "at least one recipient")
                }
                return try Self.renderJSON(
                    try await JeffEmailClient.send(accountID: accountID, to: to, cc: cc, bcc: bcc, subject: subject, body: body)
                )
            }
        )
    }

    private func emailReplyTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "email_reply",
                description: "Reply to an existing email by account, mailbox, and IMAP UID using real In-Reply-To and References headers. Only call after explicit user confirmation for the reply body.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional configured email account ID."],
                        "mailbox": ["type": "string", "description": "Mailbox containing the original message, defaults to INBOX."],
                        "uid": ["type": "string", "description": "IMAP UID of the original message to reply to."],
                        "body": ["type": "string"],
                        "cc": ["type": "array", "items": ["type": "string"]],
                        "bcc": ["type": "array", "items": ["type": "string"]],
                        "reply_all": ["type": "boolean", "description": "Whether to reply-all instead of only replying to the sender."],
                        "confirmed": ["type": "boolean", "description": "Must be true only after explicit user confirmation."],
                    ],
                    "required": ["uid", "body", "confirmed"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                guard try Self.boolValue("confirmed", in: arguments) == true else {
                    throw RootToolboxError.invalidArgument(key: "confirmed", expected: "true after explicit user confirmation")
                }
                let accountID = try Self.optionalString("account_id", in: arguments)
                let mailbox = try Self.optionalString("mailbox", in: arguments) ?? "INBOX"
                let uid = try Self.requiredString("uid", in: arguments)
                let body = try Self.requiredString("body", in: arguments)
                let cc = try Self.stringArray("cc", in: arguments)
                let bcc = try Self.stringArray("bcc", in: arguments)
                let replyAll = try Self.boolValue("reply_all", in: arguments) ?? false
                return try Self.renderJSON(
                    try await JeffEmailClient.reply(accountID: accountID, mailbox: mailbox, uid: uid, body: body, cc: cc, bcc: bcc, replyAll: replyAll)
                )
            }
        )
    }

    private func davAccountsListTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "dav_accounts_list",
                description: "List configured CalDAV/CardDAV/WebDAV capabilities derived from Jeff's email accounts. Secrets are never returned.",
                parameters: [
                    "type": "object",
                    "properties": [:],
                    "additionalProperties": false,
                ]
            ),
            executor: { _, _ in
                try Self.renderJSON(JeffDAVClient.listAccounts())
            }
        )
    }

    private func calendarListTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "calendar_list",
                description: "Discover available calendars for a configured DAV account. Use before calendar event creation if the user did not specify a calendar.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional account ID such as jeff, boulderwala, migadu, or icloud."],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                let accountID = try Self.optionalString("account_id", in: arguments)
                return try Self.renderJSON(await JeffDAVClient.listCalendars(accountID: accountID))
            }
        )
    }

    private func calendarListEventsTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "calendar_list_events",
                description: "List upcoming/past calendar events through CalDAV. Use for schedule checks, conflict checks, and proactive planning.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional DAV account ID. Defaults to all DAV-capable accounts."],
                        "calendar_url": ["type": "string", "description": "Optional explicit CalDAV calendar collection URL."],
                        "days_back": ["type": "integer", "description": "Days before now to include. Defaults to 0."],
                        "days_forward": ["type": "integer", "description": "Days after now to include, capped at 90. Defaults to 14."],
                        "limit": ["type": "integer", "description": "Maximum events to return, capped at 100."],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                let accountID = try Self.optionalString("account_id", in: arguments)
                let calendarURL = try Self.optionalString("calendar_url", in: arguments)
                let daysBack = try Self.intValue("days_back", in: arguments) ?? 0
                let daysForward = try Self.intValue("days_forward", in: arguments) ?? 14
                let limit = try Self.intValue("limit", in: arguments) ?? 25
                return try Self.renderJSON(
                    await JeffDAVClient.listEvents(
                        accountID: accountID,
                        calendarURL: calendarURL,
                        daysBack: daysBack,
                        daysForward: daysForward,
                        limit: limit
                    )
                )
            }
        )
    }

    private func calendarFindFreeTimeTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "calendar_find_free_time",
                description: "Find available calendar slots by subtracting CalDAV busy events from a requested time window. Use before proposing meeting times or checking availability.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional DAV account ID. Defaults to all calendar-capable accounts."],
                        "calendar_url": ["type": "string", "description": "Optional explicit CalDAV calendar collection URL."],
                        "window_start": ["type": "string", "description": "ISO-8601 start of the search window."],
                        "window_end": ["type": "string", "description": "ISO-8601 end of the search window."],
                        "duration_minutes": ["type": "integer", "description": "Minimum slot length. Defaults to 30."],
                        "timezone": ["type": "string", "description": "IANA timezone, defaults to the runtime timezone."],
                        "day_start_hour": ["type": "integer", "description": "Local hour to start considering availability, default 9."],
                        "day_end_hour": ["type": "integer", "description": "Local hour to stop considering availability, default 17."],
                        "limit": ["type": "integer", "description": "Maximum slots to return, capped at 50."],
                    ],
                    "required": ["window_start", "window_end"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                let accountID = try Self.optionalString("account_id", in: arguments)
                let calendarURL = try Self.optionalString("calendar_url", in: arguments)
                let windowStart = try Self.requiredString("window_start", in: arguments)
                let windowEnd = try Self.requiredString("window_end", in: arguments)
                let durationMinutes = try Self.intValue("duration_minutes", in: arguments) ?? 30
                let timezone = try Self.optionalString("timezone", in: arguments)
                let dayStartHour = try Self.intValue("day_start_hour", in: arguments) ?? 9
                let dayEndHour = try Self.intValue("day_end_hour", in: arguments) ?? 17
                let limit = try Self.intValue("limit", in: arguments) ?? 8
                return try Self.renderJSON(
                    await JeffDAVClient.findFreeTime(
                        accountID: accountID,
                        calendarURL: calendarURL,
                        windowStart: windowStart,
                        windowEnd: windowEnd,
                        durationMinutes: durationMinutes,
                        timezoneIdentifier: timezone,
                        dayStartHour: dayStartHour,
                        dayEndHour: dayEndHour,
                        limit: limit
                    )
                )
            }
        )
    }

    private func calendarCreateEventTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "calendar_create_event",
                description: "Create a calendar event through CalDAV. Only call after explicit confirmation of the calendar/account, title, start, end, location, and notes.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional DAV account ID."],
                        "calendar_url": ["type": "string", "description": "Optional explicit CalDAV calendar collection URL."],
                        "title": ["type": "string"],
                        "start": ["type": "string", "description": "ISO-8601 start date/time."],
                        "end": ["type": "string", "description": "ISO-8601 end date/time."],
                        "location": ["type": "string"],
                        "notes": ["type": "string"],
                        "confirmed": ["type": "boolean", "description": "Must be true only after explicit user confirmation."],
                    ],
                    "required": ["title", "start", "end", "confirmed"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                guard try Self.boolValue("confirmed", in: arguments) == true else {
                    throw RootToolboxError.invalidArgument(key: "confirmed", expected: "true after explicit user confirmation")
                }
                let accountID = try Self.optionalString("account_id", in: arguments)
                let calendarURL = try Self.optionalString("calendar_url", in: arguments)
                let title = try Self.requiredString("title", in: arguments)
                let start = try Self.requiredString("start", in: arguments)
                let end = try Self.requiredString("end", in: arguments)
                let location = try Self.optionalString("location", in: arguments)
                let notes = try Self.optionalString("notes", in: arguments)
                return try Self.renderJSON(
                    try await JeffDAVClient.createEvent(
                        accountID: accountID,
                        calendarURL: calendarURL,
                        title: title,
                        start: start,
                        end: end,
                        location: location,
                        notes: notes
                    )
                )
            }
        )
    }

    private func calendarDeleteEventTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "calendar_delete_event",
                description: "Delete a calendar event by CalDAV event URL. Only call after explicit user confirmation.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional DAV account ID."],
                        "event_url": ["type": "string"],
                        "confirmed": ["type": "boolean", "description": "Must be true only after explicit user confirmation."],
                    ],
                    "required": ["event_url", "confirmed"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                guard try Self.boolValue("confirmed", in: arguments) == true else {
                    throw RootToolboxError.invalidArgument(key: "confirmed", expected: "true after explicit user confirmation")
                }
                let accountID = try Self.optionalString("account_id", in: arguments)
                let eventURL = try Self.requiredString("event_url", in: arguments)
                return try Self.renderJSON(try await JeffDAVClient.deleteEvent(accountID: accountID, eventURL: eventURL))
            }
        )
    }

    private func contactsSearchTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "contacts_search",
                description: "Search configured CardDAV address books for people, emails, and phone numbers. Use this for identity/contact resolution before sending messages or emails.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional DAV account ID. Defaults to all CardDAV-capable accounts."],
                        "addressbook_url": ["type": "string", "description": "Optional explicit CardDAV address book URL."],
                        "query": ["type": "string", "description": "Search text. Empty string lists a bounded set from address books."],
                        "limit": ["type": "integer", "description": "Maximum contacts to return, capped at 50."],
                    ],
                    "required": ["query"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                let accountID = try Self.optionalString("account_id", in: arguments)
                let addressbookURL = try Self.optionalString("addressbook_url", in: arguments)
                let query = try Self.requiredString("query", in: arguments)
                let limit = try Self.intValue("limit", in: arguments) ?? 10
                return try Self.renderJSON(
                    await JeffDAVClient.searchContacts(
                        accountID: accountID,
                        addressbookURL: addressbookURL,
                        query: query,
                        limit: limit
                    )
                )
            }
        )
    }

    private func contactsCreateTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "contacts_create",
                description: "Create a CardDAV contact. Only call after explicit confirmation of the account/address book, name, email addresses, phone numbers, and notes.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional DAV account ID."],
                        "addressbook_url": ["type": "string", "description": "Optional explicit CardDAV address book URL."],
                        "full_name": ["type": "string"],
                        "emails": ["type": "array", "items": ["type": "string"]],
                        "phones": ["type": "array", "items": ["type": "string"]],
                        "organization": ["type": "string"],
                        "title": ["type": "string"],
                        "notes": ["type": "string"],
                        "confirmed": ["type": "boolean", "description": "Must be true only after explicit user confirmation."],
                    ],
                    "required": ["full_name", "confirmed"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                guard try Self.boolValue("confirmed", in: arguments) == true else {
                    throw RootToolboxError.invalidArgument(key: "confirmed", expected: "true after explicit user confirmation")
                }
                let accountID = try Self.optionalString("account_id", in: arguments)
                let addressbookURL = try Self.optionalString("addressbook_url", in: arguments)
                let fullName = try Self.requiredString("full_name", in: arguments)
                let emails = try Self.stringArray("emails", in: arguments)
                let phones = try Self.stringArray("phones", in: arguments)
                let organization = try Self.optionalString("organization", in: arguments)
                let title = try Self.optionalString("title", in: arguments)
                let notes = try Self.optionalString("notes", in: arguments)
                return try Self.renderJSON(
                    try await JeffDAVClient.createContact(
                        accountID: accountID,
                        addressbookURL: addressbookURL,
                        fullName: fullName,
                        emails: emails,
                        phones: phones,
                        organization: organization,
                        title: title,
                        notes: notes
                    )
                )
            }
        )
    }

    private func webDAVListFilesTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "webdav_list_files",
                description: "List files/folders from a configured WebDAV account, useful for lightweight notes/files storage.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional DAV account ID."],
                        "path": ["type": "string", "description": "Optional relative path."],
                        "limit": ["type": "integer", "description": "Maximum entries to return, capped at 100."],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                let accountID = try Self.optionalString("account_id", in: arguments)
                let path = try Self.optionalString("path", in: arguments)
                let limit = try Self.intValue("limit", in: arguments) ?? 25
                return try Self.renderJSON(try await JeffDAVClient.listFiles(accountID: accountID, path: path, limit: limit))
            }
        )
    }

    private func webDAVPutTextFileTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "webdav_put_text_file",
                description: "Write a text/markdown note or file to a configured WebDAV account. Only call after explicit user confirmation.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Optional DAV account ID."],
                        "path": ["type": "string", "description": "Relative file path such as notes/2026-04-28.md."],
                        "text": ["type": "string"],
                        "content_type": ["type": "string", "description": "Defaults to text/markdown; charset=utf-8."],
                        "confirmed": ["type": "boolean", "description": "Must be true only after explicit user confirmation."],
                    ],
                    "required": ["path", "text", "confirmed"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                guard try Self.boolValue("confirmed", in: arguments) == true else {
                    throw RootToolboxError.invalidArgument(key: "confirmed", expected: "true after explicit user confirmation")
                }
                let accountID = try Self.optionalString("account_id", in: arguments)
                let path = try Self.requiredString("path", in: arguments)
                let text = try Self.requiredString("text", in: arguments)
                let contentType = try Self.optionalString("content_type", in: arguments) ?? "text/markdown; charset=utf-8"
                return try Self.renderJSON(try await JeffDAVClient.putTextFile(accountID: accountID, path: path, text: text, contentType: contentType))
            }
        )
    }

    private func memorySearchTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "memory_search",
                description: "Search the Vault TrueMemory-backed memory layer for preferences, mood signals, active projects, interests, relationships, routines, facts, corrections, and summaries.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string"],
                        "kinds": [
                            "type": "array",
                            "items": [
                                "type": "string",
                                "enum": ["preference", "mood_signal", "active_project", "interest", "relationship", "routine", "fact", "correction", "summary"],
                            ],
                        ],
                        "entities": ["type": "array", "items": ["type": "string"]],
                        "limit": ["type": "integer", "description": "Maximum memories to return, capped at 30."],
                    ],
                    "required": ["query"],
                    "additionalProperties": false,
                ]
            ),
            executor: { arguments, _ in
                let query = try Self.requiredString("query", in: arguments)
                let kinds = try Self.stringArray("kinds", in: arguments)
                let entities = try Self.stringArray("entities", in: arguments)
                let limit = try Self.intValue("limit", in: arguments) ?? 8
                return try Self.renderJSON(
                    try await VaultMemoryClient.search(
                        query: query,
                        kinds: kinds,
                        entities: entities,
                        limit: limit
                    )
                )
            }
        )
    }

    private func dailyBriefingSnapshotTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "daily_briefing_snapshot",
                description: "Collect a bounded EA briefing snapshot: upcoming calendar events, recent human email candidates, pending draft actions, active scheduled prompts, and optional Vault memory context.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "days_forward": ["type": "integer", "description": "Calendar lookahead in days, capped at 14. Defaults to 2."],
                        "include_calendar": ["type": "boolean"],
                        "include_email": ["type": "boolean"],
                        "email_limit_per_account": ["type": "integer", "description": "Recent messages to scan per account, capped at 25. Defaults to 8."],
                        "include_pending_drafts": ["type": "boolean"],
                        "include_schedules": ["type": "boolean"],
                        "include_memory": ["type": "boolean"],
                        "memory_query": ["type": "string", "description": "Optional Vault memory query for current priorities/preferences."],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [scheduledPromptStore, draftActionStore] arguments, _ in
                let daysForward = try Self.intValue("days_forward", in: arguments) ?? 2
                let includeCalendar = try Self.boolValue("include_calendar", in: arguments) ?? true
                let includeEmail = try Self.boolValue("include_email", in: arguments) ?? true
                let emailLimit = try Self.intValue("email_limit_per_account", in: arguments) ?? 8
                let includePendingDrafts = try Self.boolValue("include_pending_drafts", in: arguments) ?? true
                let includeSchedules = try Self.boolValue("include_schedules", in: arguments) ?? true
                let includeMemory = try Self.boolValue("include_memory", in: arguments) ?? true
                let memoryQuery = try Self.optionalString("memory_query", in: arguments)
                    ?? "Navan active projects current priorities preferences mood routines relationships"

                var snapshot: [String: Any] = [
                    "generated_at": Self.iso8601String(Date()),
                ]

                if includeCalendar {
                    let calendar = await JeffDAVClient.listEvents(
                        accountID: nil,
                        calendarURL: nil,
                        daysBack: 0,
                        daysForward: max(1, min(daysForward, 14)),
                        limit: 30
                    )
                    snapshot["calendar"] = calendar
                    var summaryHints = snapshot["summary_hints"] as? [String: Any] ?? [:]
                    summaryHints["calendar_events"] = Self.briefingCalendarHints(from: calendar, limit: 5)
                    snapshot["summary_hints"] = summaryHints
                }

                if includeEmail {
                    do {
                        let email = try await JeffEmailClient.triageNeedsReply(
                            accountIDs: nil,
                            mailbox: "INBOX",
                            limitPerAccount: max(1, min(emailLimit, 25))
                        )
                        snapshot["email_needs_reply"] = email
                        var summaryHints = snapshot["summary_hints"] as? [String: Any] ?? [:]
                        summaryHints["email_followups"] = Self.briefingEmailHints(from: email, limit: 5)
                        snapshot["summary_hints"] = summaryHints
                    } catch {
                        snapshot["email_error"] = String(describing: error)
                    }
                }

                if includePendingDrafts, let draftActionStore {
                    do {
                        snapshot["pending_draft_actions"] = try await draftActionStore
                            .list(status: .pendingConfirmation, limit: 10)
                            .map(Self.serialize(draftAction:))
                    } catch {
                        snapshot["pending_draft_actions_error"] = String(describing: error)
                    }
                }

                if includeSchedules, let scheduledPromptStore {
                    do {
                        snapshot["active_scheduled_prompts"] = try await scheduledPromptStore
                            .prompts(status: .active)
                            .prefix(20)
                            .map(Self.serialize(scheduledPrompt:))
                    } catch {
                        snapshot["active_scheduled_prompts_error"] = String(describing: error)
                    }
                }

                if includeMemory {
                    do {
                        snapshot["vault_memory"] = try await VaultMemoryClient.search(
                            query: memoryQuery,
                            kinds: [],
                            entities: [],
                            limit: 8
                        )
                    } catch {
                        snapshot["vault_memory_error"] = String(describing: error)
                    }
                }

                return try Self.renderJSON(snapshot)
            }
        )
    }

    private static func briefingCalendarHints(from calendar: [String: Any], limit: Int) -> [[String: Any]] {
        guard let accounts = calendar["accounts"] as? [[String: Any]] else {
            return []
        }
        var events: [[String: Any]] = []
        for account in accounts {
            let accountID = account["account_id"] as? String
            for event in account["events"] as? [[String: Any]] ?? [] {
                let summary = event["summary"] as? String
                let start = event["start"] as? String
                let calendarName = event["calendar"] as? String
                let eventAccountID = event["account_id"] as? String
                var hint: [String: Any] = [:]
                hint["summary"] = summary ?? NSNull()
                hint["start"] = start ?? NSNull()
                hint["display_time"] = start.flatMap(Self.briefingDisplayTime) ?? NSNull()
                hint["calendar"] = calendarName ?? NSNull()
                hint["account_id"] = accountID ?? eventAccountID ?? NSNull()
                events.append(hint)
            }
        }
        return events
            .sorted { String(describing: $0["start"] ?? "") < String(describing: $1["start"] ?? "") }
            .prefix(max(1, limit))
            .map { $0 }
    }

    private static func briefingEmailHints(from email: [String: Any], limit: Int) -> [[String: Any]] {
        guard let accounts = email["accounts"] as? [[String: Any]] else {
            return []
        }
        var candidates: [[String: Any]] = []
        for account in accounts {
            let accountID = account["account_id"] as? String
            let accountEmail = account["email"] as? String
            for candidate in account["candidates"] as? [[String: Any]] ?? [] {
                let candidateAccountID = candidate["account_id"] as? String
                var hint: [String: Any] = [:]
                hint["from"] = candidate["from"] as? String ?? NSNull()
                hint["subject"] = candidate["subject"] as? String ?? NSNull()
                hint["date"] = candidate["date"] as? String ?? NSNull()
                hint["why"] = candidate["why_might_need_reply"] as? String ?? NSNull()
                hint["account_id"] = accountID ?? candidateAccountID ?? NSNull()
                hint["account_email"] = accountEmail ?? NSNull()
                candidates.append(hint)
            }
        }
        return candidates
            .sorted { String(describing: $0["date"] ?? "") > String(describing: $1["date"] ?? "") }
            .prefix(max(1, limit))
            .map { $0 }
    }

    private static func briefingDisplayTime(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let localTimezone = Self.defaultUserTimeZone()
        let formats: [(String, TimeZone)] = [
            ("yyyyMMdd'T'HHmmss'Z'", TimeZone(secondsFromGMT: 0) ?? localTimezone),
            ("yyyyMMdd'T'HHmmss", localTimezone),
            ("yyyyMMdd", localTimezone),
        ]
        for (format, timezone) in formats {
            let parser = DateFormatter()
            parser.calendar = Calendar(identifier: .gregorian)
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = timezone
            parser.dateFormat = format
            guard let date = parser.date(from: trimmed) else {
                continue
            }
            let display = DateFormatter()
            display.calendar = Calendar(identifier: .gregorian)
            display.locale = Locale(identifier: "en_US_POSIX")
            display.timeZone = localTimezone
            display.dateFormat = trimmed.count == 8 ? "EEE, MMM d" : "h:mm a"
            return display.string(from: date).lowercased()
        }
        return nil
    }

    private static func defaultUserTimeZone() -> TimeZone {
        let environment = ProcessInfo.processInfo.environment
        for key in ["OMNIKIT_LOCAL_TIMEZONE", "TZ"] {
            if let value = environment[key],
               let timezone = TimeZone(identifier: value) {
                return timezone
            }
        }
        return TimeZone.current
    }

    private func channelSendMessageTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "channel_send_message",
                description: "Send user-visible text through the current channel as a typed SendMessage side effect. Use this for every text reply to the user; final assistant text alone is not delivered by ingress.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "text": [
                            "type": "string",
                            "description": "User-visible message text to send.",
                        ],
                        "transport": [
                            "type": "string",
                            "description": "Optional transport override such as imessage, telegram, api, or custom.",
                        ],
                        "target_external_id": [
                            "type": "string",
                            "description": "Optional channel-native target ID. Defaults to the current channel target.",
                        ],
                    ],
                    "required": ["text"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let text = try Self.requiredString("text", in: arguments)
                let transport = try Self.transportValue("transport", in: arguments)
                let targetExternalID = try Self.optionalString("target_external_id", in: arguments)
                let result = try await ChannelActionRegistry.shared.sendMessage(
                    sessionID: server.sessionID,
                    transport: transport,
                    targetExternalID: targetExternalID,
                    text: text,
                    metadata: [
                        "side_effect": ChannelSideEffectKind.sendMessage.rawValue,
                    ]
                )
                return try Self.renderJSON(Self.serialize(channelActionResult: result))
            }
        )
    }

    private func channelSendArtifactTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "channel_send_artifact",
                description: "Send a stored artifact, such as an image, through the current channel as a typed channel side effect.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "artifact_id": [
                            "type": "string",
                            "description": "Artifact ID to send.",
                        ],
                        "caption": [
                            "type": "string",
                            "description": "Optional short caption to send with the artifact.",
                        ],
                        "transport": [
                            "type": "string",
                            "description": "Optional transport override such as imessage.",
                        ],
                        "target_external_id": [
                            "type": "string",
                            "description": "Optional channel-native target ID. Defaults to the current channel target.",
                        ],
                    ],
                    "required": ["artifact_id"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let artifactID = try Self.requiredString("artifact_id", in: arguments)
                let caption = try Self.optionalString("caption", in: arguments)
                let transport = try Self.transportValue("transport", in: arguments)
                let targetExternalID = try Self.optionalString("target_external_id", in: arguments)
                let artifact = try await server.artifactRecord(artifactID: artifactID)
                let result = try await ChannelActionRegistry.shared.sendArtifact(
                    sessionID: server.sessionID,
                    transport: transport,
                    targetExternalID: targetExternalID,
                    artifactID: artifactID,
                    caption: caption,
                    metadata: [
                        "artifact_name": artifact.name,
                        "artifact_content_type": artifact.contentType,
                    ]
                )
                return try Self.renderJSON([
                    "side_effect": Self.serialize(channelActionResult: result),
                    "artifact": Self.serialize(artifact: artifact),
                ])
            }
        )
    }

    private func imageGenerateTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "image_generate",
                description: "Generate an image from a text prompt using the configured OpenAI Image API, store it as an artifact, and optionally send it through the current channel.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "prompt": [
                            "type": "string",
                            "description": "Image generation prompt.",
                        ],
                        "model": [
                            "type": "string",
                            "description": "Optional image model. Defaults to gpt-image-1.",
                        ],
                        "size": [
                            "type": "string",
                            "description": "Optional size such as 1024x1024, 1024x1536, or 1536x1024.",
                        ],
                        "quality": [
                            "type": "string",
                            "description": "Optional quality such as low, medium, or high.",
                        ],
                        "send": [
                            "type": "boolean",
                            "description": "Whether to send the generated image through the current channel. Defaults false.",
                        ],
                        "caption": [
                            "type": "string",
                            "description": "Optional caption to send with the image when send=true.",
                        ],
                    ],
                    "required": ["prompt"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let prompt = try Self.requiredString("prompt", in: arguments)
                let model = try Self.optionalString("model", in: arguments) ?? "gpt-image-1"
                let size = try Self.optionalString("size", in: arguments)
                let quality = try Self.optionalString("quality", in: arguments)
                let shouldSend = try Self.boolValue("send", in: arguments) ?? false
                let caption = try Self.optionalString("caption", in: arguments)
                let generated = try await Self.generateImage(
                    prompt: prompt,
                    model: model,
                    size: size,
                    quality: quality
                )
                let artifact = try await server.storeArtifact(
                    name: generated.fileName,
                    contentType: generated.contentType,
                    data: generated.data
                )

                let sendResult: ChannelActionResult?
                if shouldSend {
                    sendResult = try await ChannelActionRegistry.shared.sendArtifact(
                        sessionID: server.sessionID,
                        transport: nil,
                        targetExternalID: nil,
                        artifactID: artifact.artifactID,
                        caption: caption,
                        metadata: [
                            "generated_by": "image_generate",
                            "artifact_name": artifact.name,
                            "artifact_content_type": artifact.contentType,
                        ]
                    )
                } else {
                    sendResult = nil
                }

                return try Self.renderJSON([
                    "artifact": Self.serialize(artifact: artifact),
                    "revised_prompt": generated.revisedPrompt ?? NSNull(),
                    "sent": sendResult.map(Self.serialize(channelActionResult:)) ?? NSNull(),
                ])
            }
        )
    }

    private func imageEditTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "image_edit",
                description: "Edit an existing image artifact using the configured OpenAI Image API, store the result as a new artifact, and optionally send it through the current channel.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "artifact_id": [
                            "type": "string",
                            "description": "Image artifact ID to edit.",
                        ],
                        "prompt": [
                            "type": "string",
                            "description": "Edit instruction for the image.",
                        ],
                        "model": [
                            "type": "string",
                            "description": "Optional image model. Defaults to gpt-image-1.",
                        ],
                        "size": [
                            "type": "string",
                            "description": "Optional output size such as 1024x1024, 1024x1536, or 1536x1024.",
                        ],
                        "quality": [
                            "type": "string",
                            "description": "Optional quality such as low, medium, or high.",
                        ],
                        "send": [
                            "type": "boolean",
                            "description": "Whether to send the edited image through the current channel. Defaults false.",
                        ],
                        "caption": [
                            "type": "string",
                            "description": "Optional caption to send with the image when send=true.",
                        ],
                    ],
                    "required": ["artifact_id", "prompt"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let artifactID = try Self.requiredString("artifact_id", in: arguments)
                let prompt = try Self.requiredString("prompt", in: arguments)
                let model = try Self.optionalString("model", in: arguments) ?? "gpt-image-1"
                let size = try Self.optionalString("size", in: arguments)
                let quality = try Self.optionalString("quality", in: arguments)
                let shouldSend = try Self.boolValue("send", in: arguments) ?? false
                let caption = try Self.optionalString("caption", in: arguments)
                let sourceRecord = try await server.artifactRecord(artifactID: artifactID)
                let sourceData = try await server.artifactData(artifactID: artifactID)
                let generated = try await Self.editImage(
                    prompt: prompt,
                    model: model,
                    sourceName: sourceRecord.name,
                    sourceContentType: sourceRecord.contentType,
                    sourceData: sourceData,
                    size: size,
                    quality: quality
                )
                let artifact = try await server.storeArtifact(
                    name: generated.fileName,
                    contentType: generated.contentType,
                    data: generated.data
                )

                let sendResult: ChannelActionResult?
                if shouldSend {
                    sendResult = try await ChannelActionRegistry.shared.sendArtifact(
                        sessionID: server.sessionID,
                        transport: nil,
                        targetExternalID: nil,
                        artifactID: artifact.artifactID,
                        caption: caption,
                        metadata: [
                            "generated_by": "image_edit",
                            "source_artifact_id": artifactID,
                            "artifact_name": artifact.name,
                            "artifact_content_type": artifact.contentType,
                        ]
                    )
                } else {
                    sendResult = nil
                }

                return try Self.renderJSON([
                    "artifact": Self.serialize(artifact: artifact),
                    "source_artifact": Self.serialize(artifact: sourceRecord),
                    "revised_prompt": generated.revisedPrompt ?? NSNull(),
                    "sent": sendResult.map(Self.serialize(channelActionResult:)) ?? NSNull(),
                ])
            }
        )
    }

    private func imageDownloadTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "image_download",
                description: "Download an image from an http(s) URL, store it as an artifact, and optionally send it through the current channel.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "url": [
                            "type": "string",
                            "description": "Direct http(s) URL for the image to download.",
                        ],
                        "name": [
                            "type": "string",
                            "description": "Optional artifact filename. Defaults to the URL or server-suggested filename.",
                        ],
                        "send": [
                            "type": "boolean",
                            "description": "Whether to send the downloaded image through the current channel after storing it. Defaults false.",
                        ],
                        "caption": [
                            "type": "string",
                            "description": "Optional caption to send with the image when send=true.",
                        ],
                        "transport": [
                            "type": "string",
                            "description": "Optional transport override such as imessage.",
                        ],
                        "target_external_id": [
                            "type": "string",
                            "description": "Optional channel-native target ID. Defaults to the current channel target.",
                        ],
                    ],
                    "required": ["url"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let urlString = try Self.requiredString("url", in: arguments)
                let requestedName = try Self.optionalString("name", in: arguments)
                let shouldSend = try Self.boolValue("send", in: arguments) ?? false
                let caption = try Self.optionalString("caption", in: arguments)
                let transport = try Self.transportValue("transport", in: arguments)
                let targetExternalID = try Self.optionalString("target_external_id", in: arguments)
                let downloaded = try await Self.downloadImage(urlString: urlString)
                let artifact = try await server.storeArtifact(
                    name: requestedName ?? downloaded.fileName,
                    contentType: downloaded.contentType,
                    data: downloaded.data
                )

                let sendResult: ChannelActionResult?
                if shouldSend {
                    sendResult = try await ChannelActionRegistry.shared.sendArtifact(
                        sessionID: server.sessionID,
                        transport: transport,
                        targetExternalID: targetExternalID,
                        artifactID: artifact.artifactID,
                        caption: caption,
                        metadata: [
                            "source_url": urlString,
                            "artifact_name": artifact.name,
                            "artifact_content_type": artifact.contentType,
                        ]
                    )
                } else {
                    sendResult = nil
                }

                return try Self.renderJSON([
                    "artifact": Self.serialize(artifact: artifact),
                    "source_url": urlString,
                    "sent": sendResult.map(Self.serialize(channelActionResult:)) ?? NSNull(),
                ])
            }
        )
    }

    private func noResponseTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "no_response",
                description: "Mark the current inbound event as handled silently with no user-visible response. Use for irrelevant automation events, noisy notifications, or cases where silence is intentional.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "reason": [
                            "type": "string",
                            "description": "Short internal reason for not replying.",
                        ],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let reason = try Self.optionalString("reason", in: arguments)
                let result = try await ChannelActionRegistry.shared.noResponse(
                    sessionID: server.sessionID,
                    reason: reason
                )
                return try Self.renderJSON(Self.serialize(channelActionResult: result))
            }
        )
    }

    private func channelReactTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "channel_react",
                description: "Send an explicit reaction through the current channel when the transport supports reactions. Defaults target/message to the current inbound event.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "transport": [
                            "type": "string",
                            "description": "Optional transport override such as imessage, telegram, api, or custom.",
                        ],
                        "target_external_id": [
                            "type": "string",
                            "description": "Channel-native target ID. Defaults to the current channel target.",
                        ],
                        "message_id": [
                            "type": "string",
                            "description": "Channel-native message ID to react to. Defaults to the current inbound message.",
                        ],
                        "reaction": [
                            "type": "string",
                            "description": "Reaction such as love, like, dislike, laugh, emphasize, question, or a transport-supported custom reaction.",
                        ],
                        "part_index": [
                            "type": "integer",
                            "description": "Message part index, default 0.",
                        ],
                        "emoji": [
                            "type": "string",
                            "description": "Optional emoji for custom reactions when the transport supports it.",
                        ],
                    ],
                    "required": ["reaction"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let transport = try Self.transportValue("transport", in: arguments)
                let targetExternalID = try Self.optionalString("target_external_id", in: arguments)
                let messageID = try Self.optionalString("message_id", in: arguments)
                let reaction = try Self.requiredString("reaction", in: arguments)
                let partIndex = try Self.intValue("part_index", in: arguments) ?? 0
                let emoji = try Self.optionalString("emoji", in: arguments)
                let result = try await ChannelActionRegistry.shared.react(
                    sessionID: server.sessionID,
                    transport: transport,
                    targetExternalID: targetExternalID,
                    messageID: messageID,
                    reaction: reaction,
                    partIndex: partIndex,
                    emoji: emoji
                )
                return try Self.renderJSON(Self.serialize(channelActionResult: result))
            }
        )
    }

    private func channelSetReplyEffectTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "channel_set_reply_effect",
                description: "Apply an explicit channel-native effect to the next normal reply in the current channel when supported. If the user only asks to set an effect, call no_response after this so the confirmation text does not consume the effect.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "transport": [
                            "type": "string",
                            "description": "Optional transport override such as imessage.",
                        ],
                        "target_external_id": [
                            "type": "string",
                            "description": "Channel-native target ID. Defaults to the current channel target.",
                        ],
                        "effect_id": [
                            "type": "string",
                            "description": "Channel-native effect identifier. For iMessage, use com.apple.messages.effect.CKSpotlightEffect for screen/spotlight effects and com.apple.MobileSMS.effect.impact for impact effects.",
                        ],
                    ],
                    "required": ["effect_id"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server] arguments, _ in
                let transport = try Self.transportValue("transport", in: arguments)
                let targetExternalID = try Self.optionalString("target_external_id", in: arguments)
                let effectID = try Self.requiredString("effect_id", in: arguments)
                let result = try await ChannelActionRegistry.shared.setPendingReplyEffect(
                    sessionID: server.sessionID,
                    transport: transport,
                    targetExternalID: targetExternalID,
                    effectID: effectID
                )
                return try Self.renderJSON(Self.serialize(channelActionResult: result))
            }
        )
    }

    private func displayDraftTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "display_draft",
                description: "Create durable draft-and-consent state before an external or irreversible action. The draft is shown to the user and must be approved before execution.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "draft_body": [
                            "type": "string",
                            "description": "Draft content or action plan to show the user.",
                        ],
                        "action_kind": [
                            "type": "string",
                            "description": "Action class, e.g. email, calendar, file, payment, deploy, message, custom.",
                        ],
                        "action_type": [
                            "type": "string",
                            "description": "Optional executable action type such as email_send, email_reply, calendar_create_event, calendar_delete_event, contacts_create, or webdav_put_text_file.",
                        ],
                        "action_payload": [
                            "type": "object",
                            "description": "Optional structured payload for draft_action_execute. Match the eventual tool arguments except omit confirmed.",
                            "additionalProperties": true,
                        ],
                        "target_description": [
                            "type": "string",
                            "description": "Human-readable target or integration this draft would affect.",
                        ],
                        "sensitive": [
                            "type": "boolean",
                            "description": "Whether approval should use sensitive-action delivery policy. Defaults true.",
                        ],
                    ],
                    "required": ["title", "draft_body", "action_kind"],
                    "additionalProperties": true,
                ]
            ),
            executor: { [server, draftActionStore] arguments, _ in
                let title = try Self.requiredString("title", in: arguments)
                let draftBody = try Self.requiredString("draft_body", in: arguments)
                let actionKind = try Self.requiredString("action_kind", in: arguments)
                let actionType = try Self.optionalString("action_type", in: arguments)
                let actionPayload = try Self.jsonObjectValue("action_payload", in: arguments)
                let targetDescription = try Self.optionalString("target_description", in: arguments)
                let sensitive = try Self.boolValue("sensitive", in: arguments) ?? true
                var metadata = try Self.stringDictionary(excluding: [
                    "title",
                    "draft_body",
                    "action_kind",
                    "action_type",
                    "action_payload",
                    "target_description",
                    "sensitive",
                ], in: arguments)
                let context = await ChannelActionRegistry.shared.currentContext(sessionID: server.sessionID)
                let draftAction = try await draftActionStore?.create(
                    sourceSessionID: server.sessionID,
                    title: title,
                    draftBody: draftBody,
                    actionKind: actionKind,
                    actionType: actionType,
                    targetDescription: targetDescription,
                    payload: actionPayload,
                    channelTransport: context?.transport.rawValue,
                    channelTargetExternalID: context?.targetExternalID,
                    actorExternalID: context?.actorExternalID
                )
                metadata.merge([
                    "side_effect": ChannelSideEffectKind.displayDraft.rawValue,
                    "consent_state": "draft_shown",
                    "draft_id": draftAction?.draftID ?? "",
                    "action_kind": actionKind,
                    "action_type": actionType ?? "",
                    "draft_body": draftBody,
                    "target_description": targetDescription ?? "",
                ]) { _, new in new }
                let approval = try await server.requestApprovalPrompt(
                    title: title,
                    prompt: draftBody,
                    sensitive: sensitive,
                    metadata: metadata
                )
                return try Self.renderJSON([
                    "side_effect": ChannelSideEffectKind.displayDraft.rawValue,
                    "consent_state": "draft_shown",
                    "draft_action": draftAction.map(Self.serialize(draftAction:)) ?? NSNull(),
                    "approval": Self.serialize(approval: approval),
                ])
            }
        )
    }

    private func draftActionListTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "draft_action_list",
                description: "List durable draft actions, especially pending confirmations. Use when the user says to send, execute, approve, cancel, or revise a previously shown draft.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "status": [
                            "type": "string",
                            "enum": DraftActionStatus.allCases.map(\.rawValue),
                        ],
                        "limit": ["type": "integer"],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [draftActionStore] arguments, _ in
                guard let draftActionStore else {
                    throw RootToolboxError.invalidArgument(key: "draft_action_list", expected: "draft action store to be configured")
                }
                let status = try Self.draftActionStatus("status", in: arguments)
                let limit = try Self.intValue("limit", in: arguments) ?? 20
                let drafts = try await draftActionStore.list(status: status, limit: limit)
                return try Self.renderJSON([
                    "draft_actions": drafts.map(Self.serialize(draftAction:)),
                ])
            }
        )
    }

    private func draftActionCancelTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "draft_action_cancel",
                description: "Cancel a pending durable draft action by draft_id after the user asks to cancel or discard it.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "draft_id": ["type": "string"],
                    ],
                    "required": ["draft_id"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [draftActionStore] arguments, _ in
                guard let draftActionStore else {
                    throw RootToolboxError.invalidArgument(key: "draft_action_cancel", expected: "draft action store to be configured")
                }
                let draftID = try Self.requiredString("draft_id", in: arguments)
                guard let draft = try await draftActionStore.cancel(draftID) else {
                    throw RootToolboxError.invalidArgument(key: "draft_id", expected: "existing draft_id")
                }
                return try Self.renderJSON([
                    "draft_action": Self.serialize(draftAction: draft),
                ])
            }
        )
    }

    private func draftActionExecuteTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "draft_action_execute",
                description: "Execute a pending durable draft action after explicit user confirmation. Supports email_send, email_reply, calendar_create_event, calendar_delete_event, contacts_create, and webdav_put_text_file payloads.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "draft_id": ["type": "string"],
                        "confirmed": [
                            "type": "boolean",
                            "description": "Must be true only after explicit user confirmation.",
                        ],
                    ],
                    "required": ["draft_id", "confirmed"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [draftActionStore] arguments, _ in
                guard let draftActionStore else {
                    throw RootToolboxError.invalidArgument(key: "draft_action_execute", expected: "draft action store to be configured")
                }
                guard try Self.boolValue("confirmed", in: arguments) == true else {
                    throw RootToolboxError.invalidArgument(key: "confirmed", expected: "true after explicit user confirmation")
                }
                let draftID = try Self.requiredString("draft_id", in: arguments)
                guard let draft = try await draftActionStore.get(draftID) else {
                    throw RootToolboxError.invalidArgument(key: "draft_id", expected: "existing draft_id")
                }
                guard draft.status == .pendingConfirmation else {
                    throw RootToolboxError.invalidArgument(key: "draft_id", expected: "pending_confirmation draft")
                }

                do {
                    let result = try await Self.executeDraftAction(draft)
                    let jsonResult = (try? JSONValue(result)) ?? .object([:])
                    let updated = try await draftActionStore.markExecuted(draftID, result: jsonResult) ?? draft
                    return try Self.renderJSON([
                        "side_effect": ChannelSideEffectKind.executeDraft.rawValue,
                        "draft_action": Self.serialize(draftAction: updated),
                        "execution_result": result,
                    ])
                } catch {
                    _ = try? await draftActionStore.recordFailure(draftID, reason: String(describing: error))
                    throw error
                }
            }
        )
    }

    private func schedulePromptTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "schedule_prompt",
                description: "Create a durable future turn in this same channel. Use reminder only when the future turn should notify the user with stored text. Use scheduled_task when the future turn must perform work with tools before replying. After this succeeds for a human request, call channel_send_message with a short confirmation; raw final text is not delivered.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "Short user-facing label for the reminder or scheduled task.",
                        ],
                        "prompt": [
                            "type": "string",
                            "description": "Detailed instruction to run when the schedule fires. For scheduled_task, write executable instructions: what to check/search/fetch/do, what tools may be needed, and what result to send back. Do not phrase executable work as a reminder.",
                        ],
                        "first_fire_at": [
                            "type": "string",
                            "description": "First fire time as an absolute ISO-8601 timestamp with timezone offset.",
                        ],
                        "timezone": [
                            "type": "string",
                            "description": "IANA timezone for recurrence calculations, e.g. America/Los_Angeles.",
                        ],
                        "recurrence": [
                            "type": "string",
                            "description": "none, daily, weekdays, weekly, or monthly.",
                        ],
                        "kind": [
                            "type": "string",
                            "description": "reminder means notify-only with no work; scheduled_task means perform work/checks/searches/tool calls before deciding what to send.",
                        ],
                    ],
                    "required": ["title", "prompt", "first_fire_at"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [server, scheduledPromptStore] arguments, _ in
                guard let scheduledPromptStore else {
                    throw RootToolboxError.invalidArgument(key: "schedule_prompt", expected: "scheduled prompt store to be configured")
                }
                guard let context = await ChannelActionRegistry.shared.currentContext(sessionID: server.sessionID) else {
                    throw ChannelActionRegistryError.missingCurrentContext(sessionID: server.sessionID)
                }

                let title = try Self.requiredString("title", in: arguments)
                let prompt = try Self.requiredString("prompt", in: arguments)
                let firstFireAt = try Self.dateValue("first_fire_at", in: arguments)
                let timezone = try Self.optionalString("timezone", in: arguments) ?? TimeZone.current.identifier
                let recurrence = try Self.scheduledRecurrence("recurrence", in: arguments) ?? .none
                let kind = try Self.optionalString("kind", in: arguments)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "reminder"
                let eventKind = kind == "scheduled_task" ? "automation_event" : "notification"
                let rawActorExternalID = context.actorExternalID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let fallbackActorExternalID = context.actorID?.rawValue ?? "unknown"
                let record = ScheduledPromptRecord(
                    scheduleID: "schedule.\(UUID().uuidString)",
                    createdBySessionID: server.sessionID,
                    transport: context.transport,
                    actorExternalID: rawActorExternalID.isEmpty ? fallbackActorExternalID : rawActorExternalID,
                    actorDisplayName: context.actorDisplayName,
                    channelExternalID: context.targetExternalID,
                    channelKind: context.channelKind,
                    title: title,
                    prompt: prompt,
                    eventKind: eventKind,
                    recurrence: recurrence,
                    timezoneIdentifier: timezone,
                    nextFireAt: firstFireAt,
                    metadata: [
                        "kind": kind,
                        "created_from_inbound_event_kind": context.inboundEventKind,
                    ]
                )
                let stored = try await scheduledPromptStore.save(record)
                return try Self.renderJSON(Self.serialize(scheduledPrompt: stored))
            }
        )
    }

    private func listScheduledPromptsTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "list_scheduled_prompts",
                description: "List durable reminders and scheduled tasks for this agent.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "status": [
                            "type": "string",
                            "description": "Optional status filter: active, completed, or cancelled.",
                        ],
                    ],
                    "additionalProperties": false,
                ]
            ),
            executor: { [scheduledPromptStore] arguments, _ in
                guard let scheduledPromptStore else {
                    throw RootToolboxError.invalidArgument(key: "list_scheduled_prompts", expected: "scheduled prompt store to be configured")
                }
                let status = try Self.scheduledStatus("status", in: arguments)
                let prompts = try await scheduledPromptStore.prompts(status: status)
                return try Self.renderJSON([
                    "scheduled_prompts": prompts.map(Self.serialize(scheduledPrompt:)),
                ])
            }
        )
    }

    private func cancelScheduledPromptTool() -> RegisteredTool {
        RegisteredTool(
            definition: AgentToolDefinition(
                name: "cancel_scheduled_prompt",
                description: "Cancel a durable reminder or scheduled task by schedule_id.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "schedule_id": ["type": "string"],
                    ],
                    "required": ["schedule_id"],
                    "additionalProperties": false,
                ]
            ),
            executor: { [scheduledPromptStore] arguments, _ in
                guard let scheduledPromptStore else {
                    throw RootToolboxError.invalidArgument(key: "cancel_scheduled_prompt", expected: "scheduled prompt store to be configured")
                }
                let scheduleID = try Self.requiredString("schedule_id", in: arguments)
                guard let record = try await scheduledPromptStore.cancel(scheduleID: scheduleID, at: Date()) else {
                    throw RootToolboxError.invalidArgument(key: "schedule_id", expected: "existing schedule_id")
                }
                return try Self.renderJSON(Self.serialize(scheduledPrompt: record))
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

extension RootAgentToolbox {
    struct GeneratedImage: Sendable {
        var data: Data
        var contentType: String
        var fileName: String
        var revisedPrompt: String?
    }

    struct DownloadedImage: Sendable {
        var data: Data
        var contentType: String
        var fileName: String
    }

    struct MultipartPart: Sendable {
        var name: String
        var fileName: String?
        var contentType: String?
        var data: Data
    }

    struct CodexImageAuth: Sendable {
        var accessToken: String
        var accountID: String?
        var installationID: String?
    }

    static func generateImage(
        prompt: String,
        model: String,
        size: String?,
        quality: String?
    ) async throws -> GeneratedImage {
        if let auth = try? loadCodexImageAuth() {
            do {
                return try await generateImageWithCodexAuth(
                    prompt: prompt,
                    sourceImage: nil,
                    requestedModel: model,
                    size: size,
                    quality: quality,
                    auth: auth,
                    fallbackName: "generated-image.png"
                )
            } catch {
                if !hasUsableImageAPIKey() {
                    throw error
                }
            }
        }

        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "output_format": "png",
            "n": 1,
        ]
        if let size {
            body["size"] = size
        }
        if let quality {
            body["quality"] = quality
        }
        let response = try await postImageAPIJSON(path: "/images/generations", body: body)
        return try await generatedImage(from: response, fallbackName: "generated-image.png")
    }

    static func editImage(
        prompt: String,
        model: String,
        sourceName: String,
        sourceContentType: String,
        sourceData: Data,
        size: String?,
        quality: String?
    ) async throws -> GeneratedImage {
        guard isImageContentType(sourceContentType) else {
            throw RootToolboxError.invalidArgument(key: "artifact_id", expected: "image artifact")
        }
        if let auth = try? loadCodexImageAuth() {
            do {
                return try await generateImageWithCodexAuth(
                    prompt: prompt,
                    sourceImage: (data: sourceData, contentType: sourceContentType),
                    requestedModel: model,
                    size: size,
                    quality: quality,
                    auth: auth,
                    fallbackName: "edited-image.png"
                )
            } catch {
                if !hasUsableImageAPIKey() {
                    throw error
                }
            }
        }

        var parts: [MultipartPart] = [
            MultipartPart(name: "model", fileName: nil, contentType: nil, data: Data(model.utf8)),
            MultipartPart(name: "prompt", fileName: nil, contentType: nil, data: Data(prompt.utf8)),
            MultipartPart(name: "output_format", fileName: nil, contentType: nil, data: Data("png".utf8)),
            MultipartPart(
                name: "image",
                fileName: safeFileName(sourceName),
                contentType: sourceContentType,
                data: sourceData
            ),
        ]
        if let size {
            parts.append(MultipartPart(name: "size", fileName: nil, contentType: nil, data: Data(size.utf8)))
        }
        if let quality {
            parts.append(MultipartPart(name: "quality", fileName: nil, contentType: nil, data: Data(quality.utf8)))
        }
        let response = try await postImageAPIMultipart(path: "/images/edits", parts: parts)
        return try await generatedImage(from: response, fallbackName: "edited-image.png")
    }

    public static func describeImage(
        data: Data,
        contentType: String,
        name: String? = nil
    ) async throws -> String {
        guard isImageContentType(contentType) else {
            throw RootToolboxError.invalidArgument(key: "content_type", expected: "image content type")
        }
        let auth = try loadCodexImageAuth()
        let descriptionModel = ProcessInfo.processInfo.environment["OMNIKIT_IMAGE_DESCRIPTION_CODEX_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = descriptionModel?.isEmpty == false ? descriptionModel! : "gpt-5.4-mini"
        let body: [String: Any] = [
            "model": resolvedModel,
            "instructions": """
            Describe the supplied image for a non-vision orchestrator that may need to answer questions or edit it later.
            Include visible text/OCR, layout, key objects, style, and whether it appears to be a meme, screenshot, photo, or diagram.
            Be concise and factual. Return only the description.
            """,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": "Describe this image\(name.map { " named \($0)" } ?? "").",
                        ],
                        [
                            "type": "input_image",
                            "image_url": "data:\(contentType);base64,\(data.base64EncodedString())",
                            "detail": "high",
                        ],
                    ],
                ],
            ],
            "store": false,
            "stream": true,
        ]
        let response = try await postCodexImageResponse(body: body, auth: auth)
        let description = try textFromCodexSSE(response)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            throw RootToolboxError.imageAPI("Codex image description completed without text.")
        }
        return description
    }

    static func generateImageWithCodexAuth(
        prompt: String,
        sourceImage: (data: Data, contentType: String)?,
        requestedModel: String,
        size: String?,
        quality: String?,
        auth: CodexImageAuth,
        fallbackName: String
    ) async throws -> GeneratedImage {
        let imageModel = ProcessInfo.processInfo.environment["OMNIKIT_IMAGE_CODEX_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = imageModel?.isEmpty == false ? imageModel! : "gpt-5.3-codex"
        let sizeText = size.map { " Size: \($0)." } ?? ""
        let qualityText = quality.map { " Quality: \($0)." } ?? ""
        var content: [[String: Any]] = [
            [
                "type": "input_text",
                "text": "\(prompt)\(sizeText)\(qualityText)",
            ],
        ]
        if let sourceImage {
            content.append([
                "type": "input_image",
                "image_url": "data:\(sourceImage.contentType);base64,\(sourceImage.data.base64EncodedString())",
                "detail": "high",
            ])
        }
        var body: [String: Any] = [
            "model": resolvedModel,
            "instructions": sourceImage == nil
                ? "Use the image_generation tool to generate exactly one image. Return no extra prose."
                : "Use the image_generation tool to edit the provided image according to the prompt. Return no extra prose.",
            "input": [
                [
                    "role": "user",
                    "content": content,
                ],
            ],
            "tools": [
                [
                    "type": "image_generation",
                    "output_format": "png",
                ],
            ],
            "tool_choice": "auto",
            "store": false,
            "stream": true,
        ]
        if let installationID = auth.installationID {
            body["client_metadata"] = [
                "x-codex-installation-id": installationID,
            ]
        }
        _ = requestedModel
        let response = try await postCodexImageResponse(body: body, auth: auth)
        return try generatedImageFromCodexSSE(response, fallbackName: fallbackName)
    }

    static func postCodexImageResponse(
        body: [String: Any],
        auth: CodexImageAuth
    ) async throws -> String {
        let base = ProcessInfo.processInfo.environment["OMNIKIT_CODEX_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBase = base?.isEmpty == false ? base! : "https://chatgpt.com/backend-api/codex"
        let normalizedBase = resolvedBase.hasSuffix("/") ? String(resolvedBase.dropLast()) : resolvedBase
        guard let url = URL(string: normalizedBase + "/responses") else {
            throw RootToolboxError.imageAPI("Invalid Codex image generation URL.")
        }
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("swift_omnikit", forHTTPHeaderField: "originator")
        request.setValue("swift-omnikit-image-\(UUID().uuidString)", forHTTPHeaderField: "session_id")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        request.httpBody = bodyData
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(statusCode) else {
            throw RootToolboxError.imageAPI(text.isEmpty ? "Codex image generation failed with status \(statusCode)." : text)
        }
        return text
    }

    static func generatedImageFromCodexSSE(
        _ text: String,
        fallbackName: String
    ) throws -> GeneratedImage {
        var latestImageItem: [String: Any]?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("data: ") else {
                continue
            }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                continue
            }
            if let item = event["item"] as? [String: Any],
               item["type"] as? String == "image_generation_call",
               item["result"] is String {
                latestImageItem = item
            }
            if let response = event["response"] as? [String: Any],
               let output = response["output"] as? [[String: Any]] {
                for item in output where item["type"] as? String == "image_generation_call" && item["result"] is String {
                    latestImageItem = item
                }
            }
        }
        guard let latestImageItem,
              let base64 = latestImageItem["result"] as? String,
              let imageData = Data(base64Encoded: base64) else {
            throw RootToolboxError.imageAPI("Codex image generation completed without image bytes.")
        }
        return GeneratedImage(
            data: imageData,
            contentType: "image/png",
            fileName: fallbackName,
            revisedPrompt: latestImageItem["revised_prompt"] as? String
        )
    }

    static func textFromCodexSSE(_ text: String) throws -> String {
        var streamedText = ""
        var finalTexts: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("data: ") else {
                continue
            }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                continue
            }
            if let delta = event["delta"] as? String {
                streamedText += delta
            }
            if let item = event["item"] as? [String: Any] {
                finalTexts.append(contentsOf: outputTexts(from: item))
            }
            if let response = event["response"] as? [String: Any],
               let output = response["output"] as? [[String: Any]] {
                let texts = output.flatMap(outputTexts(from:))
                if !texts.isEmpty {
                    finalTexts = texts
                }
            }
        }
        if let final = finalTexts.last, !final.isEmpty {
            return final
        }
        return streamedText
    }

    static func outputTexts(from item: [String: Any]) -> [String] {
        guard let content = item["content"] as? [[String: Any]] else {
            return []
        }
        return content.compactMap { part in
            guard let type = part["type"] as? String,
                  type == "output_text" || type == "text" else {
                return nil
            }
            return part["text"] as? String
        }
    }

    static func loadCodexImageAuth(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CodexImageAuth {
        let codexHome = environment["CODEX_HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
        let authURL = codexHome.appending(path: "auth.json", directoryHint: .notDirectory)
        let data = try Data(contentsOf: authURL)
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RootToolboxError.imageAPI("Codex auth.json does not contain a ChatGPT access token.")
        }
        let installationIDURL = codexHome.appending(path: "installation_id", directoryHint: .notDirectory)
        let installationID = (try? String(contentsOf: installationIDURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexImageAuth(
            accessToken: accessToken,
            accountID: tokens["account_id"] as? String,
            installationID: installationID?.isEmpty == false ? installationID : nil
        )
    }

    static func hasUsableImageAPIKey(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let key = try? imageAPIKey(environment: environment) else {
            return false
        }
        return key.hasPrefix("sk-") || key.hasPrefix("sess-")
    }

    static func postImageAPIJSON(path: String, body: [String: Any]) async throws -> [String: Any] {
        let apiKey = try imageAPIKey()
        let url = try imageAPIURL(path: path)
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        return try await sendImageAPIRequest(request)
    }

    static func postImageAPIMultipart(path: String, parts: [MultipartPart]) async throws -> [String: Any] {
        let apiKey = try imageAPIKey()
        let url = try imageAPIURL(path: path)
        let boundary = "omnikit-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(parts: parts, boundary: boundary)
        return try await sendImageAPIRequest(request)
    }

    static func sendImageAPIRequest(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
        guard (200..<300).contains(statusCode) else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? String(data: data, encoding: .utf8)
                ?? "OpenAI Image API request failed with status \(statusCode)"
            throw RootToolboxError.imageAPI(message)
        }
        guard let json else {
            throw RootToolboxError.imageAPI("OpenAI Image API returned a non-JSON response.")
        }
        return json
    }

    static func generatedImage(
        from response: [String: Any],
        fallbackName: String
    ) async throws -> GeneratedImage {
        guard let dataItems = response["data"] as? [[String: Any]],
              let first = dataItems.first else {
            throw RootToolboxError.imageAPI("OpenAI Image API response did not include image data.")
        }
        let revisedPrompt = first["revised_prompt"] as? String
        if let base64 = first["b64_json"] as? String,
           let data = Data(base64Encoded: base64) {
            return GeneratedImage(
                data: data,
                contentType: "image/png",
                fileName: fallbackName,
                revisedPrompt: revisedPrompt
            )
        }
        if let urlString = first["url"] as? String {
            let downloaded = try await downloadImage(urlString: urlString)
            return GeneratedImage(
                data: downloaded.data,
                contentType: downloaded.contentType,
                fileName: downloaded.fileName,
                revisedPrompt: revisedPrompt
            )
        }
        throw RootToolboxError.imageAPI("OpenAI Image API response did not include b64_json or url.")
    }

    static func imageAPIKey(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        for key in ["OMNIKIT_IMAGE_OPENAI_API_KEY", "THE_AGENT_IMAGE_OPENAI_API_KEY", "OPENAI_API_KEY", "DR_OPENAI_API_KEY"] {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        throw RootToolboxError.invalidArgument(key: "OPENAI_API_KEY", expected: "configured OpenAI API key for image tools")
    }

    static func imageAPIURL(
        path: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        let configuredBase = environment["OMNIKIT_IMAGE_OPENAI_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = configuredBase?.isEmpty == false ? configuredBase! : "https://api.openai.com/v1"
        let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: normalizedBase + path) else {
            throw RootToolboxError.invalidArgument(key: "OMNIKIT_IMAGE_OPENAI_BASE_URL", expected: "valid URL")
        }
        return url
    }

    static func multipartBody(parts: [MultipartPart], boundary: String) -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        for part in parts {
            append("--\(boundary)\(lineBreak)")
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let fileName = part.fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            append(disposition + lineBreak)
            if let contentType = part.contentType {
                append("Content-Type: \(contentType)\(lineBreak)")
            }
            append(lineBreak)
            body.append(part.data)
            append(lineBreak)
        }
        append("--\(boundary)--\(lineBreak)")
        return body
    }

    static func downloadImage(urlString: String) async throws -> DownloadedImage {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw RootToolboxError.invalidArgument(key: "url", expected: "http(s) image URL")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard data.count <= 50 * 1_024 * 1_024 else {
            throw RootToolboxError.invalidArgument(key: "url", expected: "image payload at or below 50MB")
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw RootToolboxError.invalidArgument(key: "url", expected: "successful 2xx image response")
        }

        let responseContentType = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";", maxSplits: 1)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let inferredContentType = contentType(forPathExtension: url.pathExtension)
        let contentType = responseContentType ?? inferredContentType ?? "application/octet-stream"
        guard isImageContentType(contentType) || inferredContentType != nil else {
            throw RootToolboxError.invalidArgument(key: "url", expected: "image content type")
        }

        let suggestedName = response.suggestedFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlName = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackExtension = fileExtension(forContentType: contentType) ?? "img"
        let fileName = [suggestedName, urlName]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty }) ?? "downloaded-image.\(fallbackExtension)"
        return DownloadedImage(
            data: data,
            contentType: contentType,
            fileName: fileName
        )
    }

    static func isImageContentType(_ contentType: String) -> Bool {
        contentType.lowercased().hasPrefix("image/")
    }

    static func safeFileName(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "image.png" : trimmed
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let sanitized = String(fallback.map { allowed.contains($0) ? $0 : "_" })
        return sanitized.isEmpty ? "image.png" : sanitized
    }

    static func contentType(forPathExtension pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        case "tif", "tiff":
            return "image/tiff"
        default:
            return nil
        }
    }

    static func fileExtension(forContentType contentType: String) -> String? {
        switch contentType.lowercased() {
        case "image/png":
            return "png"
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/heic":
            return "heic"
        case "image/heif":
            return "heif"
        case "image/tiff":
            return "tiff"
        default:
            return nil
        }
    }

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

    static func tpuExperimentOperation(_ key: String, in arguments: [String: Any]) throws -> TPUExperimentOperation {
        let rawValue = try requiredString(key, in: arguments)
        guard let operation = TPUExperimentOperation(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            throw RootToolboxError.invalidArgument(
                key: key,
                expected: "inspect_status, compare_best_runs, evaluate_best_checkpoint, export_best_validation_samples, rerun_best_known_config, or improve_singing_results"
            )
        }
        return operation
    }

    static func transportValue(_ key: String, in arguments: [String: Any]) throws -> ChannelBinding.Transport? {
        guard let rawValue = try optionalString(key, in: arguments) else {
            return nil
        }
        guard let transport = ChannelBinding.Transport(rawValue: rawValue.lowercased()) else {
            throw RootToolboxError.invalidArgument(key: key, expected: "local, telegram, imessage, http, api, test, or custom")
        }
        return transport
    }

    static func scheduledRecurrence(_ key: String, in arguments: [String: Any]) throws -> ScheduledPromptRecurrence? {
        guard let rawValue = try optionalString(key, in: arguments) else {
            return nil
        }
        guard let recurrence = ScheduledPromptRecurrence(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            throw RootToolboxError.invalidArgument(key: key, expected: "none, daily, weekdays, weekly, or monthly")
        }
        return recurrence
    }

    static func scheduledStatus(_ key: String, in arguments: [String: Any]) throws -> ScheduledPromptStatus? {
        guard let rawValue = try optionalString(key, in: arguments) else {
            return nil
        }
        guard let status = ScheduledPromptStatus(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            throw RootToolboxError.invalidArgument(key: key, expected: "active, completed, or cancelled")
        }
        return status
    }

    static func draftActionStatus(_ key: String, in arguments: [String: Any]) throws -> DraftActionStatus? {
        guard let rawValue = try optionalString(key, in: arguments) else {
            return nil
        }
        guard let status = DraftActionStatus(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            throw RootToolboxError.invalidArgument(key: key, expected: DraftActionStatus.allCases.map(\.rawValue).joined(separator: ", "))
        }
        return status
    }

    static func jsonObjectValue(_ key: String, in arguments: [String: Any]) throws -> JSONValue? {
        guard let value = arguments[key] else {
            return nil
        }
        let json = try JSONValue(value)
        guard case .object = json else {
            throw RootToolboxError.invalidArgument(key: key, expected: "JSON object")
        }
        return json
    }

    static func dateValue(_ key: String, in arguments: [String: Any]) throws -> Date {
        let rawValue = try requiredString(key, in: arguments)
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: trimmed) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: trimmed) {
            return date
        }
        throw RootToolboxError.invalidArgument(key: key, expected: "absolute ISO-8601 timestamp with timezone")
    }

    static func installationScope(_ key: String, in arguments: [String: Any]) throws -> SkillInstallationRecord.Scope? {
        guard let rawValue = try optionalString(key, in: arguments) else {
            return nil
        }
        guard let scope = SkillInstallationRecord.Scope(rawValue: rawValue.lowercased()) else {
            throw RootToolboxError.invalidArgument(key: key, expected: "system, workspace, or mission")
        }
        return scope
    }

    static func activationScope(_ key: String, in arguments: [String: Any]) throws -> SkillActivationRecord.Scope? {
        guard let rawValue = try optionalString(key, in: arguments) else {
            return nil
        }
        guard let scope = SkillActivationRecord.Scope(rawValue: rawValue.lowercased()) else {
            throw RootToolboxError.invalidArgument(key: key, expected: "system, workspace, or mission")
        }
        return scope
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

    static func executeDraftAction(_ draft: DraftActionRecord) async throws -> [String: Any] {
        let actionType = normalizedDraftActionType(draft.actionType ?? draft.actionKind)
        let payload = try payloadObject(for: draft)

        switch actionType {
        case "email_send":
            let to = try payloadStringArray("to", in: payload)
            guard !to.isEmpty else {
                throw RootToolboxError.invalidArgument(key: "action_payload.to", expected: "at least one recipient")
            }
            return try await JeffEmailClient.send(
                accountID: try payloadOptionalString("account_id", in: payload),
                to: to,
                cc: try payloadStringArray("cc", in: payload),
                bcc: try payloadStringArray("bcc", in: payload),
                subject: try payloadRequiredString("subject", in: payload),
                body: try payloadRequiredString("body", in: payload)
            )
        case "email_reply":
            return try await JeffEmailClient.reply(
                accountID: try payloadOptionalString("account_id", in: payload),
                mailbox: try payloadOptionalString("mailbox", in: payload) ?? "INBOX",
                uid: try payloadRequiredString("uid", in: payload),
                body: try payloadRequiredString("body", in: payload),
                cc: try payloadStringArray("cc", in: payload),
                bcc: try payloadStringArray("bcc", in: payload),
                replyAll: try payloadBool("reply_all", in: payload) ?? false
            )
        case "calendar_create_event":
            return try await JeffDAVClient.createEvent(
                accountID: try payloadOptionalString("account_id", in: payload),
                calendarURL: try payloadOptionalString("calendar_url", in: payload),
                title: try payloadRequiredString("title", in: payload),
                start: try payloadRequiredString("start", in: payload),
                end: try payloadRequiredString("end", in: payload),
                location: try payloadOptionalString("location", in: payload),
                notes: try payloadOptionalString("notes", in: payload)
            )
        case "calendar_delete_event":
            return try await JeffDAVClient.deleteEvent(
                accountID: try payloadOptionalString("account_id", in: payload),
                eventURL: try payloadRequiredString("event_url", in: payload)
            )
        case "contacts_create":
            return try await JeffDAVClient.createContact(
                accountID: try payloadOptionalString("account_id", in: payload),
                addressbookURL: try payloadOptionalString("addressbook_url", in: payload),
                fullName: try payloadRequiredString("full_name", in: payload),
                emails: try payloadStringArray("emails", in: payload),
                phones: try payloadStringArray("phones", in: payload),
                organization: try payloadOptionalString("organization", in: payload),
                title: try payloadOptionalString("title", in: payload),
                notes: try payloadOptionalString("notes", in: payload)
            )
        case "webdav_put_text_file":
            return try await JeffDAVClient.putTextFile(
                accountID: try payloadOptionalString("account_id", in: payload),
                path: try payloadRequiredString("path", in: payload),
                text: try payloadRequiredString("text", in: payload),
                contentType: try payloadOptionalString("content_type", in: payload) ?? "text/markdown; charset=utf-8"
            )
        default:
            throw RootToolboxError.invalidArgument(
                key: "action_type",
                expected: "email_send, email_reply, calendar_create_event, calendar_delete_event, contacts_create, or webdav_put_text_file"
            )
        }
    }

    static func normalizedDraftActionType(_ rawValue: String) -> String {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        switch normalized {
        case "send_email", "outbound_email":
            return "email_send"
        case "reply_email":
            return "email_reply"
        case "calendar_event", "create_calendar_event":
            return "calendar_create_event"
        case "delete_calendar_event":
            return "calendar_delete_event"
        case "create_contact", "contact_create", "carddav_create_contact":
            return "contacts_create"
        case "note", "notes", "file", "webdav_note":
            return "webdav_put_text_file"
        default:
            return normalized
        }
    }

    static func payloadObject(for draft: DraftActionRecord) throws -> [String: JSONValue] {
        guard let payload = draft.payload,
              let object = payload.objectValue else {
            throw RootToolboxError.invalidArgument(key: "action_payload", expected: "JSON object")
        }
        return object
    }

    static func payloadRequiredString(_ key: String, in payload: [String: JSONValue]) throws -> String {
        guard let value = try payloadOptionalString(key, in: payload), !value.isEmpty else {
            throw RootToolboxError.missingRequiredArgument("action_payload.\(key)")
        }
        return value
    }

    static func payloadOptionalString(_ key: String, in payload: [String: JSONValue]) throws -> String? {
        guard let value = payload[key] else {
            return nil
        }
        let string: String
        switch value {
        case .string(let raw):
            string = raw
        case .number(let raw):
            string = raw.rounded() == raw ? String(Int(raw)) : String(raw)
        case .bool(let raw):
            string = raw ? "true" : "false"
        case .null:
            return nil
        case .array, .object:
            throw RootToolboxError.invalidArgument(key: "action_payload.\(key)", expected: "string")
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func payloadStringArray(_ key: String, in payload: [String: JSONValue]) throws -> [String] {
        guard let value = payload[key] else {
            return []
        }
        switch value {
        case .array(let values):
            return try values.compactMap { item in
                guard case .string(let string) = item else {
                    throw RootToolboxError.invalidArgument(key: "action_payload.\(key)", expected: "array of strings")
                }
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        case .string(let string):
            return string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        case .null:
            return []
        case .bool, .number, .object:
            throw RootToolboxError.invalidArgument(key: "action_payload.\(key)", expected: "array of strings")
        }
    }

    static func payloadBool(_ key: String, in payload: [String: JSONValue]) throws -> Bool? {
        guard let value = payload[key] else {
            return nil
        }
        switch value {
        case .bool(let bool):
            return bool
        case .number(let number):
            return number != 0
        case .string(let string):
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                throw RootToolboxError.invalidArgument(key: "action_payload.\(key)", expected: "boolean")
            }
        case .null:
            return nil
        case .array, .object:
            throw RootToolboxError.invalidArgument(key: "action_payload.\(key)", expected: "boolean")
        }
    }

    static func jsonFoundationObject(_ value: JSONValue?) -> Any {
        guard let value else {
            return NSNull()
        }
        return (try? value.asFoundationObject()) ?? NSNull()
    }

    static func serialize(draftAction: DraftActionRecord) -> [String: Any] {
        [
            "draft_id": draftAction.draftID,
            "source_session_id": draftAction.sourceSessionID,
            "title": draftAction.title,
            "draft_body": draftAction.draftBody,
            "action_kind": draftAction.actionKind,
            "action_type": draftAction.actionType ?? NSNull(),
            "target_description": draftAction.targetDescription ?? NSNull(),
            "payload": jsonFoundationObject(draftAction.payload),
            "status": draftAction.status.rawValue,
            "created_at": iso8601String(draftAction.createdAt),
            "updated_at": iso8601String(draftAction.updatedAt),
            "executed_at": draftAction.executedAt.map(iso8601String) ?? NSNull(),
            "cancelled_at": draftAction.cancelledAt.map(iso8601String) ?? NSNull(),
            "failure_reason": draftAction.failureReason ?? NSNull(),
            "execution_result": jsonFoundationObject(draftAction.executionResult),
            "channel_transport": draftAction.channelTransport ?? NSNull(),
            "channel_target_external_id": draftAction.channelTargetExternalID ?? NSNull(),
            "actor_external_id": draftAction.actorExternalID ?? NSNull(),
        ]
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
            "metadata": task.metadata,
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

    static func serialize(skillStatus: SkillStatusSnapshot) -> [String: Any] {
        [
            "installed": skillStatus.installed.map(serialize(installation:)),
            "activations": skillStatus.activations.map(serialize(activation:)),
            "projection": serialize(projection: skillStatus.projection),
        ]
    }

    static func serialize(skillOperation: SkillOperationResult) -> [String: Any] {
        [
            "installation": skillOperation.installation.map(serialize(installation:)) ?? NSNull(),
            "activation": skillOperation.activation.map(serialize(activation:)) ?? NSNull(),
            "approval_request": skillOperation.approvalRequest.map(serialize(approval:)) ?? NSNull(),
            "projection": serialize(projection: skillOperation.projection),
        ]
    }

    static func serialize(installation: SkillInstallationRecord) -> [String: Any] {
        [
            "installation_id": installation.installationID,
            "skill_id": installation.skillID,
            "version": installation.version,
            "scope": installation.scope.rawValue,
            "workspace_id": installation.workspaceID?.rawValue ?? NSNull(),
            "source_type": installation.sourceType.rawValue,
            "source_path": installation.sourcePath,
            "installed_path": installation.installedPath,
            "digest": installation.digest,
            "metadata": installation.metadata,
        ]
    }

    static func serialize(activation: SkillActivationRecord) -> [String: Any] {
        [
            "activation_id": activation.activationID,
            "installation_id": activation.installationID ?? NSNull(),
            "skill_id": activation.skillID,
            "version": activation.version ?? NSNull(),
            "scope": activation.scope.rawValue,
            "root_session_id": activation.rootSessionID,
            "mission_id": activation.missionID ?? NSNull(),
            "status": activation.status.rawValue,
            "reason": activation.reason,
            "approval_request_id": activation.approvalRequestID ?? NSNull(),
            "metadata": activation.metadata,
        ]
    }

    static func serialize(projection: OmniSkillProjectionBundle) -> [String: Any] {
        [
            "active_skills": projection.activeSkills.map { skill in
                [
                    "skill_id": skill.skillID,
                    "version": skill.version,
                    "display_name": skill.displayName,
                    "summary": skill.summary,
                ]
            },
            "prompt_overlay": projection.promptOverlay,
            "codergen_overlay": projection.codergenOverlay,
            "attractor_overlay": projection.attractorOverlay,
            "required_capabilities": projection.requiredCapabilities,
            "allowed_domains": projection.allowedDomains,
            "preferred_model_tier": projection.preferredModelTier ?? NSNull(),
            "shell_skills": projection.shellSkills.map { skill in
                [
                    "name": skill.name,
                    "description": skill.description,
                    "path": skill.path,
                ]
            },
            "worker_tools": projection.workerTools.map { tool in
                [
                    "skill_id": tool.skillID,
                    "name": tool.name,
                    "description": tool.description,
                ]
            },
        ]
    }

    static func serialize(doctorReport: DoctorReport) -> [String: Any] {
        [
            "workspace_id": doctorReport.workspaceID,
            "channel_bindings": doctorReport.channelBindings,
            "pending_pairings": doctorReport.pendingPairings,
            "registered_workers": doctorReport.registeredWorkers,
            "stale_workers": doctorReport.staleWorkers,
            "stalled_tasks": doctorReport.stalledTasks,
            "installed_skills": doctorReport.installedSkills,
            "active_skill_activations": doctorReport.activeSkillActivations,
            "active_missions": doctorReport.activeMissions,
            "deferred_deliveries": doctorReport.deferredDeliveries,
            "route_tiers": doctorReport.routeTiers,
            "warnings": doctorReport.warnings,
            "summary_text": doctorReport.summaryText,
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

    static func serialize(artifact: ArtifactRecord) -> [String: Any] {
        [
            "artifact_id": artifact.artifactID,
            "task_id": artifact.taskID ?? NSNull(),
            "mission_id": artifact.missionID ?? NSNull(),
            "workspace_id": artifact.workspaceID?.rawValue ?? NSNull(),
            "channel_id": artifact.channelID?.rawValue ?? NSNull(),
            "name": artifact.name,
            "relative_path": artifact.relativePath,
            "content_type": artifact.contentType,
            "byte_count": artifact.byteCount,
            "created_at": iso8601String(artifact.createdAt),
        ]
    }

    static func serialize(artifactRead: RootArtifactReadResult) -> [String: Any] {
        [
            "record": serialize(artifact: artifactRead.record),
            "text": artifactRead.text ?? NSNull(),
            "truncated": artifactRead.truncated,
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
            "delivery": serialize(deliveryMetadata: mission.metadata),
            "metadata": mission.metadata,
            "created_at": iso8601String(mission.createdAt),
            "updated_at": iso8601String(mission.updatedAt),
            "completed_at": mission.completedAt.map(Self.iso8601String) ?? NSNull(),
        ]
    }

    static func serialize(tpuMissionTemplate: TPUExperimentMissionTemplate) -> [String: Any] {
        [
            "operation": tpuMissionTemplate.operation.rawValue,
            "skill_ids": tpuMissionTemplate.skillIDs,
            "request": [
                "title": tpuMissionTemplate.request.title,
                "brief": tpuMissionTemplate.request.brief,
                "execution_mode": tpuMissionTemplate.request.executionMode?.rawValue ?? NSNull(),
                "capability_requirements": tpuMissionTemplate.request.capabilityRequirements,
                "expected_outputs": tpuMissionTemplate.request.expectedOutputs,
                "constraints": tpuMissionTemplate.request.constraints,
                "priority": tpuMissionTemplate.request.priority,
                "budget_units": tpuMissionTemplate.request.budgetUnits,
                "max_recursion_depth": tpuMissionTemplate.request.maxRecursionDepth ?? NSNull(),
                "require_approval": tpuMissionTemplate.request.requireApproval,
                "approval_prompt": tpuMissionTemplate.request.approvalPrompt ?? NSNull(),
                "metadata": tpuMissionTemplate.request.metadata,
            ],
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

    static func serialize(channelActionResult result: ChannelActionResult) -> [String: Any] {
        [
            "side_effect": result.sideEffect.rawValue,
            "transport": result.transport.rawValue,
            "target_external_id": result.targetExternalID,
            "message_id": result.messageID ?? NSNull(),
            "metadata": result.metadata,
        ]
    }

    static func serialize(scheduledPrompt record: ScheduledPromptRecord) -> [String: Any] {
        [
            "schedule_id": record.scheduleID,
            "created_by_session_id": record.createdBySessionID,
            "transport": record.transport.rawValue,
            "actor_external_id": record.actorExternalID,
            "channel_external_id": record.channelExternalID,
            "channel_kind": record.channelKind,
            "title": record.title,
            "prompt": record.prompt,
            "event_kind": record.eventKind,
            "recurrence": record.recurrence.rawValue,
            "timezone": record.timezoneIdentifier,
            "status": record.status.rawValue,
            "next_fire_at": record.nextFireAt.map(Self.iso8601String) ?? NSNull(),
            "last_fired_at": record.lastFiredAt.map(Self.iso8601String) ?? NSNull(),
            "fire_count": record.fireCount,
            "metadata": record.metadata,
            "created_at": iso8601String(record.createdAt),
            "updated_at": iso8601String(record.updatedAt),
        ]
    }

    static func serialize(deliveryMetadata metadata: [String: String]) -> [String: Any] {
        let service = metadata["delivery_service"] ?? metadata["service"]
        return [
            "mode": metadata["delivery_mode"] ?? NSNull(),
            "service": service ?? NSNull(),
            "target_environment": metadata["deploy_target"] ?? NSNull(),
            "deploy_approval_required": metadata["deploy_approval_required"] ?? NSNull(),
            "auto_rollout_eligible": metadata["auto_rollout_eligible"] ?? NSNull(),
            "release_bundle_id": metadata["release_bundle_id"] ?? NSNull(),
            "release_id": metadata["release_id"] ?? NSNull(),
            "deployment_state": metadata["deployment_state"] ?? NSNull(),
            "health_status": metadata["health_status"] ?? NSNull(),
            "delivery_summary": metadata["delivery_summary"] ?? NSNull(),
            "release_generation": metadata["release_generation"] ?? NSNull(),
            "rollback_release_id": metadata["rollback_release_id"] ?? NSNull(),
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
    case imageAPI(String)

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
        case .imageAPI(let message):
            return "Image API error: \(message)"
        }
    }
}
