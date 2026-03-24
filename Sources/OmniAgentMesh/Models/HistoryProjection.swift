import Foundation

public struct HistoryProjection: Codable, Sendable, Equatable {
    public var taskBrief: String
    public var summaries: [String]
    public var parentExcerpts: [String]
    public var artifactRefs: [String]
    public var constraints: [String]
    public var expectedOutputs: [String]

    public init(
        taskBrief: String,
        summaries: [String] = [],
        parentExcerpts: [String] = [],
        artifactRefs: [String] = [],
        constraints: [String] = [],
        expectedOutputs: [String] = []
    ) {
        self.taskBrief = taskBrief
        self.summaries = summaries
        self.parentExcerpts = parentExcerpts
        self.artifactRefs = artifactRefs
        self.constraints = constraints
        self.expectedOutputs = expectedOutputs
    }
}
