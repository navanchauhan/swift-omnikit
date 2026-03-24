import Foundation

public enum WorkspacePermission: String, Codable, Sendable, CaseIterable, Comparable {
    case viewWorkspace
    case submitPrompt
    case answerQuestion
    case startMission
    case cancelMission
    case approveStandardInteraction
    case approveSensitiveInteraction
    case viewAuditTrail
    case bindChannel
    case manageMembers
    case administerWorkspace

    public static func < (lhs: WorkspacePermission, rhs: WorkspacePermission) -> Bool {
        lhs.rank < rhs.rank
    }

    public var minimumRole: WorkspaceMembership.Role {
        switch self {
        case .viewWorkspace, .viewAuditTrail:
            return .viewer
        case .submitPrompt, .answerQuestion, .startMission:
            return .member
        case .cancelMission, .approveStandardInteraction:
            return .admin
        case .approveSensitiveInteraction, .bindChannel, .manageMembers, .administerWorkspace:
            return .owner
        }
    }

    private var rank: Int {
        switch self {
        case .viewWorkspace:
            return 0
        case .submitPrompt:
            return 1
        case .answerQuestion:
            return 2
        case .startMission:
            return 3
        case .cancelMission:
            return 4
        case .approveStandardInteraction:
            return 5
        case .approveSensitiveInteraction:
            return 6
        case .viewAuditTrail:
            return 7
        case .bindChannel:
            return 8
        case .manageMembers:
            return 9
        case .administerWorkspace:
            return 10
        }
    }
}

public extension WorkspaceMembership {
    func allows(_ permission: WorkspacePermission) -> Bool {
        role >= permission.minimumRole
    }
}

public extension IdentityStore {
    func membershipRole(workspaceID: WorkspaceID, actorID: ActorID) async throws -> WorkspaceMembership.Role? {
        try await membership(workspaceID: workspaceID, actorID: actorID)?.role
    }

    func isAuthorized(
        workspaceID: WorkspaceID,
        actorID: ActorID,
        for permission: WorkspacePermission
    ) async throws -> Bool {
        guard let role = try await membershipRole(workspaceID: workspaceID, actorID: actorID) else {
            return false
        }
        return role >= permission.minimumRole
    }
}
