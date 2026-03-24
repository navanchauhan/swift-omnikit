import Foundation

public struct WorkspaceMembership: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable, Comparable {
        case owner
        case admin
        case member
        case viewer

        public static func < (lhs: Role, rhs: Role) -> Bool {
            lhs.rank < rhs.rank
        }

        private var rank: Int {
            switch self {
            case .viewer:
                return 0
            case .member:
                return 1
            case .admin:
                return 2
            case .owner:
                return 3
            }
        }
    }

    public var workspaceID: WorkspaceID
    public var actorID: ActorID
    public var role: Role
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        workspaceID: WorkspaceID,
        actorID: ActorID,
        role: Role,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.workspaceID = workspaceID
        self.actorID = actorID
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
