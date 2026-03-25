import Foundation
import OmniAgentMesh

public struct OnboardingOutcome: Sendable, Equatable {
    public enum Disposition: String, Sendable {
        case allow
        case replyAndStop = "reply_and_stop"
    }

    public var disposition: Disposition
    public var message: String?

    public init(disposition: Disposition, message: String? = nil) {
        self.disposition = disposition
        self.message = message
    }
}

public actor OnboardingWizard {
    private let policyManager: ChannelPolicyManager

    public init(policyManager: ChannelPolicyManager) {
        self.policyManager = policyManager
    }

    public func evaluate(
        context: ChannelIngressContext,
        actorID: ActorID,
        workspace: WorkspaceRecord,
        binding: ChannelBinding
    ) async throws -> OnboardingOutcome? {
        let policy = try await policyManager.snapshot(
            context: context,
            actorID: actorID,
            workspace: workspace,
            binding: binding
        )

        switch context.channelKind {
        case .directMessage:
            switch policy.directMessagePolicy {
            case .open:
                return nil
            case .disabled:
                return OnboardingOutcome(
                    disposition: .replyAndStop,
                    message: "Direct messages are disabled for this workspace."
                )
            case .allowlist:
                guard policy.allowlisted else {
                    return OnboardingOutcome(
                        disposition: .replyAndStop,
                        message: "You are not allowlisted for this workspace."
                    )
                }
                return nil
            case .pairing:
                guard policy.allowlisted else {
                    return OnboardingOutcome(
                        disposition: .replyAndStop,
                        message: "You are not allowlisted for this workspace."
                    )
                }
                if policy.paired {
                    return nil
                }
                if let text = context.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                   text.lowercased().hasPrefix("/pair ") {
                    let code = text.dropFirst("/pair ".count).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if try await policyManager.claimPairingCode(code, actorID: actorID) != nil {
                        return OnboardingOutcome(
                            disposition: .replyAndStop,
                            message: "Pairing complete. You can continue."
                        )
                    }
                    return OnboardingOutcome(
                        disposition: .replyAndStop,
                        message: "That pairing code is invalid or expired."
                    )
                }
                let record = try await policyManager.issuePairingCode(
                    transport: context.transport,
                    actorExternalID: context.actorExternalID,
                    workspaceID: workspace.workspaceID
                )
                let code = record?.code ?? "UNKNOWN"
                return OnboardingOutcome(
                    disposition: .replyAndStop,
                    message: "Pairing required. Reply with `/pair \(code)` to continue."
                )
            }
        case .group, .topic, .api:
            if !policy.allowlisted {
                return OnboardingOutcome(
                    disposition: .replyAndStop,
                    message: "You are not allowlisted for this workspace."
                )
            }
            return nil
        }
    }
}
