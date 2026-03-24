import Foundation
import OmniAgentMesh

public struct HistoryProjectionBounds: Sendable, Equatable {
    public var maxSummaries: Int
    public var maxParentExcerpts: Int
    public var maxArtifacts: Int

    public init(
        maxSummaries: Int = 6,
        maxParentExcerpts: Int = 6,
        maxArtifacts: Int = 8
    ) {
        self.maxSummaries = max(1, maxSummaries)
        self.maxParentExcerpts = max(1, maxParentExcerpts)
        self.maxArtifacts = max(1, maxArtifacts)
    }
}

public actor HistoryProjectionBuilder {
    private let jobStore: any JobStore
    private let bounds: HistoryProjectionBounds

    public init(
        jobStore: any JobStore,
        bounds: HistoryProjectionBounds = HistoryProjectionBounds()
    ) {
        self.jobStore = jobStore
        self.bounds = bounds
    }

    public func buildChildProjection(
        parentTaskID: String,
        brief: String,
        constraints: [String] = [],
        expectedOutputs: [String] = [],
        artifactRefs: [String] = []
    ) async throws -> HistoryProjection {
        guard let parent = try await jobStore.task(taskID: parentTaskID) else {
            throw JobStoreError.taskNotFound(parentTaskID)
        }
        return try await buildChildProjection(
            parentTask: parent,
            brief: brief,
            constraints: constraints,
            expectedOutputs: expectedOutputs,
            artifactRefs: artifactRefs
        )
    }

    public func buildChildProjection(
        parentTask: TaskRecord,
        brief: String,
        constraints: [String] = [],
        expectedOutputs: [String] = [],
        artifactRefs: [String] = []
    ) async throws -> HistoryProjection {
        let parentEvents = try await jobStore.events(taskID: parentTask.taskID, afterSequence: nil)

        let inheritedSummaries = parentTask.historyProjection.summaries
        let progressSummaries = parentEvents
            .filter { [.started, .progress, .waiting, .resumed, .completed, .failed].contains($0.kind) }
            .compactMap(\.summary)
        let summaries = Array((inheritedSummaries + progressSummaries).suffix(bounds.maxSummaries))

        let parentExcerpts = Array(
            (parentTask.historyProjection.parentExcerpts + parentEvents.compactMap(\.summary))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .suffix(bounds.maxParentExcerpts)
        )

        let mergedArtifacts = Array(
            Set(parentTask.artifactRefs + parentTask.historyProjection.artifactRefs + artifactRefs)
        )
            .sorted()
            .suffix(bounds.maxArtifacts)

        return HistoryProjection(
            taskBrief: brief,
            summaries: summaries,
            parentExcerpts: parentExcerpts,
            artifactRefs: Array(mergedArtifacts),
            constraints: constraints,
            expectedOutputs: expectedOutputs
        )
    }
}
