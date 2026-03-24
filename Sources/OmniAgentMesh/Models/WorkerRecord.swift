import Foundation

public struct WorkerRecord: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case idle
        case busy
        case offline
        case draining
    }

    public var workerID: String
    public var displayName: String
    public var capabilities: [String]
    public var state: State
    public var lastHeartbeatAt: Date
    public var metadata: [String: String]

    public init(
        workerID: String = UUID().uuidString,
        displayName: String,
        capabilities: [String],
        state: State = .idle,
        lastHeartbeatAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.workerID = workerID
        self.displayName = displayName
        self.capabilities = Array(Set(capabilities)).sorted()
        self.state = state
        self.lastHeartbeatAt = lastHeartbeatAt
        self.metadata = metadata
    }
}
