import Foundation

/// How container filesystem changes persist (or don't).
public enum PersistenceMode: Sendable, Codable, Hashable {
    case ephemeral
    case overlayPersistent(path: String)
}

/// Configuration for creating a container.
public struct ContainerSpec: Sendable, Codable {
    /// Image reference, e.g. "alpine:minirootfs".
    public var imageRef: String

    /// Environment variables injected into the container.
    public var env: [String: String]

    /// Guest working directory (default "/workspace").
    public var workingDir: String

    /// Optional host directory to bind-mount at /workspace.
    public var hostWorkspaceDir: String?

    /// Memory limit for the overlay filesystem in megabytes.
    public var memoryLimitMB: Int

    /// Maximum execution time in seconds.
    public var timeoutSeconds: Int

    /// Filesystem persistence mode.
    public var persistenceMode: PersistenceMode

    /// Capabilities granted to the container.
    public var capabilities: Set<ContainerCapability>

    public init(
        imageRef: String = "alpine:minirootfs",
        env: [String: String] = [:],
        workingDir: String = "/workspace",
        hostWorkspaceDir: String? = nil,
        memoryLimitMB: Int = 256,
        timeoutSeconds: Int = 300,
        persistenceMode: PersistenceMode = .ephemeral,
        capabilities: Set<ContainerCapability> = []
    ) {
        self.imageRef = imageRef
        self.env = env
        self.workingDir = workingDir
        self.hostWorkspaceDir = hostWorkspaceDir
        self.memoryLimitMB = memoryLimitMB
        self.timeoutSeconds = timeoutSeconds
        self.persistenceMode = persistenceMode
        self.capabilities = capabilities
    }
}
