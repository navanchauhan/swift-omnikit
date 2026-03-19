import Foundation

/// Lifecycle state of a container.
public enum ContainerState: Sendable, Equatable {
    case created
    case running
    case stopped(exitCode: Int32)
    case destroyed
}

/// Unique identifier for a container instance.
public struct ContainerID: Sendable, Hashable, CustomStringConvertible, Codable {
    public let uuid: UUID

    public init(_ uuid: UUID = UUID()) {
        self.uuid = uuid
    }

    public var description: String {
        uuid.uuidString.prefix(8).lowercased()
    }
}
