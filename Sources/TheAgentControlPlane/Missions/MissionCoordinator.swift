import Foundation
import OmniAgentMesh

public struct MissionStartRequest: Sendable, Equatable {
    public var title: String
    public var brief: String
    public var executionMode: MissionRecord.ExecutionMode?
    public var capabilityRequirements: [String]
    public var expectedOutputs: [String]
    public var constraints: [String]
    public var priority: Int
    public var budgetUnits: Int
    public var maxRecursionDepth: Int?
    public var requireApproval: Bool
    public var approvalPrompt: String?
    public var metadata: [String: String]

    public init(
        title: String,
        brief: String,
        executionMode: MissionRecord.ExecutionMode? = nil,
        capabilityRequirements: [String] = [],
        expectedOutputs: [String] = [],
        constraints: [String] = [],
        priority: Int = 0,
        budgetUnits: Int = 1,
        maxRecursionDepth: Int? = nil,
        requireApproval: Bool = false,
        approvalPrompt: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.title = title
        self.brief = brief
        self.executionMode = executionMode
        self.capabilityRequirements = capabilityRequirements
        self.expectedOutputs = expectedOutputs
        self.constraints = constraints
        self.priority = priority
        self.budgetUnits = budgetUnits
        self.maxRecursionDepth = maxRecursionDepth
        self.requireApproval = requireApproval
        self.approvalPrompt = approvalPrompt
        self.metadata = metadata
    }
}

public struct MissionStatusSnapshot: Sendable, Equatable {
    public var mission: MissionRecord
    public var stages: [MissionStageRecord]
    public var task: TaskRecord?
    public var approvals: [ApprovalRequestRecord]
    public var questions: [QuestionRequestRecord]
    public var recentEvents: [TaskEvent]

    public init(
        mission: MissionRecord,
        stages: [MissionStageRecord],
        task: TaskRecord?,
        approvals: [ApprovalRequestRecord],
        questions: [QuestionRequestRecord],
        recentEvents: [TaskEvent]
    ) {
        self.mission = mission
        self.stages = stages
        self.task = task
        self.approvals = approvals
        self.questions = questions
        self.recentEvents = recentEvents
    }
}

public enum MissionCoordinatorError: Error, CustomStringConvertible {
    case missionNotFound(String)
    case stageNotFound(String)
    case activeMissionLimitExceeded(workspaceID: WorkspaceID, limit: Int)

    public var description: String {
        switch self {
        case .missionNotFound(let missionID):
            return "Mission \(missionID) was not found."
        case .stageNotFound(let stageID):
            return "Mission stage \(stageID) was not found."
        case .activeMissionLimitExceeded(let workspaceID, let limit):
            return "Workspace \(workspaceID.rawValue) already has \(limit) active missions."
        }
    }
}

