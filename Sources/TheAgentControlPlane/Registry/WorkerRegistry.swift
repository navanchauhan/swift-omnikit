import Foundation
import OmniAgentMesh

public enum WorkerPlacement: String, Sendable {
    case sameHost = "same_host"
    case remote
}

public actor WorkerRegistry {
    private let jobStore: any JobStore
    private var dispatchers: [String: any WorkerDispatching] = [:]

    public init(jobStore: any JobStore) {
        self.jobStore = jobStore
    }

    public func register(
        _ worker: any WorkerDispatching,
        placement: WorkerPlacement,
        at: Date = Date(),
        metadata: [String: String] = [:]
    ) async throws {
        var registrationMetadata = metadata
        registrationMetadata["placement"] = placement.rawValue
        _ = try await worker.register(at: at, metadata: registrationMetadata)
        dispatchers[worker.workerID] = worker
    }

    public func dispatcher(workerID: String) -> (any WorkerDispatching)? {
        dispatchers[workerID]
    }

    public func records() async throws -> [WorkerRecord] {
        try await jobStore.workers()
    }

    public func matchingDispatchers(
        for task: TaskRecord,
        matcher: CapabilityMatcher,
        now: Date = Date()
    ) async throws -> [any WorkerDispatching] {
        let ranked = matcher.rank(
            task: task,
            workers: try await jobStore.workers(),
            now: now
        )
        return ranked.compactMap { dispatchers[$0.workerID] }
    }
}
