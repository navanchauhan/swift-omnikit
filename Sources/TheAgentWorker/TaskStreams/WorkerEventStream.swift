import Foundation
import OmniAgentMesh

public actor WorkerEventStream {
    private var allEvents: [TaskEvent] = []
    private var continuations: [UUID: AsyncStream<TaskEvent>.Continuation] = [:]

    public init() {}

    public func publish(_ event: TaskEvent) {
        allEvents.append(event)
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    public func history(taskID: String? = nil, afterSequence: Int? = nil) -> [TaskEvent] {
        allEvents.filter { event in
            let matchesTask = taskID.map { event.taskID == $0 } ?? true
            let matchesSequence = afterSequence.map { event.sequenceNumber > $0 } ?? true
            return matchesTask && matchesSequence
        }
    }

    public func stream(taskID: String? = nil, afterSequence: Int? = nil) -> AsyncStream<TaskEvent> {
        let replay = history(taskID: taskID, afterSequence: afterSequence)
        return AsyncStream { continuation in
            let identifier = UUID()
            continuations[identifier] = continuation
            for event in replay {
                continuation.yield(event)
            }
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(identifier)
                }
            }
        }
    }

    private func removeContinuation(_ identifier: UUID) {
        continuations.removeValue(forKey: identifier)
    }
}
