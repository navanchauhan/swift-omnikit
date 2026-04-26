import Foundation
import OmniAgentMesh

public enum ChannelActionCapability: String, Codable, Sendable, CaseIterable {
    case react
    case setReplyEffect
    case typing
    case draft
    case confirm
    case send
}

public enum ChannelSideEffectKind: String, Codable, Sendable, CaseIterable {
    case sendMessage = "SendMessage"
    case displayDraft = "DisplayDraft"
    case reactToMessage = "ReactToMessage"
    case wait = "Wait"
    case executeDraft = "ExecuteDraft"
    case setReplyEffect = "SetReplyEffect"
    case typing = "Typing"
}

public struct ChannelActionResult: Sendable, Equatable {
    public var sideEffect: ChannelSideEffectKind
    public var transport: ChannelBinding.Transport
    public var targetExternalID: String
    public var messageID: String?
    public var metadata: [String: String]

    public init(
        sideEffect: ChannelSideEffectKind,
        transport: ChannelBinding.Transport,
        targetExternalID: String,
        messageID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.sideEffect = sideEffect
        self.transport = transport
        self.targetExternalID = targetExternalID
        self.messageID = messageID
        self.metadata = metadata
    }
}

public struct ChannelActionContext: Sendable, Equatable {
    public var sessionID: String
    public var transport: ChannelBinding.Transport
    public var targetExternalID: String
    public var sourceMessageID: String?
    public var workspaceID: WorkspaceID
    public var channelID: ChannelID
    public var actorID: ActorID?
    public var actorExternalID: String?
    public var actorDisplayName: String?
    public var channelKind: String
    public var inboundEventKind: String

    public init(
        sessionID: String,
        transport: ChannelBinding.Transport,
        targetExternalID: String,
        sourceMessageID: String? = nil,
        workspaceID: WorkspaceID,
        channelID: ChannelID,
        actorID: ActorID? = nil,
        actorExternalID: String? = nil,
        actorDisplayName: String? = nil,
        channelKind: String = "api",
        inboundEventKind: String
    ) {
        self.sessionID = sessionID
        self.transport = transport
        self.targetExternalID = targetExternalID
        self.sourceMessageID = sourceMessageID
        self.workspaceID = workspaceID
        self.channelID = channelID
        self.actorID = actorID
        self.actorExternalID = actorExternalID
        self.actorDisplayName = actorDisplayName
        self.channelKind = channelKind
        self.inboundEventKind = inboundEventKind
    }
}

public struct PendingChannelArtifactSend: Sendable, Equatable {
    public var sequence: Int
    public var transport: ChannelBinding.Transport
    public var targetExternalID: String
    public var workspaceID: WorkspaceID
    public var channelID: ChannelID
    public var actorID: ActorID?
    public var artifactID: String
    public var caption: String?
    public var metadata: [String: String]

    public init(
        sequence: Int = 0,
        transport: ChannelBinding.Transport,
        targetExternalID: String,
        workspaceID: WorkspaceID,
        channelID: ChannelID,
        actorID: ActorID? = nil,
        artifactID: String,
        caption: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.sequence = sequence
        self.transport = transport
        self.targetExternalID = targetExternalID
        self.workspaceID = workspaceID
        self.channelID = channelID
        self.actorID = actorID
        self.artifactID = artifactID
        self.caption = caption
        self.metadata = metadata
    }
}

public struct PendingChannelMessageSend: Sendable, Equatable {
    public var sequence: Int
    public var transport: ChannelBinding.Transport
    public var targetExternalID: String
    public var workspaceID: WorkspaceID
    public var channelID: ChannelID
    public var actorID: ActorID?
    public var text: String
    public var metadata: [String: String]

    public init(
        sequence: Int = 0,
        transport: ChannelBinding.Transport,
        targetExternalID: String,
        workspaceID: WorkspaceID,
        channelID: ChannelID,
        actorID: ActorID? = nil,
        text: String,
        metadata: [String: String] = [:]
    ) {
        self.sequence = sequence
        self.transport = transport
        self.targetExternalID = targetExternalID
        self.workspaceID = workspaceID
        self.channelID = channelID
        self.actorID = actorID
        self.text = text
        self.metadata = metadata
    }
}

public protocol ChannelActionPerforming: Sendable {
    var channelActionCapabilities: Set<ChannelActionCapability> { get }

    func react(
        targetExternalID: String,
        messageID: String,
        reaction: String,
        partIndex: Int,
        emoji: String?
    ) async throws -> ChannelActionResult
}

public enum ChannelActionRegistryError: Error, CustomStringConvertible, Sendable {
    case unavailable(ChannelBinding.Transport)
    case missingCurrentContext(sessionID: String)
    case missingTargetExternalID
    case missingSourceMessageID
    case emptyMessageText
    case unsupportedCapability(ChannelActionCapability, ChannelBinding.Transport)

