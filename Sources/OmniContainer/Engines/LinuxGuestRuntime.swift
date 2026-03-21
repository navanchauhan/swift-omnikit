import Foundation
import OmniExecution
import OmniVFS

/// Linux-compatible execution backend for guest shells and ELF binaries.
public protocol LinuxGuestRuntime: ContainerRuntime {
    /// Execute a shell command string through the backend's default shell.
    func executeShell(
        command: String,
        env: [String: String],
        workingDir: String,
        namespace: VFSNamespace,
        timeoutMs: Int
    ) async throws -> ExecResult
}
