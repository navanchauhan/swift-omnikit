import Foundation

public enum SessionState: String, Sendable {
    case idle = "idle"
    case processing = "processing"
    case awaitingInput = "awaiting_input"
    case closed = "closed"
}
