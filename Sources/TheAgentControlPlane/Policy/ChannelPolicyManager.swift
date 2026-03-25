import Foundation
import OmniAgentMesh

public struct ChannelIngressContext: Sendable, Equatable {
    public enum ChannelKind: String, Sendable {
        case directMessage
        case group
        case topic
        case api
    }

    public var transport: ChannelBinding.Transport
    public var actorExternalID: String
    public var channelKind: ChannelKind
    public var text: String?

    public init(
        transport: ChannelBinding.Transport,
        actorExternalID: String,
        channelKind: ChannelKind,
        text: String? = nil
    ) {
        self.transport = transport
        self.actorExternalID = actorExternalID
        self.channelKind = channelKind
        self.text = text
    }
}

public struct ChannelPolicySnapshot: Sendable, Equatable {
    public enum DirectMessagePolicy: String, Sendable {
        case pairing
        case allowlist
        case open
        case disabled
    }

    public var directMessagePolicy: DirectMessagePolicy
    public var requireMention: Bool
    public var ambientMessagesEnabled: Bool
    public var allowlisted: Bool
    public var paired: Bool

    public init(
        directMessagePolicy: DirectMessagePolicy,
        requireMention: Bool,
        ambientMessagesEnabled: Bool,
        allowlisted: Bool,
        paired: Bool
    ) {
        self.directMessagePolicy = directMessagePolicy
        self.requireMention = requireMention
        self.ambientMessagesEnabled = ambientMessagesEnabled
        self.allowlisted = allowlisted
        self.paired = paired
    }
}

public actor ChannelPolicyManager {
    private let identityStore: any IdentityStore
    private let pairingStore: PairingStore?

    public init(
        identityStore: any IdentityStore,
        pairingStore: PairingStore? = nil
    ) {
        self.identityStore = identityStore
        self.pairingStore = pairingStore
    }

    public func snapshot(
        context: ChannelIngressContext,
        actorID: ActorID,
        workspace: WorkspaceRecord,
        binding: ChannelBinding
    ) async throws -> ChannelPolicySnapshot {
        let requireMention = binding.metadata["require_mention"]?.lowercased() != "false"
        let ambientMessagesEnabled = binding.metadata["ambient_messages_enabled"] == "true" ||
            workspace.metadata["ambient_channel_handling"] == "true"
        let paired = try await isActorPaired(actorID: actorID)
        let allowlisted = try await isAllowlisted(
            context: context,
            actorID: actorID,
            externalActorID: context.actorExternalID,
            workspace: workspace
        )
        return ChannelPolicySnapshot(
            directMessagePolicy: directMessagePolicy(for: workspace, transport: context.transport),
            requireMention: requireMention,
            ambientMessagesEnabled: ambientMessagesEnabled,
            allowlisted: allowlisted,
            paired: paired
        )
    }

    public func directMessagePolicy(
        for workspace: WorkspaceRecord,
        transport: ChannelBinding.Transport
    ) -> ChannelPolicySnapshot.DirectMessagePolicy {
        if let explicit = workspace.metadata["dm_policy"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let policy = ChannelPolicySnapshot.DirectMessagePolicy(rawValue: explicit) {
            return policy
        }
        return transport == .telegram ? .pairing : .open
    }

    public func isActorPaired(actorID: ActorID) async throws -> Bool {
        try await identityStore.actor(actorID: actorID)?.metadata["paired"] == "true"
    }

    public func markActorPaired(actorID: ActorID) async throws {
        guard var actor = try await identityStore.actor(actorID: actorID) else {
            return
        }
        actor.metadata["paired"] = "true"
        actor.updatedAt = Date()
        try await identityStore.saveActor(actor)
    }

    public func issuePairingCode(
        transport: ChannelBinding.Transport,
        actorExternalID: String,
        workspaceID: WorkspaceID? = nil
    ) async throws -> PairingRecord? {
        guard let pairingStore else {
            return nil
        }
        return try await pairingStore.issueCode(
            transport: transport,
            actorExternalID: actorExternalID,
            workspaceID: workspaceID
        )
    }

    public func claimPairingCode(
        _ code: String,
        actorID: ActorID
    ) async throws -> PairingRecord? {
        guard let pairingStore else {
            return nil
        }
        guard let record = try await pairingStore.claim(code: code, actorID: actorID) else {
            return nil
        }
        try await markActorPaired(actorID: actorID)
        return record
    }

    private func isAllowlisted(
        context: ChannelIngressContext,
        actorID: ActorID,
        externalActorID: String,
        workspace: WorkspaceRecord
    ) async throws -> Bool {
        let workspaceActorAllowlist = WorkspaceAllowlist.actorIDs(from: workspace)
        let workspaceExternalAllowlist = WorkspaceAllowlist.externalActorIDs(from: workspace)
        let globalMetadata = try await globalPolicyMetadata()
        let globalActorAllowlist = WorkspaceAllowlist.globalActorIDs(
            from: globalMetadata,
            transport: context.transport
        )
        let globalExternalAllowlist = WorkspaceAllowlist.globalExternalActorIDs(
            from: globalMetadata,
            transport: context.transport
        )

        if workspaceActorAllowlist.contains(actorID) ||
            workspaceExternalAllowlist.contains(externalActorID) ||
            globalActorAllowlist.contains(actorID) ||
            globalExternalAllowlist.contains(externalActorID) {
            return true
        }

        let hasExplicitAllowlist =
            !workspaceActorAllowlist.isEmpty ||
            !workspaceExternalAllowlist.isEmpty ||
            !globalActorAllowlist.isEmpty ||
            !globalExternalAllowlist.isEmpty
        let directMessageRequiresExplicitAllowlist =
            context.channelKind == .directMessage &&
            directMessagePolicy(for: workspace, transport: context.transport) == .allowlist

        if hasExplicitAllowlist || directMessageRequiresExplicitAllowlist {
            return false
        }

        if context.channelKind != .directMessage,
           try await identityStore.membership(workspaceID: workspace.workspaceID, actorID: actorID) != nil {
            return true
        }
        return true
    }

    private func globalPolicyMetadata() async throws -> [String: String] {
        guard let rootWorkspace = try await identityStore.workspace(workspaceID: WorkspaceID(rawValue: "root")) else {
            return [:]
        }
        return rootWorkspace.metadata
    }
}