    public var description: String {
        switch self {
        case .unavailable(let transport):
            return "No channel action service is available for \(transport.rawValue)."
        case .missingCurrentContext(let sessionID):
            return "No current channel action context is available for session \(sessionID)."
        case .missingTargetExternalID:
            return "No current channel target is available; pass target_external_id explicitly."
        case .missingSourceMessageID:
            return "No current source message is available; pass message_id explicitly."
        case .emptyMessageText:
            return "Cannot send an empty channel message."
        case .unsupportedCapability(let capability, let transport):
            return "Channel \(transport.rawValue) does not support \(capability.rawValue)."
        }
    }
}

public actor ChannelActionRegistry {
    public static let shared = ChannelActionRegistry()

    private var performers: [ChannelBinding.Transport: any ChannelActionPerforming] = [:]
    private var currentContexts: [String: ChannelActionContext] = [:]
    private var pendingReplyEffects: [String: String] = [:]
    private var pendingWaits: [String: ChannelActionResult] = [:]
    private var pendingMessageSends: [String: [PendingChannelMessageSend]] = [:]
    private var pendingArtifactSends: [String: [PendingChannelArtifactSend]] = [:]
    private var pendingSequenceBySession: [String: Int] = [:]

    public init() {}

    public func register(_ performer: any ChannelActionPerforming, for transport: ChannelBinding.Transport) {
        performers[transport] = performer
    }

    public func unregister(transport: ChannelBinding.Transport) {
        performers[transport] = nil
    }

    public func updateCurrentContext(_ context: ChannelActionContext) {
        currentContexts[context.sessionID] = context
    }

    public func currentContext(sessionID: String) -> ChannelActionContext? {
        currentContexts[sessionID]
    }

    public func react(
        sessionID: String,
        transport explicitTransport: ChannelBinding.Transport?,
        targetExternalID explicitTargetExternalID: String?,
        messageID explicitMessageID: String?,
        reaction: String,
        partIndex: Int,
        emoji: String?
    ) async throws -> ChannelActionResult {
        let context = try resolveContext(sessionID: sessionID)
        let transport = explicitTransport ?? context.transport
        guard let performer = performers[transport] else {
            throw ChannelActionRegistryError.unavailable(transport)
        }
        guard performer.channelActionCapabilities.contains(.react) else {
            throw ChannelActionRegistryError.unsupportedCapability(.react, transport)
        }
        let targetExternalID = try resolveTarget(explicitTargetExternalID, context: context)
        let messageID = try resolveMessageID(explicitMessageID, context: context)
        return try await performer.react(
            targetExternalID: targetExternalID,
            messageID: messageID,
            reaction: reaction,
            partIndex: partIndex,
            emoji: emoji
        )
    }

    public func setPendingReplyEffect(
        sessionID: String,
        transport explicitTransport: ChannelBinding.Transport?,
        targetExternalID explicitTargetExternalID: String?,
        effectID: String
    ) throws -> ChannelActionResult {
        let context = try resolveContext(sessionID: sessionID)
        let transport = explicitTransport ?? context.transport
        let targetExternalID = try resolveTarget(explicitTargetExternalID, context: context)
        let normalizedEffectID = normalizeEffectID(effectID, transport: transport)
        pendingReplyEffects[effectKey(transport: transport, targetExternalID: targetExternalID)] = normalizedEffectID
        var metadata = ["effect_id": normalizedEffectID]
        if normalizedEffectID != effectID {
            metadata["requested_effect_id"] = effectID
        }
        return ChannelActionResult(
            sideEffect: .setReplyEffect,
            transport: transport,
            targetExternalID: targetExternalID,
            metadata: metadata
        )
    }

    public func consumePendingReplyEffect(
        transport: ChannelBinding.Transport,
        targetExternalID: String
    ) -> String? {
        pendingReplyEffects.removeValue(forKey: effectKey(transport: transport, targetExternalID: targetExternalID))
    }

    public func noResponse(
        sessionID: String,
        reason: String?
    ) throws -> ChannelActionResult {
        let context = try resolveContext(sessionID: sessionID)
        let result = ChannelActionResult(
            sideEffect: .wait,
            transport: context.transport,
            targetExternalID: context.targetExternalID,
            messageID: context.sourceMessageID,
            metadata: [
                "reason": reason ?? "",
                "inbound_event_kind": context.inboundEventKind,
            ]
        )
        pendingWaits[sessionID] = result
        return result
    }

    public func consumeWait(sessionID: String) -> ChannelActionResult? {
        pendingWaits.removeValue(forKey: sessionID)
    }

    public func sendMessage(
        sessionID: String,
        transport explicitTransport: ChannelBinding.Transport?,
        targetExternalID explicitTargetExternalID: String?,
        text: String,
        metadata: [String: String] = [:]
    ) throws -> ChannelActionResult {
        let context = try resolveContext(sessionID: sessionID)
        let transport = explicitTransport ?? context.transport
        let targetExternalID = try resolveTarget(explicitTargetExternalID, context: context)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ChannelActionRegistryError.emptyMessageText
        }
        let send = PendingChannelMessageSend(
            sequence: nextSequence(sessionID: sessionID),
            transport: transport,
            targetExternalID: targetExternalID,
            workspaceID: context.workspaceID,
            channelID: context.channelID,
            actorID: context.actorID,
            text: trimmedText,
            metadata: metadata
        )
        pendingMessageSends[sessionID, default: []].append(send)
        return ChannelActionResult(
            sideEffect: .sendMessage,
            transport: transport,
            targetExternalID: targetExternalID,
            messageID: context.sourceMessageID,
            metadata: metadata.merging([
                "text": trimmedText,
                "channel_action_sequence": String(send.sequence),
            ]) { _, new in new }
        )
    }

    public func consumePendingMessageSends(sessionID: String) -> [PendingChannelMessageSend] {
        pendingMessageSends.removeValue(forKey: sessionID) ?? []
    }

    public func sendArtifact(
        sessionID: String,
        transport explicitTransport: ChannelBinding.Transport?,
        targetExternalID explicitTargetExternalID: String?,
        artifactID: String,
        caption: String?,
        metadata: [String: String] = [:]
    ) throws -> ChannelActionResult {
        let context = try resolveContext(sessionID: sessionID)
        let transport = explicitTransport ?? context.transport
        let targetExternalID = try resolveTarget(explicitTargetExternalID, context: context)
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let send = PendingChannelArtifactSend(
            sequence: nextSequence(sessionID: sessionID),
            transport: transport,
            targetExternalID: targetExternalID,
            workspaceID: context.workspaceID,
            channelID: context.channelID,
            actorID: context.actorID,
            artifactID: artifactID,
            caption: trimmedCaption?.isEmpty == true ? nil : trimmedCaption,
            metadata: metadata
        )
        pendingArtifactSends[sessionID, default: []].append(send)
        return ChannelActionResult(
            sideEffect: .sendMessage,
            transport: transport,
            targetExternalID: targetExternalID,
            metadata: metadata.merging([
                "artifact_id": artifactID,
                "caption": send.caption ?? "",
                "channel_action_sequence": String(send.sequence),
            ]) { _, new in new }
        )
    }

    public func consumePendingArtifactSends(sessionID: String) -> [PendingChannelArtifactSend] {
        pendingArtifactSends.removeValue(forKey: sessionID) ?? []
    }

    private func resolveContext(sessionID: String) throws -> ChannelActionContext {
        guard let context = currentContexts[sessionID] else {
            throw ChannelActionRegistryError.missingCurrentContext(sessionID: sessionID)
        }
        return context
    }

    private func resolveTarget(_ explicitTargetExternalID: String?, context: ChannelActionContext) throws -> String {
        if let explicitTargetExternalID = explicitTargetExternalID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitTargetExternalID.isEmpty {
            return explicitTargetExternalID
        }
        let targetExternalID = context.targetExternalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetExternalID.isEmpty else {
            throw ChannelActionRegistryError.missingTargetExternalID
        }
        return targetExternalID
    }

    private func resolveMessageID(_ explicitMessageID: String?, context: ChannelActionContext) throws -> String {
        if let explicitMessageID = explicitMessageID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitMessageID.isEmpty {
            return explicitMessageID
        }
        guard let messageID = context.sourceMessageID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !messageID.isEmpty else {
            throw ChannelActionRegistryError.missingSourceMessageID
        }
        return messageID
    }

    private func nextSequence(sessionID: String) -> Int {
        let next = (pendingSequenceBySession[sessionID] ?? 0) + 1
        pendingSequenceBySession[sessionID] = next
        return next
    }

    private func effectKey(transport: ChannelBinding.Transport, targetExternalID: String) -> String {
        "\(transport.rawValue):\(targetExternalID)"
    }

    private func normalizeEffectID(_ effectID: String, transport: ChannelBinding.Transport) -> String {
        let trimmed = effectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard transport == .imessage else {
            return trimmed
        }

        switch trimmed.lowercased() {
        case "screen",
             "full_screen",
             "fullscreen",
             "screen_effect",
             "spotlight",
             "ckspotlight",
             "ckspotlighteffect",
             "com.apple.mobilesms.effect.ckspotlighteffect":
            return "com.apple.messages.effect.CKSpotlightEffect"
        case "impact",
             "slam",
             "bubble",
             "emphasis":
            return "com.apple.MobileSMS.effect.impact"
        default:
            return trimmed
        }
    }
}
