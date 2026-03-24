import Foundation
import OmniAgentMesh

public enum RootAgentServerError: Error, CustomStringConvertible, Sendable, Equatable {
    case taskNotFound(String)
    case taskNotManagedBySession(taskID: String, sessionID: String)
    case noManagedTasks(sessionID: String)
    case missionNotFound(String)
    case noManagedMissions(sessionID: String)
    case missionSupportUnavailable(sessionID: String)
    case notificationNotFound(String)
    case noUnresolvedNotifications(sessionID: String)

    public var description: String {
        switch self {
        case .taskNotFound(let taskID):
            return "Task \(taskID) was not found."
        case .taskNotManagedBySession(let taskID, let sessionID):
            return "Task \(taskID) does not belong to root session \(sessionID)."
        case .noManagedTasks(let sessionID):
            return "Root session \(sessionID) does not have any managed tasks."
        case .missionNotFound(let missionID):
            return "Mission \(missionID) was not found."
        case .noManagedMissions(let sessionID):
            return "Root session \(sessionID) does not have any managed missions."
        case .missionSupportUnavailable(let sessionID):
            return "Root session \(sessionID) is not configured with mission support."
        case .notificationNotFound(let notificationID):
            return "Notification \(notificationID) was not found."
        case .noUnresolvedNotifications(let sessionID):
            return "Root session \(sessionID) does not have any unresolved notifications."
        }
    }
}

public struct RootTaskWaitResult: Sendable, Equatable {
    public var task: TaskRecord?
    public var events: [TaskEvent]
    public var unresolvedNotifications: [NotificationRecord]
    public var timedOut: Bool

    public init(
        task: TaskRecord?,
        events: [TaskEvent],
        unresolvedNotifications: [NotificationRecord],
        timedOut: Bool
    ) {
        self.task = task
        self.events = events
        self.unresolvedNotifications = unresolvedNotifications
        self.timedOut = timedOut
    }
}