public actor MissionCoordinator {
    private let scope: SessionScope
    private let scheduler: RootScheduler
    private let jobStore: any JobStore
    private let missionStore: any MissionStore
    private let artifactStore: any ArtifactStore
    private let interactionBroker: InteractionBroker
    private let workspacePolicy: WorkspacePolicy
    private let supervisor: MissionSupervisor
    private let reflectionLoop: ReflectionLoop?
    private let modelRouter: ModelRouter
    private let changeCoordinator: ChangeCoordinator?

    public init(
        scope: SessionScope,
        scheduler: RootScheduler,
        jobStore: any JobStore,
        missionStore: any MissionStore,
        artifactStore: any ArtifactStore,
        interactionBroker: InteractionBroker,
        workspacePolicy: WorkspacePolicy = WorkspacePolicy(),
        supervisor: MissionSupervisor? = nil,
        reflectionLoop: ReflectionLoop? = nil,
        modelRouter: ModelRouter = ModelRouter(),
        changeCoordinator: ChangeCoordinator? = nil
    ) {
        self.scope = scope
        self.scheduler = scheduler
        self.jobStore = jobStore
        self.missionStore = missionStore
        self.artifactStore = artifactStore
        self.interactionBroker = interactionBroker
        self.workspacePolicy = workspacePolicy
        self.supervisor = supervisor ?? MissionSupervisor(policy: workspacePolicy)
        self.reflectionLoop = reflectionLoop
        self.modelRouter = modelRouter
        self.changeCoordinator = changeCoordinator
    }

    public func startMission(
        _ request: MissionStartRequest,
        now: Date = Date()
    ) async throws -> MissionStatusSnapshot {
        var request = request
        let activeMissions = try await missionStore.missions(
            sessionID: scope.sessionID,
            workspaceID: scope.workspaceID,
            statuses: MissionRecord.Status.allCases.filter { !$0.isTerminal }
        )
        if activeMissions.count >= workspacePolicy.maxActiveMissions {
            throw MissionCoordinatorError.activeMissionLimitExceeded(
                workspaceID: scope.workspaceID,
                limit: workspacePolicy.maxActiveMissions
            )
        }

        let routingDecision = await modelRouter.route(
            for: ModelRoutingRequest(
                explicitTier: request.metadata["model_route_tier"].flatMap(ModelRoutePolicy.Tier.init(rawValue:)),
                stageKind: .implement,
                requiresCoding: request.metadata["mission_kind"] == "code_change" ||
                    request.expectedOutputs.contains(where: { $0.localizedStandardContains("implementation") || $0.localizedStandardContains("code") }) ||
                    request.brief.localizedStandardContains("code"),
                hasAttachments: request.metadata["staged_artifact_refs"]?.isEmpty == false,
                budgetUnits: request.budgetUnits,
                preferredTierHint: request.metadata["omni_skills.preferred_model_tier"]
            )
        )
        request.metadata.merge(routingDecision.metadata) { _, new in new }

        let executionMode = resolveExecutionMode(for: request)
        let contractArtifact = try await writeArtifact(
            missionID: nil,
            name: "mission-contract.json",
            contentType: "application/json",
            text: contractBody(for: request, executionMode: executionMode)
        )
        let progressArtifact = try await writeArtifact(
            missionID: nil,
            name: "mission-progress.log",
            contentType: "text/plain",
            text: "[\(now.ISO8601Format())] Mission created: \(request.title)\n"
        )
        let verificationArtifact = try await writeArtifact(
            missionID: nil,
            name: "verification-report.txt",
            contentType: "text/plain",
            text: "Mission verification pending.\n"
        )

        var mission = MissionRecord(
            rootSessionID: scope.sessionID,
            requesterActorID: scope.actorID,
            workspaceID: scope.workspaceID,
            channelID: scope.channelID,
            title: request.title,
            brief: request.brief,
            executionMode: executionMode,
            status: request.requireApproval ? .awaitingApproval : .planning,
            contractArtifactID: contractArtifact.artifactID,
            progressArtifactID: progressArtifact.artifactID,
            verificationArtifactID: verificationArtifact.artifactID,
            budgetUnits: min(max(1, request.budgetUnits), workspacePolicy.maxBudgetUnits),
            maxRecursionDepth: min(request.maxRecursionDepth ?? workspacePolicy.maxRecursionDepth, workspacePolicy.maxRecursionDepth),
            metadata: request.metadata.merging([
                "capability_requirements": request.capabilityRequirements.joined(separator: ","),
                "expected_outputs": request.expectedOutputs.joined(separator: ","),
                "constraints": request.constraints.joined(separator: ","),
                "priority": String(request.priority),
                "budget_units": String(request.budgetUnits),
            ]) { _, new in new },
            createdAt: now,
            updatedAt: now
        )
        mission = try await missionStore.saveMission(mission)

        _ = try await missionStore.saveStage(
            MissionStageRecord(
                missionID: mission.missionID,
                rootSessionID: mission.rootSessionID,
                workspaceID: mission.workspaceID,
                channelID: mission.channelID,
                kind: .plan,
                executionMode: .direct,
                title: "Plan",
                status: .completed,
                artifactRefs: [contractArtifact.artifactID],
                metadata: ["summary": "Mission contract created."],
                createdAt: now,
                updatedAt: now,
                completedAt: now
            )
        )

        if request.requireApproval {
            _ = try await missionStore.saveStage(
                MissionStageRecord(
                    missionID: mission.missionID,
                    rootSessionID: mission.rootSessionID,
                    workspaceID: mission.workspaceID,
                    channelID: mission.channelID,
                    kind: .approval,
                    executionMode: .direct,
                    title: "Approval",
                    status: .waiting,
                    maxAttempts: 1,
                    metadata: ["prompt": request.approvalPrompt ?? request.brief],
                    createdAt: now,
                    updatedAt: now
                )
            )
            _ = try await interactionBroker.requestApproval(
                scope: scope,
                title: request.title,
                prompt: request.approvalPrompt ?? request.brief,
                missionID: mission.missionID,
                requesterActorID: scope.actorID,
                sensitive: true,
                policy: workspacePolicy,
                metadata: request.metadata
            )
            return try await missionStatus(missionID: mission.missionID)
        }

        try await beginExecution(for: mission, request: request, now: now)
        return try await missionStatus(missionID: mission.missionID)
    }

    public func listMissions(
        statuses: [MissionRecord.Status]? = nil,
        limit: Int? = nil
    ) async throws -> [MissionRecord] {
        let missions = try await missionStore.missions(
            sessionID: scope.sessionID,
            workspaceID: scope.workspaceID,
            statuses: statuses
        )
        if let limit, missions.count > limit {
            return Array(missions.prefix(limit))
        }
        return missions
    }

    public func missionStatus(missionID: String) async throws -> MissionStatusSnapshot {
        try await reconcileMission(missionID: missionID)
        guard let mission = try await missionStore.mission(missionID: missionID) else {
            throw MissionCoordinatorError.missionNotFound(missionID)
        }
        let stages = try await missionStore.stages(missionID: missionID)
        let task: TaskRecord?
        if let primaryTaskID = mission.primaryTaskID {
            task = try await jobStore.task(taskID: primaryTaskID)
        } else {
            task = nil
        }
        let recentEvents: [TaskEvent]
        if let primaryTaskID = mission.primaryTaskID {
            recentEvents = try await jobStore.events(taskID: primaryTaskID, afterSequence: nil)
        } else {
            recentEvents = []
        }
        let approvals = try await missionStore.approvalRequests(
            sessionID: scope.sessionID,
            workspaceID: scope.workspaceID,
            statuses: nil
        ).filter { $0.missionID == missionID }
        let questions = try await missionStore.questionRequests(
            sessionID: scope.sessionID,
            workspaceID: scope.workspaceID,
            statuses: nil
        ).filter { $0.missionID == missionID }
        return MissionStatusSnapshot(
            mission: mission,
            stages: stages,
            task: task,
            approvals: approvals,
            questions: questions,
            recentEvents: recentEvents
        )
    }

    public func waitForMission(
        missionID: String,
        timeoutSeconds: Double = 60,
        pollInterval: Duration = .milliseconds(250)
    ) async throws -> MissionStatusSnapshot {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while true {
            let snapshot = try await missionStatus(missionID: missionID)
            if snapshot.mission.status.isTerminal {
                return snapshot
            }
            if Date() >= deadline {
                return snapshot
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    public func approveRequest(
        requestID: String,
        approved: Bool,
        actorID: ActorID? = nil,
        responseText: String? = nil,
        at: Date = Date()
    ) async throws -> ApprovalRequestRecord {
        let request = try await interactionBroker.approve(
            requestID: requestID,
            approved: approved,
            actorID: actorID,
            responseText: responseText,
            at: at
        )
        if approved, let missionID = request.missionID {
            guard var mission = try await missionStore.mission(missionID: missionID) else {
                return request
            }
            if mission.status == .awaitingApproval {
                mission.status = .planning
                mission.updatedAt = at
                mission = try await missionStore.saveMission(mission)
                try await beginExecution(
                    for: mission,
                    request: resumeRequest(for: mission),
                    now: at
                )
            }
        }
        return request
    }

    public func answerQuestion(
        requestID: String,
        answerText: String,
        actorID: ActorID? = nil,
        at: Date = Date()
    ) async throws -> QuestionRequestRecord {
        let request = try await interactionBroker.answerQuestion(
            requestID: requestID,
            answerText: answerText,
            actorID: actorID,
            at: at
        )
        if let missionID = request.missionID, var mission = try await missionStore.mission(missionID: missionID) {
            if mission.status == .awaitingUserInput || mission.status == .blocked {
                mission.status = .planning
                mission.updatedAt = at
                _ = try await missionStore.saveMission(mission)
            }
        }
        return request
    }

    public func cancelMission(missionID: String, at: Date = Date()) async throws -> MissionRecord {
        guard var mission = try await missionStore.mission(missionID: missionID) else {
            throw MissionCoordinatorError.missionNotFound(missionID)
        }
        mission.status = .cancelled
        mission.completedAt = at
        mission.updatedAt = at
        if let taskID = mission.primaryTaskID {
            _ = try? await jobStore.cancelTask(
                taskID: taskID,
                workerID: nil,
                summary: "Mission cancelled",
                idempotencyKey: "mission.cancelled.\(missionID)",
                now: at
            )
        }
        return try await missionStore.saveMission(mission)
    }

    public func pauseMission(missionID: String, at: Date = Date()) async throws -> MissionRecord {
        guard var mission = try await missionStore.mission(missionID: missionID) else {
            throw MissionCoordinatorError.missionNotFound(missionID)
        }
        guard !mission.status.isTerminal else {
            return mission
        }
        mission.status = .paused
        mission.updatedAt = at
        return try await missionStore.saveMission(mission)
    }

    public func resumeMission(missionID: String, at: Date = Date()) async throws -> MissionRecord {
        guard var mission = try await missionStore.mission(missionID: missionID) else {
            throw MissionCoordinatorError.missionNotFound(missionID)
        }
        guard mission.status == .paused else {
            return mission
        }
        mission.status = .planning
        mission.updatedAt = at
        let stored = try await missionStore.saveMission(mission)
        try await reconcileMission(missionID: missionID, now: at)
        return try await missionStore.mission(missionID: stored.missionID) ?? stored
    }

    public func retryMissionStage(stageID: String, at: Date = Date()) async throws -> MissionStageRecord {
        guard var stage = try await missionStore.stage(stageID: stageID) else {
            throw MissionCoordinatorError.stageNotFound(stageID)
        }
        stage.attemptCount += 1
        stage.status = .running
        stage.updatedAt = at
        let metadata = stage.metadata
        let task = try await scheduler.submitTask(
            rootSessionID: stage.rootSessionID,
            requesterActorID: scope.actorID,
            workspaceID: stage.workspaceID,
            channelID: stage.channelID,
            missionID: stage.missionID,
            parentTaskID: nil,
            historyProjection: HistoryProjection(
                taskBrief: metadata["brief"] ?? "Retry mission stage \(stage.title)",
                constraints: splitCSV(metadata["constraints"]) + [
                    "max_recursion_depth=\(metadata["max_recursion_depth"] ?? String(workspacePolicy.maxRecursionDepth))",
                    "budget_units_remaining=\(metadata["budget_units_remaining"] ?? "1")",
                ],
                expectedOutputs: splitCSV(metadata["expected_outputs"])
            ),
            capabilityRequirements: splitCSV(metadata["capability_requirements"]),
            metadata: metadata,
            priority: Int(metadata["priority"] ?? "") ?? 0,
            createdAt: at
        )
        stage.taskID = task.taskID
        if var mission = try await missionStore.mission(missionID: stage.missionID) {
            mission.primaryTaskID = task.taskID
            mission.status = .executing
            mission.updatedAt = at
            _ = try await missionStore.saveMission(mission)
        }
        _ = try? await scheduler.dispatchAllAvailableTasksInBackground(now: at)
        return try await missionStore.saveStage(stage)
    }

    private func beginExecution(
        for mission: MissionRecord,
        request: MissionStartRequest,
        now: Date
    ) async throws {
        if shouldUseChangeCoordinator(for: request), let changeCoordinator {
            let changeRequest = ChangeRequest(
                rootSessionID: mission.rootSessionID,
                title: request.title,
                summary: request.brief,
                version: request.metadata["version"] ?? "draft",
                implementationBrief: request.brief,
                implementationCapabilities: request.capabilityRequirements,
                priority: request.priority
            )
            let changeTask = try await changeCoordinator.startChange(changeRequest, createdAt: now)
            _ = try await changeCoordinator.enqueueImplementation(
                for: changeTask.taskID,
                request: changeRequest,
                createdAt: now
            )
            try await saveExecutionStage(
                mission: mission,
                request: request,
                taskID: changeTask.taskID,
                now: now
            )
            return
        }

        switch mission.executionMode {
        case .direct:
            try await markMissionCompleted(
                missionID: mission.missionID,
                summary: "Root agent elected to handle this directly.",
                at: now
            )
        case .workerTask, .attractorWorkflow:
            let capabilityRequirements = mission.executionMode == .attractorWorkflow
                ? Array(Set(request.capabilityRequirements + ["execution:attractor"])).sorted()
                : request.capabilityRequirements
            let task = try await scheduler.submitTask(
                rootSessionID: mission.rootSessionID,
                requesterActorID: mission.requesterActorID,
                workspaceID: mission.workspaceID,
                channelID: mission.channelID,
                missionID: mission.missionID,
                parentTaskID: nil,
                historyProjection: HistoryProjection(
                    taskBrief: request.brief,
                    constraints: request.constraints + [
                        "mission_id=\(mission.missionID)",
                        "execution_mode=\(mission.executionMode.rawValue)",
                        "max_recursion_depth=\(mission.maxRecursionDepth)",
                        "budget_units_remaining=\(mission.budgetUnits)",
                    ],
                    expectedOutputs: request.expectedOutputs
                ),
                capabilityRequirements: capabilityRequirements,
                metadata: request.metadata,
                priority: request.priority,
                createdAt: now
            )
            try await saveExecutionStage(
                mission: mission,
                request: request,
                taskID: task.taskID,
                now: now
            )
            _ = try? await scheduler.dispatchAllAvailableTasksInBackground(now: now)
        }
    }

    private func saveExecutionStage(
        mission: MissionRecord,
        request: MissionStartRequest,
        taskID: String,
        now: Date
    ) async throws {
        var updatedMission = mission
        updatedMission.primaryTaskID = taskID
        updatedMission.status = .executing
        updatedMission.updatedAt = now
        _ = try await missionStore.saveMission(updatedMission)
        _ = try await missionStore.saveStage(
            MissionStageRecord(
                missionID: mission.missionID,
                rootSessionID: mission.rootSessionID,
                workspaceID: mission.workspaceID,
                channelID: mission.channelID,
                taskID: taskID,
                kind: .implement,
                executionMode: mission.executionMode,
                title: "Implement",
                status: .running,
                attemptCount: 1,
                maxAttempts: workspacePolicy.maxStageAttempts,
                metadata: [
                    "brief": request.brief,
                    "capability_requirements": request.capabilityRequirements.joined(separator: ","),
                    "expected_outputs": request.expectedOutputs.joined(separator: ","),
                    "constraints": request.constraints.joined(separator: ","),
                    "priority": String(request.priority),
                    "max_recursion_depth": String(mission.maxRecursionDepth),
                    "budget_units_remaining": String(mission.budgetUnits),
                ].merging(request.metadata) { _, new in new },
                createdAt: now,
                updatedAt: now
            )
        )
    }

    private func reconcileMission(missionID: String, now: Date = Date()) async throws {
        guard var mission = try await missionStore.mission(missionID: missionID) else {
            throw MissionCoordinatorError.missionNotFound(missionID)
        }
        var stages = try await missionStore.stages(missionID: missionID)
        guard let latestStageIndex = stages.lastIndex(where: { !$0.status.isTerminal || $0.taskID != nil }) else {
            return
        }
        var latestStage = stages[latestStageIndex]

        if let taskID = latestStage.taskID, let task = try await jobStore.task(taskID: taskID) {
            let latestTaskSummary = try await jobStore.events(taskID: taskID, afterSequence: nil).last?.summary
                ?? task.historyProjection.taskBrief
            switch task.status {
            case .submitted, .assigned, .running, .waiting:
                latestStage.status = task.status == .waiting ? .waiting : .running
                mission.status = .executing
            case .completed:
                latestStage.status = .completed
                latestStage.completedAt = now
                latestStage.updatedAt = now
                latestStage.artifactRefs = Array(Set(latestStage.artifactRefs + task.artifactRefs)).sorted()
                mission.status = .completed
                mission.completedAt = now
                mission.updatedAt = now
                let verificationArtifact = try await writeVerificationArtifact(
                    mission: mission,
                    task: task,
                    summary: latestTaskSummary
                )
                mission.verificationArtifactID = verificationArtifact.artifactID
                if mission.metadata["reflection_completed"] != "true" {
                    _ = try await reflectionLoop?.reflectOnMissionCompletion(
                        mission: mission,
                        task: task,
                        events: try await jobStore.events(taskID: taskID, afterSequence: nil)
                    )
                    mission.metadata["reflection_completed"] = "true"
                    mission.updatedAt = now
                }
            case .failed, .cancelled:
                if await supervisor.shouldRetry(stage: latestStage, task: task, now: now) {
                    _ = try await retryMissionStage(stageID: latestStage.stageID, at: now)
                    if let refreshedMission = try await missionStore.mission(missionID: missionID) {
                        mission = refreshedMission
                    } else {
                        mission.status = .executing
                        mission.updatedAt = now
                    }
                    stages = try await missionStore.stages(missionID: missionID)
                    latestStage = try await missionStore.stage(stageID: latestStage.stageID) ?? latestStage
                } else {
                    latestStage.status = task.status == .cancelled ? .cancelled : .failed
                    latestStage.completedAt = now
                    latestStage.updatedAt = now
                    mission.status = task.status == .cancelled ? .cancelled : .failed
                    mission.completedAt = now
                    mission.updatedAt = now
                    let verificationArtifact = try await writeVerificationArtifact(
                        mission: mission,
                        task: task,
                        summary: latestTaskSummary
                    )
                    mission.verificationArtifactID = verificationArtifact.artifactID
                }
            }
            _ = try await missionStore.saveStage(latestStage)
        }

        let pendingApprovals = try await missionStore.approvalRequests(
            sessionID: mission.rootSessionID,
            workspaceID: mission.workspaceID,
            statuses: [.pending, .deferred]
        ).filter { $0.missionID == missionID }
        let pendingQuestions = try await missionStore.questionRequests(
            sessionID: mission.rootSessionID,
            workspaceID: mission.workspaceID,
            statuses: [.pending, .deferred]
        ).filter { $0.missionID == missionID }

        if !pendingApprovals.isEmpty {
            mission.status = .awaitingApproval
            mission.updatedAt = now
        } else if !pendingQuestions.isEmpty {
            mission.status = .awaitingUserInput
            mission.updatedAt = now
        }

        _ = try await missionStore.saveMission(mission)
    }

    private func markMissionCompleted(
        missionID: String,
        summary: String,
        at: Date
    ) async throws {
        guard var mission = try await missionStore.mission(missionID: missionID) else {
            throw MissionCoordinatorError.missionNotFound(missionID)
        }
        mission.status = .completed
        mission.completedAt = at
        mission.updatedAt = at
        if mission.metadata["reflection_completed"] != "true" {
            _ = try await reflectionLoop?.reflectOnMissionCompletion(
                mission: mission,
                task: nil,
                events: []
            )
            mission.metadata["reflection_completed"] = "true"
        }
        let verificationArtifact = try await writeVerificationArtifact(
            mission: mission,
            task: nil,
            summary: summary
        )
        mission.verificationArtifactID = verificationArtifact.artifactID
        _ = try await missionStore.saveMission(mission)
        _ = try await missionStore.saveStage(
            MissionStageRecord(
                missionID: mission.missionID,
                rootSessionID: mission.rootSessionID,
                workspaceID: mission.workspaceID,
                channelID: mission.channelID,
                kind: .finalize,
                executionMode: .direct,
                title: "Finalize",
                status: .completed,
                metadata: ["summary": summary],
                createdAt: at,
                updatedAt: at,
                completedAt: at
            )
        )
    }

    private func writeVerificationArtifact(
        mission: MissionRecord,
        task: TaskRecord?,
        summary: String
    ) async throws -> ArtifactRecord {
        let body = [
            "Mission: \(mission.title)",
            "Status: \(mission.status.rawValue)",
            "Summary: \(summary)",
            task.map { "Task: \($0.taskID) (\($0.status.rawValue))" },
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        return try await artifactStore.put(
            ArtifactPayload(
                taskID: nil,
                missionID: mission.missionID,
                workspaceID: mission.workspaceID,
                channelID: mission.channelID,
                name: "verification-report.txt",
                contentType: "text/plain",
                data: Data(body.utf8)
            )
        )
    }

    private func resolveExecutionMode(for request: MissionStartRequest) -> MissionRecord.ExecutionMode {
        if let explicit = request.executionMode {
            return explicit
        }
        if request.metadata["workflow"] == "attractor" || request.capabilityRequirements.contains("execution:attractor") {
            return .attractorWorkflow
        }
        if request.capabilityRequirements.isEmpty &&
            request.expectedOutputs.isEmpty &&
            request.constraints.isEmpty &&
            request.brief.count < 180 {
            return .direct
        }
        return .workerTask
    }

    private func shouldUseChangeCoordinator(for request: MissionStartRequest) -> Bool {
        request.metadata["mission_kind"] == "code_change"
            || request.expectedOutputs.contains(where: { $0.localizedStandardContains("implementation") })
    }

    private func contractBody(
        for request: MissionStartRequest,
        executionMode: MissionRecord.ExecutionMode
    ) -> String {
        let object: [String: Any] = [
            "title": request.title,
            "brief": request.brief,
            "execution_mode": executionMode.rawValue,
            "capability_requirements": request.capabilityRequirements,
            "expected_outputs": request.expectedOutputs,
            "constraints": request.constraints,
            "priority": request.priority,
            "budget_units": request.budgetUnits,
            "max_recursion_depth": request.maxRecursionDepth ?? workspacePolicy.maxRecursionDepth,
            "metadata": request.metadata,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func writeArtifact(
        missionID: String?,
        name: String,
        contentType: String,
        text: String
    ) async throws -> ArtifactRecord {
        try await artifactStore.put(
            ArtifactPayload(
                missionID: missionID,
                workspaceID: scope.workspaceID,
                channelID: scope.channelID,
                name: name,
                contentType: contentType,
                data: Data(text.utf8)
            )
        )
    }

    private func resumeRequest(for mission: MissionRecord) -> MissionStartRequest {
        MissionStartRequest(
            title: mission.title,
            brief: mission.brief,
            executionMode: mission.executionMode,
            capabilityRequirements: splitCSV(mission.metadata["capability_requirements"]),
            expectedOutputs: splitCSV(mission.metadata["expected_outputs"]),
            constraints: splitCSV(mission.metadata["constraints"]),
            priority: Int(mission.metadata["priority"] ?? "") ?? 0,
            budgetUnits: Int(mission.metadata["budget_units"] ?? "") ?? mission.budgetUnits,
            maxRecursionDepth: mission.maxRecursionDepth,
            requireApproval: false,
            approvalPrompt: nil,
            metadata: mission.metadata
        )
    }
}

private func splitCSV(_ rawValue: String?) -> [String] {
    rawValue?
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty } ?? []
}
