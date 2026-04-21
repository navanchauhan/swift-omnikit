import Foundation
import OmniExecution

/// Selects which execution backend to use for agent tool invocations.
public enum ExecutionBackend: Sendable {
    /// Use the host system directly (default, existing behavior)
    case local

    /// Use a container-based execution environment
    case container(ContainerBackendConfig)
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
