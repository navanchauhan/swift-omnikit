import Foundation

public enum Role: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
    case developer
}
