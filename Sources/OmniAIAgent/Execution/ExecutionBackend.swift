import Foundation
import OmniExecution

/// Selects which execution backend to use for agent tool invocations.
public enum ExecutionBackend: Sendable {
    /// Use the host system directly (default, existing behavior)
    case local

    #if os(macOS) || os(Linux)
    /// Use a container-based execution environment
    case container(ContainerBackendConfig)
    #endif
}

#if os(macOS) || os(Linux)
/// Configuration for the container execution backend.
public struct ContainerBackendConfig: Sendable {
    /// Image reference (e.g., "alpine:minirootfs")
    public var imageRef: String
    /// Whether outbound networking is enabled (for apk, etc.)
    public var networkEnabled: Bool
    /// Host workspace directory to bind into container
    public var hostWorkspaceDir: String?

    public init(
        imageRef: String = "alpine:minirootfs",
        networkEnabled: Bool = false,
        hostWorkspaceDir: String? = nil
    ) {
        self.imageRef = imageRef
        self.networkEnabled = networkEnabled
        self.hostWorkspaceDir = hostWorkspaceDir
    }
}
#endif
