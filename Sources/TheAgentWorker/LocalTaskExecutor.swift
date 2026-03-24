import Foundation
import OmniAgentMesh

public typealias LocalTaskProgressReporter = @Sendable (String, [String: String]) async throws -> Void

public struct LocalTaskExecutionArtifact: Sendable {
    public var name: String
    public var contentType: String
    public var data: Data

    public init(name: String, contentType: String, data: Data) {
        self.name = name
        self.contentType = contentType
        self.data = data
    }
}

public struct LocalTaskExecutionResult: Sendable {
    public var summary: String
    public var artifacts: [LocalTaskExecutionArtifact]
    public var metadata: [String: String]

    public init(
        summary: String,
        artifacts: [LocalTaskExecutionArtifact] = [],
        metadata: [String: String] = [:]
    ) {
        self.summary = summary
        self.artifacts = artifacts
        self.metadata = metadata
    }
}

public struct LocalTaskExecutor: Sendable {
    public typealias ExecutionHandler = @Sendable (TaskRecord, LocalTaskProgressReporter) async throws -> LocalTaskExecutionResult

    private let handler: ExecutionHandler

    public init(handler: ExecutionHandler? = nil) {
        self.handler = handler ?? { task, reportProgress in
            try await Self.defaultHandler(task: task, reportProgress: reportProgress)
        }
    }

    public func execute(task: TaskRecord, reportProgress: LocalTaskProgressReporter) async throws -> LocalTaskExecutionResult {
        try await handler(task, reportProgress)
    }

    private static func defaultHandler(
        task: TaskRecord,
        reportProgress: LocalTaskProgressReporter
    ) async throws -> LocalTaskExecutionResult {
        try await reportProgress("Started local execution", ["task_id": task.taskID])
        try Task.checkCancellation()
        return LocalTaskExecutionResult(summary: "Completed local task: \(task.historyProjection.taskBrief)")
    }
}
