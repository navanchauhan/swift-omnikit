/// Errors specific to container lifecycle and operations.
public enum ContainerError: Error, Sendable {
    case invalidStateTransition(from: ContainerState, to: ContainerState)
    case notRunning
    case engineNotAvailable(String)
    case executionFailed(String)
}
