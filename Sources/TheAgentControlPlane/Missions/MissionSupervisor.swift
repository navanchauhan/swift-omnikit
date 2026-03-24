import Foundation
import OmniAgentMesh

public actor MissionSupervisor {
    private let policy: WorkspacePolicy

    public init(policy: WorkspacePolicy = WorkspacePolicy()) {
        self.policy = policy
    }

    public func shouldRetry(stage: MissionStageRecord, task: TaskRecord?, now: Date = Date()) -> Bool {
        guard let task, task.status == .failed else {
            return false
        }
        guard stage.attemptCount < min(stage.maxAttempts, policy.maxStageAttempts) else {
            return false
        }
        if let deadlineAt = stage.deadlineAt, deadlineAt <= now {
            return false
        }
        return true
    }
}
