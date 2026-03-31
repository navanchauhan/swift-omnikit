import Foundation
import OmniAgentMesh

public struct CapabilityMatcher: Sendable {
    public var staleAfter: TimeInterval
    public var preferSameHost: Bool

    public init(staleAfter: TimeInterval = 120, preferSameHost: Bool = true) {
        self.staleAfter = staleAfter
        self.preferSameHost = preferSameHost
    }

    public func rank(
        task: TaskRecord,
        workers: [WorkerRecord],
        now: Date = Date()
    ) -> [WorkerRecord] {
        let requiredGeneration = task.metadata["required_generation"].flatMap(Int.init)
        return workers
            .filter { worker in
                Set(task.capabilityRequirements).isSubset(of: Set(worker.capabilities))
            }
            .filter { worker in
                worker.state != .offline &&
                    worker.state != .drained &&
                    now.timeIntervalSince(worker.lastHeartbeatAt) <= staleAfter
            }
            .filter { worker in
                guard let requiredGeneration else { return true }
                return worker.generation == requiredGeneration
            }
            .sorted { lhs, rhs in
                compare(lhs, rhs) == .orderedAscending
            }
    }

    private func compare(_ lhs: WorkerRecord, _ rhs: WorkerRecord) -> ComparisonResult {
        let lhsScore = placementScore(for: lhs) + stateScore(for: lhs) + generationScore(for: lhs) + capabilityScore(for: lhs)
        let rhsScore = placementScore(for: rhs) + stateScore(for: rhs) + generationScore(for: rhs) + capabilityScore(for: rhs)

        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? .orderedAscending : .orderedDescending
        }
        if lhs.lastHeartbeatAt != rhs.lastHeartbeatAt {
            return lhs.lastHeartbeatAt > rhs.lastHeartbeatAt ? .orderedAscending : .orderedDescending
        }
        return lhs.workerID.localizedStandardCompare(rhs.workerID)
    }

    private func placementScore(for worker: WorkerRecord) -> Int {
        guard preferSameHost else { return 0 }
        switch worker.metadata["placement"] {
        case WorkerPlacement.sameHost.rawValue:
            return 10
        case WorkerPlacement.remote.rawValue:
            return 0
        default:
            return 5
        }
    }

    private func stateScore(for worker: WorkerRecord) -> Int {
        switch worker.state {
        case .idle:
            return 100
        case .busy:
            return 25
        case .draining:
            return -100
        case .drained:
            return -500
        case .offline:
            return -1_000
        }
    }

    private func generationScore(for worker: WorkerRecord) -> Int {
        worker.generation
    }

    private func capabilityScore(for worker: WorkerRecord) -> Int {
        -worker.capabilities.count
    }
}
