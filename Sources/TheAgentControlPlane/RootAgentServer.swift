import Foundation
import OmniAgentMesh

public enum RootAgentServerError: Error, CustomStringConvertible, Sendable, Equatable {
    case taskNotFound(String)
    case taskNotManagedBySession(taskID: String, sessionID: String)
    case noManagedTasks(sessionID: String)
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

    private let conversation: RootConversation
    private let inbox: NotificationInbox
    private let scheduler: RootScheduler
    private let jobStore: any JobStore

    public init(
        sessionID: String,
        conversationStore: any ConversationStore,
        jobStore: any JobStore,
        hotWindowLimit: Int = 12,
        notificationPolicy: NotificationPolicy = NotificationPolicy(),
        scheduler: RootScheduler? = nil
    ) {
        self.sessionID = sessionID
        self.jobStore = jobStore
        self.scheduler = scheduler ?? RootScheduler(jobStore: jobStore)
        self.conversation = RootConversation(
            sessionID: sessionID,
            store: conversationStore,
            hotWindowLimit: hotWindowLimit
        )
        self.inbox = NotificationInbox(
            sessionID: sessionID,
            store: conversationStore,
            policy: notificationPolicy
        )
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

    public func handleUserText(_ content: String, metadata: [String: String] = [:]) async throws -> RootConversationSnapshot {
        _ = try await conversation.recordUserText(content, metadata: metadata)
        return try await restoreState()
    }

    public func recordAssistantText(_ content: String, metadata: [String: String] = [:]) async throws -> RootConversationSnapshot {
        _ = try await conversation.recordAssistantText(content, metadata: metadata)
        return try await restoreState()
    }

    public func recordAudioTranscript(_ content: String, metadata: [String: String] = [:]) async throws -> RootConversationSnapshot {
        _ = try await conversation.recordAudioTranscript(content, metadata: metadata)
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
