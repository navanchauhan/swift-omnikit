import Foundation
import OmniAgentDeliveryCore
import OmniAgentMesh
import TheAgentWorkerKit

public enum MissionDeliveryMode: String, Sendable, Equatable {
    case deployable
    case artifactOnly = "artifact_only"
    case blockedForTargeting = "blocked_for_targeting"
}

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
    private let releaseBundleStore: (any ReleaseBundleStore)?
    private let releaseController: ReleaseController?

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
        changeCoordinator: ChangeCoordinator? = nil,
        releaseBundleStore: (any ReleaseBundleStore)? = nil,
        releaseController: ReleaseController? = nil
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
        self.releaseBundleStore = releaseBundleStore
        self.releaseController = releaseController
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

        let deliveryMode = resolveDeliveryMode(for: request)
        if shouldUseChangeCoordinator(for: request) {
            request.metadata["mission_kind"] = request.metadata["mission_kind"] ?? "code_change"
            request.metadata["delivery_mode"] = deliveryMode.rawValue
            request.metadata["delivery_service"] = request.metadata["delivery_service"] ?? request.metadata["service"] ?? "default"
            if let deployTarget = resolvedDeploymentTarget(for: request) {
                request.metadata["deploy_target"] = deployTarget
            }
            request.metadata["deploy_approval_required"] = String(deliveryMode == .deployable && workspacePolicy.requireDeploymentApproval)
            request.metadata["auto_rollout_eligible"] = String(deliveryMode == .deployable && workspacePolicy.allowAutomaticRollout)
            if deliveryMode == .deployable && workspacePolicy.requireDeploymentApproval {
                request.requireApproval = true
                request.approvalPrompt = request.approvalPrompt ?? "approve deploy to \(request.metadata["deploy_target"] ?? "the configured target") for \(request.title)?"
            }
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
            status: request.requireApproval ? .awaitingApproval : (deliveryMode == .blockedForTargeting ? .blocked : .planning),
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

        if deliveryMode == .blockedForTargeting {
            let options = workspacePolicy.allowedDeploymentTargets
            _ = try await missionStore.saveStage(
                MissionStageRecord(
                    missionID: mission.missionID,
                    rootSessionID: mission.rootSessionID,
                    workspaceID: mission.workspaceID,
                    channelID: mission.channelID,
                    kind: .question,
                    executionMode: .direct,
                    title: "Select deployment target",
                    status: .waiting,
                    maxAttempts: 1,
                    metadata: [
                        "delivery_mode": deliveryMode.rawValue,
                        "delivery_service": request.metadata["delivery_service"] ?? "default",
                    ],
                    createdAt: now,
                    updatedAt: now
                )
            )
            _ = try await interactionBroker.requestQuestion(
                scope: scope,
                title: "Deployment target required",
                prompt: "Which deployment target should i use for \(request.title)?",
                kind: options.isEmpty ? .freeText : .singleSelect,
                options: options,
                missionID: mission.missionID,
                requesterActorID: scope.actorID,
                metadata: [
                    "delivery_mode": deliveryMode.rawValue,
                    "delivery_service": request.metadata["delivery_service"] ?? "default",
                ]
            )
            return try await missionStatus(missionID: mission.missionID)
        }

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
                priority: request.priority,
                deliveryMode: request.metadata["delivery_mode"].flatMap(ChangeDeliveryMode.init(rawValue:)) ?? .artifactOnly,
                service: request.metadata["delivery_service"] ?? request.metadata["service"] ?? "default",
                targetEnvironment: request.metadata["deploy_target"],
                requireDeployApproval: request.metadata["deploy_approval_required"] == "true",
                autoRolloutEligible: request.metadata["auto_rollout_eligible"] == "true"
            )
            let changeTask = try await changeCoordinator.startChange(changeRequest, createdAt: now)
            let implementationTask = try await changeCoordinator.enqueueImplementation(
                for: changeTask.taskID,
                request: changeRequest,
                createdAt: now
            )
            var updatedMission = mission
            updatedMission.metadata["change_task_id"] = changeTask.taskID
            updatedMission.updatedAt = now
            _ = try await missionStore.saveMission(updatedMission)
            try await saveExecutionStage(
                mission: updatedMission,
                request: request,
                taskID: implementationTask.taskID,
                primaryTaskID: changeTask.taskID,
                now: now
            )
            _ = try? await scheduler.dispatchAllAvailableTasksInBackground(now: now)
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
        primaryTaskID: String? = nil,
        now: Date
    ) async throws {
        var updatedMission = mission
        updatedMission.primaryTaskID = primaryTaskID ?? taskID
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
                    "change_task_id": primaryTaskID ?? taskID,
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
        if mission.metadata["mission_kind"] == "code_change", changeCoordinator != nil {
            try await reconcileChangeMission(missionID: missionID, now: now)
            return
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

    private func reconcileChangeMission(missionID: String, now: Date) async throws {
        guard var mission = try await missionStore.mission(missionID: missionID) else {
            throw MissionCoordinatorError.missionNotFound(missionID)
        }
        guard let changeCoordinator else {
            return
        }
        guard let changeTaskID = mission.metadata["change_task_id"] ?? mission.primaryTaskID else {
            return
        }

        _ = try? await changeCoordinator.reconcileChange(changeTaskID: changeTaskID, now: now)

        var stages = try await missionStore.stages(missionID: missionID)
        guard let implementIndex = stages.lastIndex(where: { $0.kind == .implement }) else {
            return
        }

        var implementStage = stages[implementIndex]
        let (syncedImplementStage, implementationTask) = try await synchronizedStage(implementStage, now: now)
        implementStage = syncedImplementStage
        stages[implementIndex] = implementStage
        _ = try await missionStore.saveStage(implementStage)

        guard let implementationTask else {
            mission.status = .executing
            mission.updatedAt = now
            _ = try await missionStore.saveMission(mission)
            return
        }

        switch implementationTask.status {
        case .submitted, .assigned, .running, .waiting:
            mission.status = .executing
            mission.updatedAt = now
            _ = try await missionStore.saveMission(mission)
            return
        case .failed, .cancelled:
            let summary = "implementation failed for change mission \(mission.title)"
            _ = try? await changeCoordinator.failChange(changeTaskID: changeTaskID, summary: summary, now: now)
            try await terminalizeChangeMission(
                mission: mission,
                status: implementationTask.status == .cancelled ? .cancelled : .failed,
                summary: summary,
                task: implementationTask,
                metadataUpdates: [:],
                now: now
            )
            return
        case .completed:
            break
        }

        let changeRequest = changeRequest(for: mission, request: resumeRequest(for: mission))

        let reviewIndex = stages.lastIndex(where: { $0.kind == .review })
        let scenarioIndex = stages.lastIndex(where: { $0.kind == .scenario })

        if reviewIndex == nil || scenarioIndex == nil {
            let reviewTask = try await changeCoordinator.enqueueReview(
                for: changeTaskID,
                request: changeRequest,
                implementationArtifactRefs: implementationTask.artifactRefs,
                createdAt: now
            )
            let scenarioTask = try await changeCoordinator.enqueueScenarioEvaluation(
                for: changeTaskID,
                request: changeRequest,
                implementationArtifactRefs: implementationTask.artifactRefs,
                createdAt: now.addingTimeInterval(1)
            )
            _ = try await missionStore.saveStage(
                MissionStageRecord(
                    missionID: mission.missionID,
                    rootSessionID: mission.rootSessionID,
                    workspaceID: mission.workspaceID,
                    channelID: mission.channelID,
                    taskID: reviewTask.taskID,
                    kind: .review,
                    executionMode: .workerTask,
                    title: "Review",
                    status: .running,
                    attemptCount: 1,
                    maxAttempts: workspacePolicy.maxStageAttempts,
                    metadata: [
                        "change_task_id": changeTaskID,
                        "implementation_task_id": implementationTask.taskID,
                        "brief": changeRequest.reviewBrief,
                        "capability_requirements": changeRequest.reviewCapabilities.joined(separator: ","),
                    ],
                    createdAt: now,
                    updatedAt: now
                )
            )
            _ = try await missionStore.saveStage(
                MissionStageRecord(
                    missionID: mission.missionID,
                    rootSessionID: mission.rootSessionID,
                    workspaceID: mission.workspaceID,
                    channelID: mission.channelID,
                    taskID: scenarioTask.taskID,
                    kind: .scenario,
                    executionMode: .workerTask,
                    title: "Scenario",
                    status: .running,
                    attemptCount: 1,
                    maxAttempts: workspacePolicy.maxStageAttempts,
                    metadata: [
                        "change_task_id": changeTaskID,
                        "implementation_task_id": implementationTask.taskID,
                        "brief": changeRequest.scenarioBrief,
                        "capability_requirements": changeRequest.scenarioCapabilities.joined(separator: ","),
                    ],
                    createdAt: now,
                    updatedAt: now
                )
            )
            mission.status = .validating
            mission.updatedAt = now
            _ = try await missionStore.saveMission(mission)
            _ = try? await scheduler.dispatchAllAvailableTasksInBackground(now: now)
            return
        }

        var reviewStage = stages[reviewIndex!]
        var scenarioStage = stages[scenarioIndex!]
        let (syncedReviewStage, reviewTask) = try await synchronizedStage(reviewStage, now: now)
        reviewStage = syncedReviewStage
        let (syncedScenarioStage, scenarioTask) = try await synchronizedStage(scenarioStage, now: now)
        scenarioStage = syncedScenarioStage
        _ = try await missionStore.saveStage(reviewStage)
        _ = try await missionStore.saveStage(scenarioStage)

        guard let reviewTask, let scenarioTask else {
            mission.status = .validating
            mission.updatedAt = now
            _ = try await missionStore.saveMission(mission)
            return
        }

        if [.submitted, .assigned, .running, .waiting].contains(reviewTask.status)
            || [.submitted, .assigned, .running, .waiting].contains(scenarioTask.status) {
            mission.status = .validating
            mission.updatedAt = now
            _ = try await missionStore.saveMission(mission)
            return
        }

        if [.failed, .cancelled].contains(reviewTask.status) || [.failed, .cancelled].contains(scenarioTask.status) {
            let summary = reviewTask.status == .failed || reviewTask.status == .cancelled
                ? "review blocked deployment for \(mission.title)"
                : "scenario validation blocked deployment for \(mission.title)"
            _ = try? await changeCoordinator.failChange(changeTaskID: changeTaskID, summary: summary, now: now)
            try await terminalizeChangeMission(
                mission: mission,
                status: .failed,
                summary: summary,
                task: reviewTask.status == .failed || reviewTask.status == .cancelled ? reviewTask : scenarioTask,
                metadataUpdates: [:],
                now: now
            )
            return
        }

        let reviewSummary = try await latestSummary(taskID: reviewTask.taskID)
        let scenarioSummary = try await latestSummary(taskID: scenarioTask.taskID)
        let reviewApproved = ReviewWorker().isApproved(summary: reviewSummary)
        let scenarioPassed = ScenarioEvalWorker().didPass(summary: scenarioSummary)
        let judgeSummary = reviewApproved && scenarioPassed
            ? "review and scenario checks passed"
            : (reviewApproved ? "scenario validation blocked deployment" : "review blocked deployment")
        try await saveOrUpdateDirectStage(
            existing: stages.last(where: { $0.kind == .judge }),
            mission: mission,
            kind: .judge,
            title: "Judge",
            status: reviewApproved && scenarioPassed ? .completed : .failed,
            metadata: [
                "summary": judgeSummary,
                "review_summary": reviewSummary,
                "scenario_summary": scenarioSummary,
            ],
            now: now
        )

        guard reviewApproved && scenarioPassed else {
            _ = try? await changeCoordinator.failChange(changeTaskID: changeTaskID, summary: judgeSummary, now: now)
            try await terminalizeChangeMission(
                mission: mission,
                status: .failed,
                summary: judgeSummary,
                task: reviewTask,
                metadataUpdates: [:],
                now: now
            )
            return
        }

        switch changeRequest.deliveryMode {
        case .artifactOnly:
            let summary = "change completed with durable artifacts and no deployment"
            _ = try? await changeCoordinator.completeChange(
                changeTaskID: changeTaskID,
                summary: summary,
                artifactRefs: implementationTask.artifactRefs,
                now: now
            )
            try await terminalizeChangeMission(
                mission: mission,
                status: .completed,
                summary: summary,
                task: implementationTask,
                metadataUpdates: [
                    "deployment_state": "skipped",
                    "health_status": "inconclusive",
                    "delivery_summary": summary,
                    "delivery_completed": "true",
                ],
                now: now
            )
        case .blockedForTargeting:
            mission.status = .blocked
            mission.updatedAt = now
            _ = try await missionStore.saveMission(mission)
        case .deployable:
            try await performDeployableChangeDelivery(
                mission: mission,
                changeTaskID: changeTaskID,
                request: changeRequest,
                implementationTask: implementationTask,
                now: now
            )
        }
    }

    private func performDeployableChangeDelivery(
        mission: MissionRecord,
        changeTaskID: String,
        request: ChangeRequest,
        implementationTask: TaskRecord,
        now: Date
    ) async throws {
        guard let releaseBundleStore, let releaseController, let changeCoordinator else {
            let summary = "delivery runtime is unavailable for deployable mission \(mission.title)"
            try await terminalizeChangeMission(
                mission: mission,
                status: .failed,
                summary: summary,
                task: implementationTask,
                metadataUpdates: [
                    "deployment_state": "unavailable",
                    "health_status": "inconclusive",
                    "delivery_summary": summary,
                ],
                now: now
            )
            return
        }

        let implementationArtifacts = try await artifactStore.list(taskID: implementationTask.taskID)
        let releaseBundle = try await makeReleaseBundle(
            request: request,
            implementationArtifacts: implementationArtifacts,
            now: now
        )
        try await releaseBundleStore.saveBundle(releaseBundle)

        let unrelatedRunningTasks = try await jobStore.tasks(statuses: [.submitted, .assigned, .running, .waiting])
            .map(\.taskID)
            .filter { $0 != changeTaskID && $0 != implementationTask.taskID }

        try await saveOrUpdateDirectStage(
            existing: try await missionStore.stages(missionID: mission.missionID).last(where: { $0.kind == .finalize }),
            mission: mission,
            kind: .finalize,
            title: "Deploy",
            status: .running,
            metadata: [
                "release_bundle_id": releaseBundle.bundleID,
                "summary": "prepared release bundle and starting canary rollout",
            ],
            now: now
        )

        let release = try await releaseController.prepareRelease(
            version: request.version,
            releaseBundleID: releaseBundle.bundleID,
            service: request.service,
            targetEnvironment: request.targetEnvironment,
            deliveryMode: .deployable,
            autoRolloutEligible: request.autoRolloutEligible,
            drainingTaskIDs: unrelatedRunningTasks,
            metadata: [
                "mission_id": mission.missionID,
                "change_id": request.changeID,
                "integration_policy": request.policy.rawValue,
            ],
            now: now
        )
        let deployResult = try await releaseController.deployCanary(
            releaseID: release.releaseID,
            maxAttempts: max(1, request.maxRetries + 1),
            now: now.addingTimeInterval(1)
        )

        var metadataUpdates: [String: String] = [
            "release_bundle_id": releaseBundle.bundleID,
            "release_id": release.releaseID,
            "deployment_state": deployResult.state.rawValue,
            "health_status": deployResult.healthStatus.rawValue,
            "delivery_summary": deployResult.summary,
            "delivery_completed": "true",
            "release_generation": String(release.generation),
        ]
        if let rolledBack = deployResult.rolledBackToReleaseID {
            metadataUpdates["rollback_release_id"] = rolledBack
        }

        if deployResult.deployed {
            let summary = "deployed \(mission.title) as release \(release.releaseID)"
            metadataUpdates["delivery_summary"] = summary
            _ = try? await changeCoordinator.completeChange(
                changeTaskID: changeTaskID,
                summary: summary,
                artifactRefs: implementationTask.artifactRefs,
                now: now.addingTimeInterval(2)
            )
            try await terminalizeChangeMission(
                mission: mission,
                status: .completed,
                summary: summary,
                task: implementationTask,
                metadataUpdates: metadataUpdates,
                now: now.addingTimeInterval(2)
            )
        } else {
            let summary = deployResult.summary
            metadataUpdates["delivery_summary"] = summary
            _ = try? await changeCoordinator.failChange(
                changeTaskID: changeTaskID,
                summary: summary,
                now: now.addingTimeInterval(2)
            )
            try await terminalizeChangeMission(
                mission: mission,
                status: .failed,
                summary: summary,
                task: implementationTask,
                metadataUpdates: metadataUpdates,
                now: now.addingTimeInterval(2)
            )
        }
    }

    private func synchronizedStage(
        _ stage: MissionStageRecord,
        now: Date
    ) async throws -> (MissionStageRecord, TaskRecord?) {
        guard let taskID = stage.taskID, let task = try await jobStore.task(taskID: taskID) else {
            return (stage, nil)
        }
        var updated = stage
        switch task.status {
        case .submitted, .assigned, .running:
            updated.status = .running
            updated.updatedAt = now
        case .waiting:
            updated.status = .waiting
            updated.updatedAt = now
        case .completed:
            updated.status = .completed
            updated.updatedAt = now
            updated.completedAt = updated.completedAt ?? now
            updated.artifactRefs = Array(Set(updated.artifactRefs + task.artifactRefs)).sorted()
        case .failed:
            updated.status = .failed
            updated.updatedAt = now
            updated.completedAt = updated.completedAt ?? now
        case .cancelled:
            updated.status = .cancelled
            updated.updatedAt = now
            updated.completedAt = updated.completedAt ?? now
        }
        return (updated, task)
    }

    private func saveOrUpdateDirectStage(
        existing: MissionStageRecord?,
        mission: MissionRecord,
        kind: MissionStageRecord.Kind,
        title: String,
        status: MissionStageRecord.Status,
        metadata: [String: String],
        now: Date
    ) async throws {
        var stage = existing ?? MissionStageRecord(
            missionID: mission.missionID,
            rootSessionID: mission.rootSessionID,
            workspaceID: mission.workspaceID,
            channelID: mission.channelID,
            kind: kind,
            executionMode: .direct,
            title: title,
            status: status,
            createdAt: now,
            updatedAt: now
        )
        stage.title = title
        stage.status = status
        stage.metadata = metadata
        stage.updatedAt = now
        stage.completedAt = status.isTerminal ? now : nil
        _ = try await missionStore.saveStage(stage)
    }

    private func latestSummary(taskID: String) async throws -> String {
        let events = try await jobStore.events(taskID: taskID, afterSequence: nil)
        return events.last?.summary ?? ""
    }

    private func terminalizeChangeMission(
        mission: MissionRecord,
        status: MissionRecord.Status,
        summary: String,
        task: TaskRecord?,
        metadataUpdates: [String: String],
        now: Date
    ) async throws {
        var updatedMission = mission
        updatedMission.status = status
        updatedMission.completedAt = now
        updatedMission.updatedAt = now
        updatedMission.metadata.merge(metadataUpdates) { _, new in new }
        let taskEvents = if let task {
            try await jobStore.events(taskID: task.taskID, afterSequence: nil)
        } else {
            [TaskEvent]()
        }
        if updatedMission.metadata["reflection_completed"] != "true" {
            _ = try await reflectionLoop?.reflectOnMissionCompletion(
                mission: updatedMission,
                task: task,
                events: taskEvents
            )
            updatedMission.metadata["reflection_completed"] = "true"
        }
        let verificationArtifact = try await writeVerificationArtifact(
            mission: updatedMission,
            task: task,
            summary: summary
        )
        updatedMission.verificationArtifactID = verificationArtifact.artifactID
        _ = try await missionStore.saveMission(updatedMission)
        try await saveOrUpdateDirectStage(
            existing: try await missionStore.stages(missionID: mission.missionID).last(where: { $0.kind == .finalize }),
            mission: updatedMission,
            kind: .finalize,
            title: status == .completed ? "Finalize" : "Finalize failure",
            status: status == .completed ? .completed : .failed,
            metadata: ["summary": summary].merging(metadataUpdates) { _, new in new },
            now: now
        )
    }

    private func changeRequest(for mission: MissionRecord, request: MissionStartRequest) -> ChangeRequest {
        ChangeRequest(
            changeID: mission.metadata["change_task_id"] ?? UUID().uuidString,
            rootSessionID: mission.rootSessionID,
            title: mission.title,
            summary: mission.brief,
            version: request.metadata["version"] ?? "draft",
            implementationBrief: request.brief,
            implementationCapabilities: request.capabilityRequirements.isEmpty ? ["lane:implementation"] : request.capabilityRequirements,
            priority: request.priority,
            policy: request.metadata["integration_policy"].flatMap(ChangeIntegrationPolicy.init(rawValue:)) ?? .pullRequestOnly,
            deliveryMode: request.metadata["delivery_mode"].flatMap(ChangeDeliveryMode.init(rawValue:)) ?? .artifactOnly,
            service: request.metadata["delivery_service"] ?? request.metadata["service"] ?? "default",
            targetEnvironment: request.metadata["deploy_target"],
            requireDeployApproval: request.metadata["deploy_approval_required"] == "true",
            autoRolloutEligible: request.metadata["auto_rollout_eligible"] == "true",
            maxRetries: Int(request.metadata["deploy_max_retries"] ?? "") ?? 1
        )
    }

    private func makeReleaseBundle(
        request: ChangeRequest,
        implementationArtifacts: [ArtifactRecord],
        now: Date
    ) async throws -> ReleaseBundle {
        var artifactRefs: [ReleaseBundleArtifact] = []
        artifactRefs.reserveCapacity(implementationArtifacts.count)
        for artifact in implementationArtifacts {
            let data = try await artifactStore.data(for: artifact.artifactID) ?? Data()
            artifactRefs.append(
                ReleaseBundleArtifact(
                    artifactID: artifact.artifactID,
                    name: artifact.name,
                    contentType: artifact.contentType,
                    byteCount: data.count,
                    contentHash: ReleaseBundleHash.hash(data)
                )
            )
        }
        return ReleaseBundle(
            changeID: request.changeID,
            rootSessionID: request.rootSessionID,
            service: request.service,
            targetEnvironment: request.targetEnvironment ?? "unspecified",
            version: request.version,
            commitish: request.policy.rawValue,
            artifactRefs: artifactRefs,
            healthPlan: [
                "service_liveness",
                "worker_heartbeats",
                "smoke_checks",
            ],
            rollbackEligible: request.deliveryMode == .deployable,
            metadata: [
                "delivery_mode": request.deliveryMode.rawValue,
                "auto_rollout_eligible": String(request.autoRolloutEligible),
            ],
            createdAt: now
        )
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
        if resolveDeliveryMode(for: request) == .deployable {
            return .workerTask
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
            || request.expectedOutputs.contains(where: {
                $0.localizedStandardContains("implementation") ||
                $0.localizedStandardContains("deploy") ||
                $0.localizedStandardContains("release")
            })
            || request.brief.localizedStandardContains("implement")
            || request.brief.localizedStandardContains("ship")
            || request.brief.localizedStandardContains("deploy")
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

    private func resolveDeliveryMode(for request: MissionStartRequest) -> MissionDeliveryMode {
        if let explicit = request.metadata["delivery_mode"].flatMap(MissionDeliveryMode.init(rawValue:)) {
            return explicit
        }
        guard shouldUseChangeCoordinator(for: request) else {
            return .artifactOnly
        }
        if request.metadata["deployable"] == "false" {
            return .artifactOnly
        }
        if resolvedDeploymentTarget(for: request) != nil &&
            (request.metadata["deployable"] == "true" || request.expectedOutputs.contains(where: { $0.localizedStandardContains("deploy") || $0.localizedStandardContains("release") || $0.localizedStandardContains("ship") }) || workspacePolicy.defaultRepoChangesDeployable) {
            return .deployable
        }
        if request.metadata["deployable"] == "true" || request.expectedOutputs.contains(where: { $0.localizedStandardContains("deploy") || $0.localizedStandardContains("release") || $0.localizedStandardContains("ship") }) {
            return .blockedForTargeting
        }
        return workspacePolicy.defaultRepoChangesDeployable ? .blockedForTargeting : .artifactOnly
    }

    private func resolvedDeploymentTarget(for request: MissionStartRequest) -> String? {
        if let explicit = request.metadata["deploy_target"]?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }
        return workspacePolicy.defaultDeploymentTarget
    }
}

private func splitCSV(_ rawValue: String?) -> [String] {
    rawValue?
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty } ?? []
}
