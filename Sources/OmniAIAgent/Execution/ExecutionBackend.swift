import Foundation
import OmniExecution

/// Selects which execution backend to use for agent tool invocations.
public enum ExecutionBackend: Sendable {
    /// Use the host system directly (default, existing behavior)
    case local

    /// Use SwiftBash in-process for shell commands.
    case swiftBash(SwiftBashBackendConfig = SwiftBashBackendConfig())

    /// Use a container-based execution environment
    case container(ContainerBackendConfig)
}

/// Configuration for the SwiftBash execution backend.
public struct SwiftBashBackendConfig: Sendable {
    /// Filesystem model used by the in-process shell.
    public enum FileSystemMode: Sendable, Equatable {
        /// Use the host filesystem directly.
        case realFileSystem
        /// Mount the working directory as a copy-on-write sandbox at the shell working directory.
        case sandboxedWorkspace
        /// Use an empty in-memory filesystem.
        case inMemory
    }

    /// Filesystem model used by the in-process shell.
    public var fileSystemMode: FileSystemMode
    /// Whether to expose the real host identity and inherited environment to shell commands.
    public var useHostEnvironment: Bool
    /// Whether network access is allowed for SwiftBash commands such as curl.
    public var networkEnabled: Bool
    /// URL prefixes allowed when network access is enabled.
    public var allowedURLPrefixes: [String]
    /// Explicit escape hatch for unrestricted public internet access.
    public var allowFullInternetAccess: Bool
    /// Reuse one SwiftBash shell across execCommand calls.
    public var persistentSession: Bool

    public init(
        fileSystemMode: FileSystemMode = .sandboxedWorkspace,
        useHostEnvironment: Bool = false,
        networkEnabled: Bool = false,
        allowedURLPrefixes: [String] = [],
        allowFullInternetAccess: Bool = false,
        persistentSession: Bool = false
    ) {
        self.fileSystemMode = fileSystemMode
        self.useHostEnvironment = useHostEnvironment
        self.networkEnabled = networkEnabled
        self.allowedURLPrefixes = allowedURLPrefixes
        self.allowFullInternetAccess = allowFullInternetAccess
        self.persistentSession = persistentSession
    }
}

/// Configuration for the container execution backend.
public struct ContainerBackendConfig: Sendable {
    /// Image reference (e.g., "alpine:minirootfs")
    public var imageRef: String
    /// Whether outbound networking is enabled (for apk, etc.)
    public var networkEnabled: Bool
    /// Host workspace directory to bind into container
    public var hostWorkspaceDir: String?
    /// Optional host directory to bind for persistent guest state.
    public var hostStateDir: String?
    /// Optional guest home directory. When set, HOME will point here.
    public var guestHomeDir: String?

    public init(
        imageRef: String = "alpine:minirootfs",
        networkEnabled: Bool = false,
        hostWorkspaceDir: String? = nil,
        hostStateDir: String? = nil,
        guestHomeDir: String? = nil
    ) {
        self.imageRef = imageRef
        self.networkEnabled = networkEnabled
        self.hostWorkspaceDir = hostWorkspaceDir
        self.hostStateDir = hostStateDir
        self.guestHomeDir = guestHomeDir
    }
}
