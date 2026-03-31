import Foundation
import OmniAgentMesh

public struct WorkspacePolicy: Sendable, Equatable {
    public enum SensitiveInteractionDelivery: String, Sendable {
        case sameChannel = "same_channel"
        case directMessage = "direct_message"
    }

    public var maxActiveMissions: Int
    public var maxBudgetUnits: Int
    public var maxRecursionDepth: Int
    public var maxStageAttempts: Int
    public var allowAmbientChannelHandling: Bool
    public var sensitiveInteractionDelivery: SensitiveInteractionDelivery
    public var defaultRepoChangesDeployable: Bool
    public var defaultDeploymentTarget: String?
    public var allowedDeploymentTargets: [String]
    public var requireDeploymentApproval: Bool
    public var allowAutomaticRollout: Bool

    public init(
        maxActiveMissions: Int = 8,
        maxBudgetUnits: Int = 16,
        maxRecursionDepth: Int = 2,
        maxStageAttempts: Int = 2,
        allowAmbientChannelHandling: Bool = false,
        sensitiveInteractionDelivery: SensitiveInteractionDelivery = .directMessage,
        defaultRepoChangesDeployable: Bool = false,
        defaultDeploymentTarget: String? = nil,
        allowedDeploymentTargets: [String] = [],
        requireDeploymentApproval: Bool = true,
        allowAutomaticRollout: Bool = false
    ) {
        self.maxActiveMissions = max(1, maxActiveMissions)
        self.maxBudgetUnits = max(1, maxBudgetUnits)
        self.maxRecursionDepth = max(0, maxRecursionDepth)
        self.maxStageAttempts = max(1, maxStageAttempts)
        self.allowAmbientChannelHandling = allowAmbientChannelHandling
        self.sensitiveInteractionDelivery = sensitiveInteractionDelivery
        self.defaultRepoChangesDeployable = defaultRepoChangesDeployable
        self.defaultDeploymentTarget = defaultDeploymentTarget?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.allowedDeploymentTargets = allowedDeploymentTargets
        self.requireDeploymentApproval = requireDeploymentApproval
        self.allowAutomaticRollout = allowAutomaticRollout
    }

    public static func resolve(from workspace: WorkspaceRecord?) -> WorkspacePolicy {
        guard let workspace else {
            return WorkspacePolicy()
        }
        return WorkspacePolicy(
            maxActiveMissions: parsePositiveInt(workspace.metadata["max_active_missions"]) ?? 8,
            maxBudgetUnits: parsePositiveInt(workspace.metadata["max_budget_units"]) ?? 16,
            maxRecursionDepth: parseNonNegativeInt(workspace.metadata["max_recursion_depth"]) ?? 2,
            maxStageAttempts: parsePositiveInt(workspace.metadata["max_stage_attempts"]) ?? 2,
            allowAmbientChannelHandling: parseBool(workspace.metadata["ambient_channel_handling"]) ?? false,
            sensitiveInteractionDelivery: {
                switch workspace.metadata["sensitive_interaction_delivery"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "same_channel":
                    return .sameChannel
                default:
                    return .directMessage
                }
            }(),
            defaultRepoChangesDeployable: parseBool(workspace.metadata["default_repo_changes_deployable"]) ?? false,
            defaultDeploymentTarget: workspace.metadata["default_deployment_target"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            allowedDeploymentTargets: parseCSV(workspace.metadata["deployment_targets"]),
            requireDeploymentApproval: parseBool(workspace.metadata["require_deployment_approval"]) ?? true,
            allowAutomaticRollout: parseBool(workspace.metadata["allow_automatic_rollout"]) ?? false
        )
    }
}

private func parsePositiveInt(_ rawValue: String?) -> Int? {
    guard let rawValue, let value = Int(rawValue), value > 0 else {
        return nil
    }
    return value
}

private func parseNonNegativeInt(_ rawValue: String?) -> Int? {
    guard let rawValue, let value = Int(rawValue), value >= 0 else {
        return nil
    }
    return value
}

private func parseBool(_ rawValue: String?) -> Bool? {
    switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "true", "1", "yes":
        return true
    case "false", "0", "no":
        return false
    default:
        return nil
    }
}

private func parseCSV(_ rawValue: String?) -> [String] {
    rawValue?
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty } ?? []
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
