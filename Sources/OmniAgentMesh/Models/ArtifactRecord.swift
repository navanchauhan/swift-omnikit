import Foundation

public struct ArtifactRecord: Codable, Sendable, Equatable {
    public var artifactID: String
    public var taskID: String?
    public var name: String
    public var relativePath: String
    public var contentType: String
    public var byteCount: Int
    public var createdAt: Date

    public init(
        artifactID: String = UUID().uuidString,
        taskID: String? = nil,
        name: String,
        relativePath: String,
        contentType: String,
        byteCount: Int,
        createdAt: Date = Date()
    ) {
        self.artifactID = artifactID
        self.taskID = taskID
        self.name = name
        self.relativePath = relativePath
        self.contentType = contentType
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}
