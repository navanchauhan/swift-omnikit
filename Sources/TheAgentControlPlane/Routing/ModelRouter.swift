import Foundation
import OmniAgentMesh

public struct ModelRoutingRequest: Sendable, Equatable {
    public var explicitTier: ModelRoutePolicy.Tier?
    public var stageKind: MissionStageRecord.Kind?
    public var requiresCoding: Bool
    public var hasAttachments: Bool
    public var budgetUnits: Int
    public var preferredTierHint: String?

    public init(
        explicitTier: ModelRoutePolicy.Tier? = nil,
        stageKind: MissionStageRecord.Kind? = nil,
        requiresCoding: Bool = false,
        hasAttachments: Bool = false,
        budgetUnits: Int = 1,
        preferredTierHint: String? = nil
    ) {
        self.explicitTier = explicitTier
        self.stageKind = stageKind
        self.requiresCoding = requiresCoding
        self.hasAttachments = hasAttachments
        self.budgetUnits = budgetUnits
        self.preferredTierHint = preferredTierHint
    }
}

public struct ModelRoutingDecision: Sendable, Equatable {
    public var tier: ModelRoutePolicy.Tier
    public var provider: String
    public var model: String
    public var reasoningEffort: String
    public var reason: String

    public init(
        tier: ModelRoutePolicy.Tier,
        provider: String,
        model: String,
        reasoningEffort: String,
        reason: String
    ) {
        self.tier = tier
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.reason = reason
    }

    public var metadata: [String: String] {
        [
            "model_route_tier": tier.rawValue,
            "model_route_provider": provider,
            "model_route_model": model,
            "model_route_reasoning_effort": reasoningEffort,
            "model_route_reason": reason,
        ]
    }
}

public actor ModelRouter {
    private let policy: ModelRoutePolicy

    public init(policy: ModelRoutePolicy = ModelRoutePolicy()) {
        self.policy = policy
    }

    public func route(for request: ModelRoutingRequest) -> ModelRoutingDecision {
        let resolvedTier: ModelRoutePolicy.Tier
        let reason: String

        if let explicitTier = request.explicitTier {
            resolvedTier = explicitTier
            reason = "explicit"
        } else if let preferredTierHint = request.preferredTierHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  let tier = ModelRoutePolicy.Tier(rawValue: preferredTierHint) {
            resolvedTier = tier
            reason = "skill_hint"
        } else if request.hasAttachments {
            resolvedTier = .vision
            reason = "attachments"
        } else if request.requiresCoding {
            resolvedTier = .codergen
            reason = "coding"
        } else if let stageKind = request.stageKind {
            switch stageKind {
            case .plan:
                resolvedTier = .planner
                reason = "stage_plan"
            case .implement:
                resolvedTier = .implementer
                reason = "stage_implement"
            case .review, .scenario, .judge:
                resolvedTier = .reviewer
                reason = "stage_validate"
            case .approval, .question, .finalize, .direct:
                resolvedTier = request.budgetUnits <= 1 ? .chatLight : .chatDeep
                reason = "stage_interaction"
            }
        } else if request.budgetUnits <= 1 {
            resolvedTier = .chatLight
            reason = "budget_light"
        } else {
            resolvedTier = .chatDeep
            reason = "default"
        }

        let entry = policy.entries[resolvedTier] ?? ModelRoutePolicy.defaultEntries[resolvedTier]!
        return ModelRoutingDecision(
            tier: resolvedTier,
            provider: entry.provider,
            model: entry.model,
            reasoningEffort: entry.reasoningEffort,
            reason: reason
        )
    }

    public func supportedTiers() -> [String] {
        policy.entries.keys.map(\.rawValue).sorted()
    }
}
