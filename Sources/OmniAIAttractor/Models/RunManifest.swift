import Foundation

public enum RunCompletionState: String, Codable, Sendable {
    case running
    case completed
    case failed
}

public struct RunManifest: Codable, Sendable {
    public var dotPath: String
    public var backend: String
    public var workingDirectory: String
    public var logsRoot: String
    public var currentNode: String?
    public var pid: Int32?
    public var createdAt: Date
    public var updatedAt: Date
    public var completionState: RunCompletionState

    public init(
        dotPath: String,
        backend: String,
        workingDirectory: String,
        logsRoot: String,
        currentNode: String? = nil,
        pid: Int32? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completionState: RunCompletionState = .running
    ) {
        self.dotPath = dotPath
        self.backend = backend
        self.workingDirectory = workingDirectory
        self.logsRoot = logsRoot
        self.currentNode = currentNode
        self.pid = pid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completionState = completionState
    }

    public mutating func beginRun(currentNode: String? = nil, at now: Date = Date()) {
        if let currentNode, !currentNode.isEmpty {
            self.currentNode = currentNode
        }
        self.pid = ProcessInfo.processInfo.processIdentifier
        self.updatedAt = now
        self.completionState = .running
    }

    public mutating func finish(
        state: RunCompletionState,
        currentNode: String? = nil,
        at now: Date = Date()
    ) {
        if let currentNode, !currentNode.isEmpty {
            self.currentNode = currentNode
        }
        self.pid = nil
        self.updatedAt = now
        self.completionState = state
    }

    public mutating func repairAfterUnexpectedExit(
        checkpoint: Checkpoint,
        at now: Date = Date()
    ) {
        if !checkpoint.currentNode.isEmpty {
            currentNode = checkpoint.currentNode
        }
        pid = nil
        updatedAt = max(updatedAt, max(checkpoint.timestamp, now))
        completionState = .failed
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> RunManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RunManifest.self, from: data)
    }
}
