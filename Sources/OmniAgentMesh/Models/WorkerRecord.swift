import Foundation

public struct WorkerRecord: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case workerID
        case displayName
        case capabilities
        case state
        case generation
        case lastHeartbeatAt
        case metadata
    }

    public enum State: String, Codable, Sendable {
        case idle
        case busy
        case offline
        case draining
        case drained
    }

    public var workerID: String
    public var displayName: String
    public var capabilities: [String]
    public var state: State
    public var generation: Int
    public var lastHeartbeatAt: Date
    public var metadata: [String: String]

    public init(
        workerID: String = UUID().uuidString,
        displayName: String,
        capabilities: [String],
        state: State = .idle,
        generation: Int = 0,
        lastHeartbeatAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.workerID = workerID
        self.displayName = displayName
        self.capabilities = Array(Set(capabilities)).sorted()
        self.state = state
        self.generation = max(0, generation)
        self.lastHeartbeatAt = lastHeartbeatAt
        self.metadata = metadata
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.workerID = try container.decode(String.self, forKey: .workerID)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.capabilities = try container.decode([String].self, forKey: .capabilities)
        self.state = try container.decode(State.self, forKey: .state)
        self.generation = try container.decodeIfPresent(Int.self, forKey: .generation) ?? 0
        self.lastHeartbeatAt = try container.decode(Date.self, forKey: .lastHeartbeatAt)
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workerID, forKey: .workerID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(state, forKey: .state)
        try container.encode(generation, forKey: .generation)
        try container.encode(lastHeartbeatAt, forKey: .lastHeartbeatAt)
        try container.encode(metadata, forKey: .metadata)
    }
}
