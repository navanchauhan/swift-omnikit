import Foundation
import OmniVFS
import OmniExecution

/// Protocol for execution engines (blink, WasmKit).
public protocol ContainerRuntime: Sendable {
    /// Check if this runtime can execute the given binary data.
    func canExecute(_ data: [UInt8]) -> Bool

    /// Execute a binary with the given arguments and environment.
    func execute(
        binaryPath: String,
        args: [String],
        env: [String: String],
        workingDir: String,
        namespace: VFSNamespace,
        timeoutMs: Int
    ) async throws -> ExecResult
}
