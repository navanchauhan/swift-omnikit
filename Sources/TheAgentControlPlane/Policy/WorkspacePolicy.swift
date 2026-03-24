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

    public init(
        maxActiveMissions: Int = 8,
        maxBudgetUnits: Int = 16,
        maxRecursionDepth: Int = 2,
        maxStageAttempts: Int = 2,
        allowAmbientChannelHandling: Bool = false,
        sensitiveInteractionDelivery: SensitiveInteractionDelivery = .directMessage
    ) {
        self.maxActiveMissions = max(1, maxActiveMissions)
        self.maxBudgetUnits = max(1, maxBudgetUnits)
        self.maxRecursionDepth = max(0, maxRecursionDepth)
        self.maxStageAttempts = max(1, maxStageAttempts)
        self.allowAmbientChannelHandling = allowAmbientChannelHandling
        self.sensitiveInteractionDelivery = sensitiveInteractionDelivery
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
            }()
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
