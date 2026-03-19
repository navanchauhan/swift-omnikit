import Foundation
import OmniVFS
import OmniExecution

/// Per-exec session with cloned namespace and environment.
public struct ExecSession: Sendable {
    public let namespace: VFSNamespace
    public let env: [String: String]
    public let workingDir: String

    public init(namespace: VFSNamespace, env: [String: String], workingDir: String) {
        self.namespace = namespace
        self.env = env
        self.workingDir = workingDir
    }
}