public actor RootAgentServer {
    public nonisolated let sessionID: String
    public nonisolated let scope: SessionScope

    private let conversation: RootConversation
    private let inbox: NotificationInbox
    private let scheduler: RootScheduler
    private let jobStore: any JobStore
    private let missionStore: (any MissionStore)?
    private let interactionBroker: InteractionBroker?
    private let missionCoordinator: MissionCoordinator?
    private let workspacePolicy: WorkspacePolicy

    public init(
        scope: SessionScope,
        conversationStore: any ConversationStore,
        jobStore: any JobStore,
        missionStore: (any MissionStore)? = nil,
        artifactStore: (any ArtifactStore)? = nil,
        deliveryStore: (any DeliveryStore)? = nil,
        hotWindowLimit: Int = 12,
        notificationPolicy: NotificationPolicy = NotificationPolicy(),
        workspacePolicy: WorkspacePolicy = WorkspacePolicy(),
        scheduler: RootScheduler? = nil
    ) {
        self.sessionID = scope.sessionID
        self.scope = scope
        self.jobStore = jobStore
        self.missionStore = missionStore
        self.workspacePolicy = workspacePolicy
        self.scheduler = scheduler ?? RootScheduler(jobStore: jobStore)
        self.conversation = RootConversation(
            scope: scope,
            store: conversationStore,
            hotWindowLimit: hotWindowLimit
        )
        self.inbox = NotificationInbox(
            scope: scope,
            store: conversationStore,
            policy: notificationPolicy
        )
        if let missionStore, let artifactStore {
            let interactionBroker = InteractionBroker(
                missionStore: missionStore,
                conversationStore: conversationStore,
                deliveryStore: deliveryStore,
                notificationPolicy: notificationPolicy
            )
            self.interactionBroker = interactionBroker
            self.missionCoordinator = MissionCoordinator(
                scope: scope,
                scheduler: self.scheduler,
                jobStore: jobStore,
                missionStore: missionStore,
                artifactStore: artifactStore,
                interactionBroker: interactionBroker,
                workspacePolicy: workspacePolicy,
                changeCoordinator: ChangeCoordinator(jobStore: jobStore)
            )
        } else {
            self.interactionBroker = nil
            self.missionCoordinator = nil
        }
    }

    public init(
        sessionID: String,
        conversationStore: any ConversationStore,
        jobStore: any JobStore,
        missionStore: (any MissionStore)? = nil,
        artifactStore: (any ArtifactStore)? = nil,
        deliveryStore: (any DeliveryStore)? = nil,
        hotWindowLimit: Int = 12,
        notificationPolicy: NotificationPolicy = NotificationPolicy(),
        workspacePolicy: WorkspacePolicy = WorkspacePolicy(),
        scheduler: RootScheduler? = nil
    ) {
        let scope = SessionScope.bestEffort(sessionID: sessionID)
        self.sessionID = sessionID
        self.scope = scope
        self.jobStore = jobStore
        self.missionStore = missionStore
        self.workspacePolicy = workspacePolicy
        self.scheduler = scheduler ?? RootScheduler(jobStore: jobStore)
        self.conversation = RootConversation(sessionID: sessionID, store: conversationStore, hotWindowLimit: hotWindowLimit)
        self.inbox = NotificationInbox(sessionID: sessionID, store: conversationStore, policy: notificationPolicy)
        if let missionStore, let artifactStore {
            let interactionBroker = InteractionBroker(
                missionStore: missionStore,
                conversationStore: conversationStore,
                deliveryStore: deliveryStore,
                notificationPolicy: notificationPolicy
            )
            self.interactionBroker = interactionBroker
            self.missionCoordinator = MissionCoordinator(
                scope: scope,
                scheduler: self.scheduler,
                jobStore: jobStore,
                missionStore: missionStore,
                artifactStore: artifactStore,
                interactionBroker: interactionBroker,
                workspacePolicy: workspacePolicy,
                changeCoordinator: ChangeCoordinator(jobStore: jobStore)
            )
        } else {
            self.interactionBroker = nil
            self.missionCoordinator = nil
        }
    }

    public func registerLocalWorker(_ worker: any WorkerDispatching, at: Date = Date()) async throws {
        try await scheduler.registerLocalWorker(worker, at: at)
    }

    public func registerRemoteWorker(_ worker: any WorkerDispatching, at: Date = Date()) async throws {
        try await scheduler.registerRemoteWorker(worker, at: at)
    }

    public func restoreState() async throws -> RootConversationSnapshot {
        try await conversation.snapshot()
    }

    public func handleUserText(
        _ content: String,
        actorID: ActorID? = nil,
        metadata: [String: String] = [:]
    ) async throws -> RootConversationSnapshot {
        _ = try await conversation.recordUserText(content, actorID: actorID, metadata: metadata)
        return try await restoreState()
    }

    public func recordAssistantText(_ content: String, metadata: [String: String] = [:]) async throws -> RootConversationSnapshot {
        _ = try await conversation.recordAssistantText(content, metadata: metadata)
        return try await restoreState()
    }

    public func recordAudioTranscript(
        _ content: String,
        actorID: ActorID? = nil,
        metadata: [String: String] = [:]
    ) async throws -> RootConversationSnapshot {
        _ = try await conversation.recordAudioTranscript(content, actorID: actorID, metadata: metadata)
        return try await restoreState()
    }

    public func delegateTask(
        brief: String,
        capabilityRequirements: [String] = [],
        expectedOutputs: [String] = [],
        constraints: [String] = [],
        priority: Int = 0,
        parentTaskID: String? = nil
    ) async throws -> TaskRecord {
        let snapshot = try await conversation.snapshot()
        let historyProjection = HistoryProjection(
            taskBrief: brief,
            summaries: snapshot.summary.map { [$0.summaryText] } ?? [],
            parentExcerpts: snapshot.hotContext.map { item in
                "\(item.role.rawValue): \(item.content)"
            },
            artifactRefs: [],
            constraints: constraints,
            expectedOutputs: expectedOutputs
        )
        let task = try await scheduler.submitTask(
            rootSessionID: sessionID,
            requesterActorID: scope.actorID,
            workspaceID: scope.workspaceID,
            channelID: scope.channelID,
            parentTaskID: parentTaskID,
            historyProjection: historyProjection,
            capabilityRequirements: capabilityRequirements,
            priority: priority
        )
        _ = try? await kickLocalDispatch(now: Date())
        return task
    }

    public func listWorkers() async throws -> [WorkerRecord] {
        try await jobStore.workers()
    }

    public func startMission(_ request: MissionStartRequest) async throws -> MissionStatusSnapshot {
        guard let missionCoordinator else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await missionCoordinator.startMission(request)
    }

    public func listMissions(
        statuses: [MissionRecord.Status]? = nil,
        limit: Int? = nil
    ) async throws -> [MissionRecord] {
        guard let missionCoordinator else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await missionCoordinator.listMissions(statuses: statuses, limit: limit)
    }

    public func latestMission() async throws -> MissionRecord? {
        guard let missionStore else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await missionStore.missions(
            sessionID: sessionID,
            workspaceID: scope.workspaceID,
            statuses: nil
        ).first
    }

    public func missionStatus(missionID: String? = nil) async throws -> MissionStatusSnapshot {
        guard let missionCoordinator else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        let resolvedMissionID: String
        if let missionID {
            resolvedMissionID = missionID
        } else if let latest = try await latestMission() {
            resolvedMissionID = latest.missionID
        } else {
            throw RootAgentServerError.noManagedMissions(sessionID: sessionID)
        }
        return try await missionCoordinator.missionStatus(missionID: resolvedMissionID)
    }

    public func waitForMission(
        missionID: String? = nil,
        timeoutSeconds: Double = 60,
        pollInterval: Duration = .milliseconds(250)
    ) async throws -> MissionStatusSnapshot {
        guard let missionCoordinator else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        let resolvedMissionID: String
        if let missionID {
            resolvedMissionID = missionID
        } else if let latest = try await latestMission() {
            resolvedMissionID = latest.missionID
        } else {
            throw RootAgentServerError.noManagedMissions(sessionID: sessionID)
        }
        return try await missionCoordinator.waitForMission(
            missionID: resolvedMissionID,
            timeoutSeconds: timeoutSeconds,
            pollInterval: pollInterval
        )
    }

    public func cancelMission(missionID: String) async throws -> MissionRecord {
        guard let missionCoordinator else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await missionCoordinator.cancelMission(missionID: missionID)
    }

    public func pauseMission(missionID: String) async throws -> MissionRecord {
        guard let missionCoordinator else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await missionCoordinator.pauseMission(missionID: missionID)
    }

    public func resumeMission(missionID: String) async throws -> MissionRecord {
        guard let missionCoordinator else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await missionCoordinator.resumeMission(missionID: missionID)
    }

    public func retryMissionStage(stageID: String) async throws -> MissionStageRecord {
        guard let missionCoordinator else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await missionCoordinator.retryMissionStage(stageID: stageID)
    }

    public func listInbox(unresolvedOnly: Bool = true) async throws -> [InteractionInboxItem] {
        guard let interactionBroker else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await interactionBroker.listInbox(scope: scope, unresolvedOnly: unresolvedOnly)
    }

    public func approveRequest(
        requestID: String,
        approved: Bool,
        actorID: ActorID? = nil,
        responseText: String? = nil
    ) async throws -> ApprovalRequestRecord {
        guard let missionCoordinator else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await missionCoordinator.approveRequest(
            requestID: requestID,
            approved: approved,
            actorID: actorID,
            responseText: responseText
        )
    }

    public func answerQuestion(
        requestID: String,
        answerText: String,
        actorID: ActorID? = nil
    ) async throws -> QuestionRequestRecord {
        guard let missionCoordinator else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await missionCoordinator.answerQuestion(
            requestID: requestID,
            answerText: answerText,
            actorID: actorID
        )
    }

    public func requestApprovalPrompt(
        title: String,
        prompt: String,
        missionID: String? = nil,
        taskID: String? = nil,
        requesterActorID: ActorID? = nil,
        sensitive: Bool = true,
        metadata: [String: String] = [:]
    ) async throws -> ApprovalRequestRecord {
        guard let interactionBroker else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await interactionBroker.requestApproval(
            scope: scope,
            title: title,
            prompt: prompt,
            missionID: missionID,
            taskID: taskID,
            requesterActorID: requesterActorID,
            sensitive: sensitive,
            policy: workspacePolicy,
            metadata: metadata
        )
    }

    public func requestQuestionPrompt(
        title: String,
        prompt: String,
        kind: QuestionRequestRecord.Kind = .freeText,
        options: [String] = [],
        missionID: String? = nil,
        taskID: String? = nil,
        requesterActorID: ActorID? = nil,
        metadata: [String: String] = [:]
    ) async throws -> QuestionRequestRecord {
        guard let interactionBroker else {
            throw RootAgentServerError.missionSupportUnavailable(sessionID: sessionID)
        }
        return try await interactionBroker.requestQuestion(
            scope: scope,
            title: title,
            prompt: prompt,
            kind: kind,
            options: options,
            missionID: missionID,
            taskID: taskID,
            requesterActorID: requesterActorID,
            metadata: metadata
        )
    }

    public func listTasks(
        statuses: [TaskRecord.Status]? = nil,
        limit: Int? = nil,
        currentRootOnly: Bool = true
    ) async throws -> [TaskRecord] {
        var tasks = try await jobStore.tasks(statuses: statuses)
        if currentRootOnly {
            tasks.removeAll { $0.rootSessionID != sessionID }
        }
        tasks.sort(by: RootAgentServer.taskSortComparator)
        if let limit, tasks.count > limit {
            return Array(tasks.prefix(limit))
        }
        return tasks
    }

    public func latestTask(currentRootOnly: Bool = true) async throws -> TaskRecord? {
        let tasks = try await listTasks(statuses: nil, limit: 1, currentRootOnly: currentRootOnly)
        return tasks.first
    }

    public func task(taskID: String, currentRootOnly: Bool = true) async throws -> TaskRecord? {
        guard let task = try await jobStore.task(taskID: taskID) else {
            return nil
        }
        if currentRootOnly && task.rootSessionID != sessionID {
            return nil
        }
        return task
    }

    public func taskEvents(
        taskID: String,
        afterSequence: Int? = nil,
        currentRootOnly: Bool = true
    ) async throws -> [TaskEvent] {
        if currentRootOnly {
            _ = try await requireManagedTask(taskID: taskID)
        }
        return try await jobStore.events(taskID: taskID, afterSequence: afterSequence)
    }

    public func listNotifications(
        refresh: Bool = true,
        unresolvedOnly: Bool = true
    ) async throws -> [NotificationRecord] {
        if refresh {
            _ = try await refreshTaskNotifications()
        }
        return unresolvedOnly
            ? try await inbox.unresolved()
            : try await inbox.all()
    }

    public func resolveNotification(
        notificationID: String? = nil,
        at: Date = Date()
    ) async throws -> NotificationRecord {
        let targetID: String
        if let notificationID {
            targetID = notificationID
        } else {
            let unresolved = try await inbox.unresolved()
            guard let oldest = unresolved.first else {
                throw RootAgentServerError.noUnresolvedNotifications(sessionID: sessionID)
            }
            targetID = oldest.notificationID
        }

        guard let resolved = try await inbox.resolve(notificationID: targetID, at: at) else {
            throw RootAgentServerError.notificationNotFound(targetID)
        }
        return resolved
    }

    public func kickLocalDispatch(now: Date = Date()) async throws -> [TaskRecord] {
        try await scheduler.dispatchAllAvailableTasksInBackground(now: now)
    }

    public func waitForTask(
        taskID: String? = nil,
        timeoutSeconds: Double = 60,
        pollInterval: Duration = .milliseconds(250)
    ) async throws -> RootTaskWaitResult {
        let resolvedTaskID = try await resolveTaskID(taskID)
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastSequence: Int?
        var collectedEvents: [TaskEvent] = []

        while true {
            _ = try? await kickLocalDispatch(now: Date())

            let newEvents = try await taskEvents(taskID: resolvedTaskID, afterSequence: lastSequence)
            if let latestSequence = newEvents.last?.sequenceNumber {
                lastSequence = latestSequence
            }
            collectedEvents.append(contentsOf: newEvents)

            let currentTask = try await task(taskID: resolvedTaskID)
            if let currentTask, currentTask.status.isTerminal {
                let notifications = try await listNotifications(refresh: true, unresolvedOnly: true)
                return RootTaskWaitResult(
                    task: currentTask,
                    events: collectedEvents,
                    unresolvedNotifications: notifications,
                    timedOut: false
                )
            }

            if Date() >= deadline {
                let notifications = try await listNotifications(refresh: true, unresolvedOnly: true)
                return RootTaskWaitResult(
                    task: currentTask,
                    events: collectedEvents,
                    unresolvedNotifications: notifications,
                    timedOut: true
                )
            }

            try await Task.sleep(for: pollInterval)
        }
    }

    public func dispatchAndRefresh(now: Date = Date()) async throws -> [NotificationRecord] {
        _ = try await scheduler.dispatchAllAvailableTasks(now: now)
        return try await refreshTaskNotifications()
    }

    public func refreshTaskNotifications() async throws -> [NotificationRecord] {
        let terminalTasks = try await jobStore.tasks(statuses: [.completed, .failed, .cancelled])
        var existingNotificationIDs = Set(try await inbox.all().map(\.notificationID))

        for task in terminalTasks where task.rootSessionID == sessionID {
            let notificationID = "task.\(task.taskID).\(task.status.rawValue)"
            guard !existingNotificationIDs.contains(notificationID) else {
                continue
            }

            let taskEvents = try await jobStore.events(taskID: task.taskID, afterSequence: nil)
            let lastSummary = taskEvents.last?.summary ?? task.historyProjection.taskBrief

            let title: String
            let importance: NotificationRecord.Importance
            switch task.status {
            case .completed:
                title = "Task Completed"
                importance = .important
            case .failed:
                title = "Task Failed"
                importance = .urgent
            case .cancelled:
                title = "Task Cancelled"
                importance = .important
            default:
                continue
            }

            let notification = try await inbox.enqueue(
                notificationID: notificationID,
                taskID: task.taskID,
                title: title,
                body: lastSummary,
                importance: importance,
                metadata: ["status": task.status.rawValue]
            )
            try await conversation.recordNotification(notification)
            existingNotificationIDs.insert(notificationID)
        }

        return try await inbox.unresolved()
    }

    private func requireManagedTask(taskID: String) async throws -> TaskRecord {
        guard let task = try await jobStore.task(taskID: taskID) else {
            throw RootAgentServerError.taskNotFound(taskID)
        }
        guard task.rootSessionID == sessionID else {
            throw RootAgentServerError.taskNotManagedBySession(taskID: taskID, sessionID: sessionID)
        }
        return task
    }

    private func resolveTaskID(_ explicitTaskID: String?) async throws -> String {
        if let explicitTaskID {
            let task = try await requireManagedTask(taskID: explicitTaskID)
            return task.taskID
        }
        guard let latest = try await latestTask(currentRootOnly: true) else {
            throw RootAgentServerError.noManagedTasks(sessionID: sessionID)
        }
        return latest.taskID
    }

    private static func taskSortComparator(lhs: TaskRecord, rhs: TaskRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.taskID < rhs.taskID
    }
}

private extension TaskRecord.Status {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .submitted, .assigned, .running, .waiting:
            return false
        }
    }
}
