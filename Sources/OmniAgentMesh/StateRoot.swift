import Foundation

public struct AgentFabricStateRoot: Sendable, Equatable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public static func workingDirectoryDefault() -> AgentFabricStateRoot {
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return AgentFabricStateRoot(
            rootDirectory: workingDirectory.appending(path: ".ai/the-agent", directoryHint: .isDirectory)
        )
    }

    public var conversationDatabaseURL: URL {
        rootDirectory.appending(path: "conversation.sqlite")
    }

    public var identityDatabaseURL: URL {
        rootDirectory.appending(path: "identity.sqlite")
    }

    public var jobsDatabaseURL: URL {
        rootDirectory.appending(path: "jobs.sqlite")
    }

    public var missionsDatabaseURL: URL {
        rootDirectory.appending(path: "missions.sqlite")
    }

    public var deploymentDatabaseURL: URL {
        rootDirectory.appending(path: "deploy.sqlite")
    }

    public var artifactsDirectoryURL: URL {
        rootDirectory.appending(path: "artifacts", directoryHint: .isDirectory)
    }

    public var releasesDirectoryURL: URL {
        rootDirectory.appending(path: "releases", directoryHint: .isDirectory)
    }

    public var checkpointsDirectoryURL: URL {
        rootDirectory.appending(path: "checkpoints", directoryHint: .isDirectory)
    }

    public func prepare() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artifactsDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: releasesDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkpointsDirectoryURL, withIntermediateDirectories: true)
    }
}
