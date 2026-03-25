import Foundation
import OmniAgentMesh

public struct TaskStallRecord: Sendable, Equatable {
    public enum Reason: String, Sendable {
        case idleTimeout = "idle_timeout"
        case missingHeartbeat = "missing_heartbeat"
        case wallClockTimeout = "wall_clock_timeout"
    }

    public var task: TaskRecord
    public var reason: Reason
    public var latestHeartbeat: ActivityHeartbeat?
    public var latestEventAt: Date

    public init(
        task: TaskRecord,
        reason: Reason,
        latestHeartbeat: ActivityHeartbeat?,
        latestEventAt: Date
    ) {
        self.task = task
        self.reason = reason
        self.latestHeartbeat = latestHeartbeat
        self.latestEventAt = latestEventAt
    }

    public var summary: String {
        switch reason {
        case .idleTimeout:
            return "Task \(task.taskID) has gone idle without activity heartbeats."
        case .missingHeartbeat:
            return "Task \(task.taskID) started without any heartbeat coverage."
        case .wallClockTimeout:
            return "Task \(task.taskID) exceeded its wall-clock deadline."
        }
    }
}

public actor TimeoutWatchdog {
    private let jobStore: any JobStore
    private let defaultIdleTimeout: TimeInterval
    private let defaultHeartbeatGracePeriod: TimeInterval

    public init(
        jobStore: any JobStore,
        defaultIdleTimeout: TimeInterval = 120,
        defaultHeartbeatGracePeriod: TimeInterval = 30
    ) {
        self.jobStore = jobStore
        self.defaultIdleTimeout = defaultIdleTimeout
        self.defaultHeartbeatGracePeriod = defaultHeartbeatGracePeriod
    }

    public func stalledTasks(now: Date = Date()) async throws -> [TaskStallRecord] {
        let tasks = try await jobStore.tasks(statuses: [.submitted, .assigned, .running, .waiting])
        var stalled: [TaskStallRecord] = []

        for task in tasks {
            let events = try await jobStore.events(taskID: task.taskID, afterSequence: nil)
            let latestEventAt = events.last?.createdAt ?? task.updatedAt
            let latestHeartbeat = events.reversed().lazy.compactMap(ActivityHeartbeat.coverage(from:)).first

            if let deadlineAt = task.deadlineAt, deadlineAt <= now {
                stalled.append(
                    TaskStallRecord(
                        task: task,
                        reason: .wallClockTimeout,
                        latestHeartbeat: latestHeartbeat,
                        latestEventAt: latestEventAt
                    )
                )
                continue
            }

            let idleTimeout = Double(task.metadata["idle_timeout_seconds"] ?? "") ?? defaultIdleTimeout
            let heartbeatGrace = Double(task.metadata["heartbeat_grace_seconds"] ?? "") ?? defaultHeartbeatGracePeriod

            if let latestHeartbeat {
                if now.timeIntervalSince(latestHeartbeat.recordedAt) > idleTimeout {
                    stalled.append(
                        TaskStallRecord(
                            task: task,
                            reason: .idleTimeout,
                            latestHeartbeat: latestHeartbeat,
                            latestEventAt: latestEventAt
                        )
                    )
                }
            } else if now.timeIntervalSince(latestEventAt) > heartbeatGrace {
                stalled.append(
                    TaskStallRecord(
                        task: task,
                        reason: .missingHeartbeat,
                        latestHeartbeat: nil,
                        latestEventAt: latestEventAt
                    )
                )
            }
        }

        return stalled
    }
}
