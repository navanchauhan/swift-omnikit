import Foundation
import OmniAgentMesh
import TheAgentControlPlaneKit

public actor IngressGateway {
    private let identityStore: any IdentityStore
    private let deliveryStore: any DeliveryStore
    private let missionStore: (any MissionStore)?
    private let runtimeRegistry: WorkspaceRuntimeRegistry
    private let policyManager: ChannelPolicyManager?
    private let onboardingWizard: OnboardingWizard?
    private let attachmentStager: AttachmentStager?
    private let mediaDescriptionProvider: (any MediaDescriptionProviding)?

    public init(
        identityStore: any IdentityStore,
        deliveryStore: any DeliveryStore,
        missionStore: (any MissionStore)? = nil,
        runtimeRegistry: WorkspaceRuntimeRegistry,
        policyManager: ChannelPolicyManager? = nil,
        onboardingWizard: OnboardingWizard? = nil,
        attachmentStager: AttachmentStager? = nil,
        mediaDescriptionProvider: (any MediaDescriptionProviding)? = nil
    ) {
        self.identityStore = identityStore
        self.deliveryStore = deliveryStore
        self.missionStore = missionStore
        self.runtimeRegistry = runtimeRegistry
        self.policyManager = policyManager
        self.onboardingWizard = onboardingWizard
        self.attachmentStager = attachmentStager
        self.mediaDescriptionProvider = mediaDescriptionProvider
    }

    public func handle(_ envelope: IngressEnvelope) async throws -> IngressGatewayResult {
        if try await deliveryStore.delivery(idempotencyKey: envelope.idempotencyKey) != nil {
            return IngressGatewayResult(disposition: .duplicate)
        }

        let route = try await resolveRoute(for: envelope)
        if let onboardingWizard,
           let context = onboardingContext(for: envelope),
           let outcome = try await onboardingWizard.evaluate(
               context: context,
               actorID: route.messageActorID,
               workspace: route.workspace,
               binding: route.binding
           ),
           outcome.disposition == .replyAndStop {
            let message = outcome.message ?? "This channel is not ready yet."
            let instruction = IngressDeliveryInstruction(
                idempotencyKey: "\(envelope.idempotencyKey).onboarding",
                kind: .message,
                transport: envelope.transport,
                visibility: .sameChannel,
                workspaceID: route.runtimeScope.workspaceID,
                channelID: route.runtimeScope.channelID,
                actorID: route.messageActorID,
                targetExternalID: envelope.channelExternalID,
                chunks: IngressDeliveryFormatter.chunkText(message),
                metadata: envelope.metadata.merging([
                    "interaction_kind": "onboarding",
                ]) { _, new in new }
            )
            try await saveInboundDelivery(
                envelope: envelope,
                route: route,
                status: .processed,
                summary: envelope.text ?? "Handled by onboarding gate."
            )
            try await saveOutboundDelivery(instruction, route: route)
            return IngressGatewayResult(
                disposition: .processed,
                runtimeScope: route.runtimeScope,
                actorID: route.messageActorID,
                assistantText: message,
                deliveries: [instruction]
            )
        }

        if envelope.payloadKind != .callback && shouldIgnore(envelope: envelope, route: route) {
            try await saveInboundDelivery(
                envelope: envelope,
                route: route,
                status: .ignored,
                summary: "Ignored shared-channel message without mention or reply context."
            )
            return IngressGatewayResult(
                disposition: .ignored,
                runtimeScope: route.runtimeScope,
                actorID: route.messageActorID
            )
        }

        switch envelope.payloadKind {
        case .callback:
            let acknowledgementText = "Received."
            let acknowledgement = IngressDeliveryInstruction(
                idempotencyKey: "\(envelope.idempotencyKey).ack",
                kind: .callbackAcknowledgement,
                transport: envelope.transport,
                visibility: .sameChannel,
                workspaceID: route.runtimeScope.workspaceID,
                channelID: route.runtimeScope.channelID,
                actorID: route.messageActorID,
                targetExternalID: envelope.channelExternalID,
                chunks: [acknowledgementText],
                metadata: envelope.metadata
            )

            let callbackAction = envelope.callbackData.flatMap(parseCallbackAction)
            let followUpInstruction: IngressDeliveryInstruction?
            switch callbackAction {
            case .approve(let requestID, let approved):
                let server = try await resolveCallbackServer(
                    approvalRequestID: requestID,
                    questionRequestID: nil,
                    fallbackScope: route.runtimeScope
                )
                _ = try await server.approveRequest(
                    requestID: requestID,
                    approved: approved,
                    actorID: route.messageActorID,
                    responseText: approved ? "Approved via callback" : "Rejected via callback"
                )
                followUpInstruction = IngressDeliveryInstruction(
                    idempotencyKey: "\(envelope.idempotencyKey).result",
                    kind: .message,
                    transport: envelope.transport,
                    visibility: .sameChannel,
                    workspaceID: route.runtimeScope.workspaceID,
                    channelID: route.runtimeScope.channelID,
                    actorID: route.messageActorID,
                    targetExternalID: envelope.channelExternalID,
                    chunks: [approved ? "Approval recorded." : "Rejection recorded."]
                )
            case .question(let requestID, let answer):
                let server = try await resolveCallbackServer(
                    approvalRequestID: nil,
                    questionRequestID: requestID,
                    fallbackScope: route.runtimeScope
                )
                _ = try await server.answerQuestion(
                    requestID: requestID,
                    answerText: answer,
                    actorID: route.messageActorID
                )
                followUpInstruction = IngressDeliveryInstruction(
                    idempotencyKey: "\(envelope.idempotencyKey).result",
                    kind: .message,
                    transport: envelope.transport,
                    visibility: .sameChannel,
                    workspaceID: route.runtimeScope.workspaceID,
                    channelID: route.runtimeScope.channelID,
                    actorID: route.messageActorID,
                    targetExternalID: envelope.channelExternalID,
                    chunks: ["Answer recorded."]
                )
            case .none:
                followUpInstruction = IngressDeliveryInstruction(
                    idempotencyKey: "\(envelope.idempotencyKey).result",
                    kind: .message,
                    transport: envelope.transport,
                    visibility: .sameChannel,
                    workspaceID: route.runtimeScope.workspaceID,
                    channelID: route.runtimeScope.channelID,
                    actorID: route.messageActorID,
                    targetExternalID: envelope.channelExternalID,
                    chunks: ["Unsupported callback action."]
                )
            }

            var deliveries = [acknowledgement]
            if let followUpInstruction {
                deliveries.append(followUpInstruction)
            }
            try await saveInboundDelivery(
                envelope: envelope,
                route: route,
                status: .processed,
                summary: "Acknowledged callback action."
            )
            for delivery in deliveries {
                try await saveOutboundDelivery(delivery, route: route)
            }
            return IngressGatewayResult(
                disposition: .processed,
                runtimeScope: route.runtimeScope,
                actorID: route.messageActorID,
                deliveries: deliveries
            )
        case .unsupported:
            return try await unsupportedResult(
                envelope: envelope,
                route: route,
                summary: "Unsupported inbound payload."
            )
        case .text:
            let trimmed = envelope.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty || !envelope.attachments.isEmpty else {
                return try await unsupportedResult(
                    envelope: envelope,
                    route: route,
                    summary: "Ignored empty inbound text."
                )
            }

            let stagedAttachments = try await attachmentStager?.stage(
                attachments: envelope.attachments,
                workspaceID: route.runtimeScope.workspaceID,
                channelID: route.runtimeScope.channelID
            ) ?? AttachmentStageResult()
            let runtime = try await runtimeRegistry.runtime(for: route.runtimeScope)
            await ChannelActionRegistry.shared.updateCurrentContext(
                ChannelActionContext(
                    sessionID: route.runtimeScope.sessionID,
                    transport: envelope.transport,
                    targetExternalID: envelope.channelExternalID,
                    sourceMessageID: envelope.messageID,
                    workspaceID: route.runtimeScope.workspaceID,
                    channelID: route.runtimeScope.channelID,
                    actorID: route.messageActorID,
                    actorExternalID: envelope.actorExternalID,
                    actorDisplayName: envelope.actorDisplayName,
                    channelKind: envelope.channelKind.rawValue,
                    inboundEventKind: envelope.eventKind.rawValue
                )
            )
            let enrichedAttachments = await describeMediaAttachments(stagedAttachments.attachments)
            let rootInputText = rootInputText(
                for: envelope,
                trimmedText: trimmed,
                stagedAttachments: enrichedAttachments
            )
            _ = try await runtime.submitUserText(
                rootInputText,
                actorID: route.messageActorID,
                metadata: route.messageMetadata(
                    merging: envelope.metadata.merging(attachmentMetadata(stagedAttachments.metadata, enrichedAttachments)) { _, new in new },
                    envelope: envelope
                ),
                recordAssistantText: false
            )
            var actionOutcome = try await collectChannelActionOutcome(
                sessionID: route.runtimeScope.sessionID,
                route: route,
                envelope: envelope
            )
            if actionOutcome.requiresProtocolRetry {
                print("[IngressGateway] protocol violation: no typed channel action for \(envelope.idempotencyKey); retrying once.")
                _ = try await runtime.submitUserText(
                    protocolCorrectionText(for: envelope),
                    actorID: route.messageActorID,
                    metadata: route.messageMetadata(
                        merging: envelope.metadata.merging([
                            "protocol_retry": "true",
                            "protocol_retry_reason": "missing_typed_channel_action",
                        ]) { _, new in new },
                        envelope: envelope
                    ),
                    recordAssistantText: false
                )
                actionOutcome = try await collectChannelActionOutcome(
                    sessionID: route.runtimeScope.sessionID,
                    route: route,
                    envelope: envelope
                )
            }
            if actionOutcome.isProtocolViolation {
                let summary = "Protocol violation: root agent produced no typed channel action."
                print("[IngressGateway] \(summary) idempotency_key=\(envelope.idempotencyKey)")
                try await saveInboundDelivery(
                    envelope: envelope,
                    route: route,
                    status: .failed,
                    summary: summary
                )
                return IngressGatewayResult(
                    disposition: .failed,
                    runtimeScope: route.runtimeScope,
                    actorID: route.messageActorID,
                    assistantText: nil,
                    deliveries: []
                )
            }

            let assistantText = actionOutcome.assistantText
            let instructions = actionOutcome.instructions
            if !assistantText.isEmpty {
                _ = try await runtime.server.recordAssistantText(
                    assistantText,
                    metadata: [
                        "source": "channel_send_message",
                        "ingress_transport": envelope.transport.rawValue,
                        "ingress_event_kind": envelope.eventKind.rawValue,
                    ]
                )
            }

            try await saveInboundDelivery(
                envelope: envelope,
                route: route,
                status: .processed,
                summary: trimmed
            )
            for instruction in instructions {
                try await saveOutboundDelivery(instruction, route: route)
            }

            return IngressGatewayResult(
                disposition: .processed,
                runtimeScope: route.runtimeScope,
                actorID: route.messageActorID,
                assistantText: assistantText.isEmpty ? nil : assistantText,
                deliveries: instructions
            )
        }
    }

    private func collectChannelActionOutcome(
        sessionID: String,
        route: ResolvedIngressRoute,
        envelope: IngressEnvelope
    ) async throws -> ChannelActionOutcome {
        let waitEffect = await ChannelActionRegistry.shared.consumeWait(sessionID: sessionID)
        let deferredInstructions = try await collectDeferredInteractionDeliveries(
            route: route,
            envelope: envelope
        )
        let pendingMessageSends = await ChannelActionRegistry.shared.consumePendingMessageSends(
            sessionID: sessionID
        )
        let pendingArtifactSends = await ChannelActionRegistry.shared.consumePendingArtifactSends(
            sessionID: sessionID
        )

        let pendingMessageInstructions = messageSendInstructions(
            for: pendingMessageSends,
            route: route,
            envelope: envelope
        )
        let pendingArtifactInstructions = artifactSendInstructions(
            for: pendingArtifactSends,
            route: route,
            envelope: envelope,
            fallbackCaptionChunks: []
        )
        let channelSendInstructions = (pendingMessageInstructions + pendingArtifactInstructions).sorted {
            channelActionSequence($0) < channelActionSequence($1)
        }
        let instructions = deferredInstructions + channelSendInstructions
        return ChannelActionOutcome(
            waitEffect: waitEffect,
            instructions: instructions,
            assistantText: explicitAssistantText(from: channelSendInstructions)
        )
    }

    private func protocolCorrectionText(for envelope: IngressEnvelope) -> String {
        """
        Protocol violation: your previous turn produced no typed channel side effect.
        You must now choose exactly one outcome for the current \(envelope.eventKind.rawValue) event:
        - call `channel_send_message` for any user-visible text reply
        - call `channel_send_artifact` or an image tool with `send=true` when sending media
        - call `no_response` only when silence is intentional
        Do not return raw final assistant text.
        """
    }

    private func rootInputText(
        for envelope: IngressEnvelope,
        trimmedText: String,
        stagedAttachments: [StagedAttachment]
    ) -> String {
        let body = trimmedText.isEmpty ? "(no text body)" : trimmedText
        let attachmentContext = attachmentContextText(stagedAttachments)
        if envelope.transport == .imessage, envelope.eventKind == .humanMessage {
            return """
            Inbound human_message over imessage.
            To reply, call `channel_send_message`; raw final assistant text is internal only and is not delivered to the user.
            Reply style for `channel_send_message`: one short message bubble under 160 characters by default; one sentence when possible; no bullets, no implementation recap, no tool/process narration unless explicitly requested.
            \(attachmentContext)

            \(body)
            """
        }
        guard envelope.eventKind != .humanMessage else {
            return [attachmentContext, body]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
        }
        return """
        Inbound \(envelope.eventKind.rawValue) event from \(envelope.transport.rawValue).
        Treat this as an event, not as direct human intent. Use `no_response` if no user-visible response is needed, or `channel_send_message` if the event should notify the user.
        Raw final assistant text is internal only and is not delivered to the user.
        \(attachmentContext)

        \(body)
        """
    }

    private func attachmentContextText(_ attachments: [StagedAttachment]) -> String {
        guard !attachments.isEmpty else {
            return ""
        }
        let lines = attachments.enumerated().map { index, attachment in
            let localPath = attachment.localPath.map { ", local_path=\($0)" } ?? ""
            let description = attachment.metadata["generated_media_description"].map { ", description=\($0)" } ?? ""
            return "- \(index + 1). artifact_id=\(attachment.artifactID), name=\(attachment.name), content_type=\(attachment.contentType), bytes=\(attachment.byteCount)\(localPath)\(description)"
        }
        return """

        Attached artifacts:
        \(lines.joined(separator: "\n"))
        Uploaded images are editable artifacts. For follow-up edits like "make this black and white", use the most recent relevant image `artifact_id` as the `image_edit.artifact_id` base and set `send=true` when the user asked for the image back in-channel. Do not call `view_image` unless it is actually available as a registered tool.
        """
    }

    private func describeMediaAttachments(_ attachments: [StagedAttachment]) async -> [StagedAttachment] {
        guard let mediaDescriptionProvider else {
            return attachments
        }
        var described: [StagedAttachment] = []
        described.reserveCapacity(attachments.count)
        for attachment in attachments {
            guard isImageAttachment(attachment) else {
                described.append(attachment)
                continue
            }
            var enriched = attachment
            do {
                if let description = try await mediaDescriptionProvider.describeImageAttachment(attachment),
                   !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    enriched.metadata["generated_media_description"] = description
                }
            } catch {
                enriched.metadata["generated_media_description_error"] = String(describing: error)
                print("[IngressGateway] image description failed for artifact \(attachment.artifactID): \(error)")
            }
            described.append(enriched)
        }
        return described
    }

    private func attachmentMetadata(
        _ baseMetadata: [String: String],
        _ attachments: [StagedAttachment]
    ) -> [String: String] {
        var metadata = baseMetadata
        for (index, attachment) in attachments.enumerated() {
            let prefix = "staged_attachment_\(index + 1)"
            metadata["\(prefix)_artifact_id"] = attachment.artifactID
            metadata["\(prefix)_content_type"] = attachment.contentType
            metadata["\(prefix)_name"] = attachment.name
            if let localPath = attachment.localPath {
                metadata["\(prefix)_local_path"] = localPath
            }
            if let description = attachment.metadata["generated_media_description"] {
                metadata["\(prefix)_description"] = description
            }
        }
        return metadata
    }

    private func isImageAttachment(_ attachment: StagedAttachment) -> Bool {
        attachment.contentType.lowercased().hasPrefix("image/")
    }

    private func messageSendInstructions(
        for sends: [PendingChannelMessageSend],
        route: ResolvedIngressRoute,
        envelope: IngressEnvelope
    ) -> [IngressDeliveryInstruction] {
        sends.map { send in
            IngressDeliveryInstruction(
                idempotencyKey: "\(envelope.idempotencyKey).channel_send_message.\(send.sequence)",
                kind: .message,
                transport: send.transport,
                visibility: .sameChannel,
                workspaceID: send.workspaceID,
                channelID: send.channelID,
                actorID: send.actorID ?? route.messageActorID,
                targetExternalID: send.targetExternalID,
                chunks: IngressDeliveryFormatter.chunkText(send.text),
                metadata: send.metadata.merging([
                    "side_effect": ChannelSideEffectKind.sendMessage.rawValue,
                    "inbound_event_kind": envelope.eventKind.rawValue,
                    "channel_action_sequence": String(send.sequence),
                ]) { _, new in new }
            )
        }
    }

    private func artifactSendInstructions(
        for sends: [PendingChannelArtifactSend],
        route: ResolvedIngressRoute,
        envelope: IngressEnvelope,
        fallbackCaptionChunks: [String]
    ) -> [IngressDeliveryInstruction] {
        sends.map { send in
            let captionChunks = send.caption.map { IngressDeliveryFormatter.chunkText($0) } ?? fallbackCaptionChunks
            return IngressDeliveryInstruction(
                idempotencyKey: "\(envelope.idempotencyKey).artifact_send.\(send.sequence)",
                kind: .message,
                transport: send.transport,
                visibility: .sameChannel,
                workspaceID: send.workspaceID,
                channelID: send.channelID,
                actorID: send.actorID ?? route.messageActorID,
                targetExternalID: send.targetExternalID,
                chunks: captionChunks,
                attachments: [
                    IngressDeliveryAttachment(
                        artifactID: send.artifactID,
                        metadata: send.metadata
                    ),
                ],
                metadata: send.metadata.merging([
                    "side_effect": ChannelSideEffectKind.sendMessage.rawValue,
                    "artifact_id": send.artifactID,
                    "inbound_event_kind": envelope.eventKind.rawValue,
                    "channel_action_sequence": String(send.sequence),
                ]) { _, new in new }
            )
        }
    }

    private func channelActionSequence(_ instruction: IngressDeliveryInstruction) -> Int {
        instruction.metadata["channel_action_sequence"].flatMap(Int.init) ?? Int.max
    }

    private func explicitAssistantText(from instructions: [IngressDeliveryInstruction]) -> String {
        instructions
            .flatMap(\.chunks)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func generatedImageInstructions(
        for artifacts: [ArtifactRecord],
        route: ResolvedIngressRoute,
        envelope: IngressEnvelope,
        captionChunks: [String]
    ) -> [IngressDeliveryInstruction] {
        artifacts.enumerated().map { index, artifact in
            IngressDeliveryInstruction(
                idempotencyKey: "\(envelope.idempotencyKey).generated_image.\(index)",
                kind: .message,
                transport: envelope.transport,
                visibility: .sameChannel,
                workspaceID: route.runtimeScope.workspaceID,
                channelID: route.runtimeScope.channelID,
                actorID: route.messageActorID,
                targetExternalID: envelope.channelExternalID,
                chunks: index == 0 ? captionChunks : [],
                attachments: [
                    IngressDeliveryAttachment(
                        artifactID: artifact.artifactID,
                        name: artifact.name,
                        contentType: artifact.contentType,
                        metadata: [
                            "generated_by": "image_generation",
                        ]
                    ),
                ],
                metadata: [
                    "side_effect": ChannelSideEffectKind.sendMessage.rawValue,
                    "generated_by": "image_generation",
                    "artifact_id": artifact.artifactID,
                    "inbound_event_kind": envelope.eventKind.rawValue,
                ]
            )
        }
    }

    private func unsupportedResult(
        envelope: IngressEnvelope,
        route: ResolvedIngressRoute,
        summary: String
    ) async throws -> IngressGatewayResult {
        let instruction = IngressDeliveryInstruction(
            idempotencyKey: "\(envelope.idempotencyKey).unsupported",
            kind: .message,
            transport: envelope.transport,
            visibility: .sameChannel,
            workspaceID: route.runtimeScope.workspaceID,
            channelID: route.runtimeScope.channelID,
            actorID: route.messageActorID,
            targetExternalID: envelope.channelExternalID,
            chunks: ["This input type is not supported yet."]
        )
        try await saveInboundDelivery(
            envelope: envelope,
            route: route,
            status: .processed,
            summary: summary
        )
        try await saveOutboundDelivery(instruction, route: route)
        return IngressGatewayResult(
            disposition: .unsupported,
            runtimeScope: route.runtimeScope,
            actorID: route.messageActorID,
            deliveries: [instruction]
        )
    }

    private func resolveRoute(for envelope: IngressEnvelope) async throws -> ResolvedIngressRoute {
        if let binding = try await identityStore.channelBinding(
            transport: envelope.transport,
            externalID: envelope.channelExternalID
        ) {
            let workspace = try await ensuredWorkspace(
                workspaceID: binding.workspaceID,
                envelope: envelope
            )
            let messageActorID = try await ensureHumanActor(for: envelope, workspaceID: binding.workspaceID)
            let runtimeScope = try await runtimeScope(
                envelope: envelope,
                workspaceID: binding.workspaceID,
                channelID: binding.channelID,
                messageActorID: messageActorID
            )
            return ResolvedIngressRoute(
                runtimeScope: runtimeScope,
                messageActorID: messageActorID,
                workspace: workspace,
                binding: binding
            )
        }

        let messageActorID = try await ensureHumanActor(for: envelope, workspaceID: provisionalWorkspaceID(for: envelope))
        let workspace = try await ensureWorkspaceAndMembership(
            envelope: envelope,
            messageActorID: messageActorID
        )
        let channelID = provisionalChannelID(for: envelope)
        let runtimeScope = try await runtimeScope(
            envelope: envelope,
            workspaceID: workspace.workspaceID,
            channelID: channelID,
            messageActorID: messageActorID
        )

        let binding = ChannelBinding(
            transport: envelope.transport,
            externalID: envelope.channelExternalID,
            workspaceID: workspace.workspaceID,
            channelID: channelID,
            actorID: runtimeScope.actorID,
            metadata: [
                "ambient_messages_enabled": "false",
                "channel_kind": envelope.channelKind.rawValue,
            ]
        )
        try await identityStore.saveChannelBinding(binding)

        return ResolvedIngressRoute(
            runtimeScope: runtimeScope,
            messageActorID: messageActorID,
            workspace: workspace,
            binding: binding
        )
    }

    private func shouldIgnore(envelope: IngressEnvelope, route: ResolvedIngressRoute) -> Bool {
        switch envelope.channelKind {
        case .directMessage, .api:
            return false
        case .group, .topic:
            let ambientEnabled = route.binding.metadata["ambient_messages_enabled"] == "true" ||
                route.workspace.metadata["ambient_channel_handling"] == "true"
            return !ambientEnabled && !envelope.mentionTriggerActive && !envelope.replyContextActive
        }
    }

    private func onboardingContext(for envelope: IngressEnvelope) -> ChannelIngressContext? {
        let channelKind: ChannelIngressContext.ChannelKind
        switch envelope.channelKind {
        case .directMessage:
            channelKind = .directMessage
        case .group:
            channelKind = .group
        case .topic:
            channelKind = .topic
        case .api:
            channelKind = .api
        }
        return ChannelIngressContext(
            transport: envelope.transport,
            actorExternalID: envelope.actorExternalID,
            channelKind: channelKind,
            text: envelope.text
        )
    }

    private func provisionalWorkspaceID(for envelope: IngressEnvelope) -> WorkspaceID {
        switch envelope.channelKind {
        case .directMessage:
            return WorkspaceID(rawValue: "\(envelope.transport.rawValue)-dm-\(sanitize(envelope.actorExternalID))")
        case .group, .topic, .api:
            return WorkspaceID(rawValue: "\(envelope.transport.rawValue)-workspace-\(sanitize(envelope.channelExternalID))")
        }
    }

    private func provisionalChannelID(for envelope: IngressEnvelope) -> ChannelID {
        ChannelID(rawValue: "\(envelope.transport.rawValue)-channel-\(sanitize(envelope.channelExternalID))")
    }

    private func ensureHumanActor(
        for envelope: IngressEnvelope,
        workspaceID: WorkspaceID
    ) async throws -> ActorID {
        let actorID = ActorID(rawValue: "\(envelope.transport.rawValue)-actor-\(sanitize(envelope.actorExternalID))")
        if try await identityStore.actor(actorID: actorID) == nil {
            try await identityStore.saveActor(
                ActorRecord(
                    actorID: actorID,
                    displayName: envelope.actorDisplayName ?? envelope.actorExternalID,
                    kind: .human,
                    metadata: [
                        "transport": envelope.transport.rawValue,
                        "external_actor_id": envelope.actorExternalID,
                    ]
                )
            )
        }
        _ = workspaceID
        return actorID
    }

    private func ensureWorkspaceAndMembership(
        envelope: IngressEnvelope,
        messageActorID: ActorID
    ) async throws -> WorkspaceRecord {
        let workspaceID = provisionalWorkspaceID(for: envelope)
        let existing = try await identityStore.workspace(workspaceID: workspaceID)
        if let existing {
            if try await identityStore.membership(workspaceID: workspaceID, actorID: messageActorID) == nil {
                let role: WorkspaceMembership.Role = (try await identityStore.memberships(workspaceID: workspaceID)).isEmpty ? .owner : .member
                try await identityStore.saveMembership(
                    WorkspaceMembership(workspaceID: workspaceID, actorID: messageActorID, role: role)
                )
            }
            return existing
        }

        let workspace = WorkspaceRecord(
            workspaceID: workspaceID,
            displayName: defaultWorkspaceDisplayName(for: envelope),
            kind: envelope.channelKind == .directMessage ? .personal : .shared,
            metadata: [
                "transport": envelope.transport.rawValue,
                "channel_kind": envelope.channelKind.rawValue,
                "ambient_channel_handling": "false",
            ]
        )
        try await identityStore.saveWorkspace(workspace)
        try await identityStore.saveMembership(
            WorkspaceMembership(workspaceID: workspaceID, actorID: messageActorID, role: .owner)
        )
        return workspace
    }

    private func ensuredWorkspace(
        workspaceID: WorkspaceID,
        envelope: IngressEnvelope
    ) async throws -> WorkspaceRecord {
        if let existing = try await identityStore.workspace(workspaceID: workspaceID) {
            return existing
        }
        let workspace = WorkspaceRecord(
            workspaceID: workspaceID,
            displayName: defaultWorkspaceDisplayName(for: envelope),
            kind: envelope.channelKind == .directMessage ? .personal : .shared,
            metadata: [
                "transport": envelope.transport.rawValue,
                "channel_kind": envelope.channelKind.rawValue,
                "ambient_channel_handling": "false",
            ]
        )
        try await identityStore.saveWorkspace(workspace)
        return workspace
    }

    private func runtimeScope(
        envelope: IngressEnvelope,
        workspaceID: WorkspaceID,
        channelID: ChannelID,
        messageActorID: ActorID
    ) async throws -> SessionScope {
        switch envelope.channelKind {
        case .directMessage:
            return SessionScope(actorID: messageActorID, workspaceID: workspaceID, channelID: channelID)
        case .group, .topic, .api:
            let runtimeActorID = ActorID(rawValue: "\(workspaceID.rawValue)-root")
            if try await identityStore.actor(actorID: runtimeActorID) == nil {
                try await identityStore.saveActor(
                    ActorRecord(
                        actorID: runtimeActorID,
                        displayName: "\(workspaceID.rawValue) Root",
                        kind: .system,
                        metadata: [
                            "transport": envelope.transport.rawValue,
                            "workspace_runtime": "true",
                        ]
                    )
                )
            }
            if try await identityStore.membership(workspaceID: workspaceID, actorID: runtimeActorID) == nil {
                try await identityStore.saveMembership(
                    WorkspaceMembership(workspaceID: workspaceID, actorID: runtimeActorID, role: .owner)
                )
            }
            return SessionScope(actorID: runtimeActorID, workspaceID: workspaceID, channelID: channelID)
        }
    }

    private func defaultWorkspaceDisplayName(for envelope: IngressEnvelope) -> String {
        switch envelope.channelKind {
        case .directMessage:
            return envelope.actorDisplayName.map { "\($0) Workspace" } ?? "\(envelope.actorExternalID) Workspace"
        case .group, .topic, .api:
            return envelope.channelExternalID
        }
    }

    private func sanitize(_ rawValue: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let sanitized = String(rawValue.map { allowed.contains($0) ? $0 : "_" })
        return sanitized.isEmpty ? "unknown" : sanitized
    }

    private func saveInboundDelivery(
        envelope: IngressEnvelope,
        route: ResolvedIngressRoute,
        status: DeliveryRecord.Status,
        summary: String
    ) async throws {
        _ = try await deliveryStore.saveDelivery(
            DeliveryRecord(
                idempotencyKey: envelope.idempotencyKey,
                direction: .inbound,
                transport: envelope.transport,
                sessionID: route.runtimeScope.sessionID,
                actorID: route.messageActorID,
                workspaceID: route.runtimeScope.workspaceID,
                channelID: route.runtimeScope.channelID,
                messageID: envelope.messageID,
                status: status,
                summary: summary,
                metadata: envelope.metadata.merging([
                    "channel_external_id": envelope.channelExternalID,
                    "channel_kind": envelope.channelKind.rawValue,
                    "inbound_event_kind": envelope.eventKind.rawValue,
                    "actor_external_id": envelope.actorExternalID,
                    "actor_display_name": envelope.actorDisplayName ?? "",
                ]) { current, new in
                    current.isEmpty ? new : current
                },
                createdAt: envelope.receivedAt,
                updatedAt: envelope.receivedAt
            )
        )
    }

    private func saveOutboundDelivery(
        _ instruction: IngressDeliveryInstruction,
        route: ResolvedIngressRoute
    ) async throws {
        let attachmentIDs = instruction.attachments.map(\.artifactID).joined(separator: ",")
        _ = try await deliveryStore.saveDelivery(
            DeliveryRecord(
                deliveryID: instruction.deliveryID,
                idempotencyKey: instruction.idempotencyKey,
                direction: .outbound,
                transport: instruction.transport,
                sessionID: route.runtimeScope.sessionID,
                actorID: instruction.actorID,
                workspaceID: instruction.workspaceID,
                channelID: instruction.channelID,
                messageID: instruction.targetExternalID,
                status: .deferred,
                summary: instruction.chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? attachmentIDs
                    : instruction.chunks.joined(separator: "\n"),
                metadata: instruction.metadata.merging([
                    "target_external_id": instruction.targetExternalID,
                    "visibility": instruction.visibility.rawValue,
                    "channel_transport": instruction.transport.rawValue,
                    "attachment_artifact_ids": attachmentIDs,
                ]) { current, new in
                    current.isEmpty ? new : current
                }
            )
        )
    }

    private func collectDeferredInteractionDeliveries(
        route: ResolvedIngressRoute,
        envelope: IngressEnvelope
    ) async throws -> [IngressDeliveryInstruction] {
        let sessionDeliveries = try await deliveryStore.deliveries(
            direction: .outbound,
            sessionID: route.runtimeScope.sessionID,
            status: .deferred
        )
        var candidates = sessionDeliveries

        if envelope.channelKind == .directMessage {
            let allDeferred = try await deliveryStore.deliveries(
                direction: .outbound,
                sessionID: nil,
                status: .deferred
            )
            let actorDeferred = allDeferred.filter { record in
                record.actorID == route.messageActorID &&
                    record.metadata["delivery_preference"] == ApprovalRequestRecord.DeliveryPreference.directMessage.rawValue
            }
            candidates.append(contentsOf: actorDeferred)
        }

        var seenDeliveryIDs: Set<String> = []
        var instructions: [IngressDeliveryInstruction] = []
        for record in candidates {
            guard seenDeliveryIDs.insert(record.deliveryID).inserted else {
                continue
            }
            guard let interactionKind = record.metadata["interaction_kind"] else {
                continue
            }
            if interactionKind == InteractionInboxItem.Kind.approval.rawValue {
                if let instruction = try await approvalInstruction(for: record, route: route, envelope: envelope) {
                    instructions.append(instruction)
                }
            } else if interactionKind == InteractionInboxItem.Kind.question.rawValue {
                if let instruction = try await questionInstruction(for: record, route: route, envelope: envelope) {
                    instructions.append(instruction)
                }
            }
        }

        return instructions
    }

    private func approvalInstruction(
        for record: DeliveryRecord,
        route: ResolvedIngressRoute,
        envelope: IngressEnvelope
    ) async throws -> IngressDeliveryInstruction? {
        if record.actorID != route.messageActorID {
            var normalizedRecord = record
            normalizedRecord.actorID = route.messageActorID
            _ = try await deliveryStore.saveDelivery(normalizedRecord)
        }
        guard let requestID = record.metadata["request_id"] else {
            return nil
        }
        if let missionStore, let approval = try await missionStore.approvalRequest(requestID: requestID) {
            guard approval.status == .pending || approval.status == .deferred else {
                return nil
            }

            if approval.deliveryPreference == .directMessage {
                if let dmTarget = try await resolvedDirectMessageTarget(for: route, envelope: envelope) {
                    return IngressDeliveryInstruction(
                        idempotencyKey: record.idempotencyKey,
                        kind: .message,
                        transport: envelope.transport,
                        visibility: .directMessage,
                        workspaceID: route.runtimeScope.workspaceID,
                        channelID: route.runtimeScope.channelID,
                        actorID: route.messageActorID,
                        targetExternalID: dmTarget,
                        chunks: IngressDeliveryFormatter.chunkText(
                            approval.title + "\n\n" + approval.prompt
                        ),
                        metadata: record.metadata.merging([
                            "interaction_kind": InteractionInboxItem.Kind.approval.rawValue,
                            "request_id": requestID,
                        ]) { _, new in new }
                    )
                }

                return IngressDeliveryInstruction(
                    idempotencyKey: "\(record.idempotencyKey).dm-bootstrap",
                    kind: .message,
                    transport: envelope.transport,
                    visibility: .sameChannel,
                    workspaceID: route.runtimeScope.workspaceID,
                    channelID: route.runtimeScope.channelID,
                    actorID: route.messageActorID,
                    targetExternalID: envelope.channelExternalID,
                    chunks: ["A sensitive approval is waiting. Start a private DM with the bot and send any message to continue."],
                    metadata: [
                        "bootstrap_for_request_id": requestID,
                        "interaction_kind": InteractionInboxItem.Kind.approval.rawValue,
                    ]
                )
            }

            return IngressDeliveryInstruction(
                idempotencyKey: record.idempotencyKey,
                kind: .message,
                transport: envelope.transport,
                visibility: .sameChannel,
                workspaceID: route.runtimeScope.workspaceID,
                channelID: route.runtimeScope.channelID,
                actorID: route.messageActorID,
                targetExternalID: envelope.channelExternalID,
                chunks: IngressDeliveryFormatter.chunkText(
                    approval.title + "\n\n" + approval.prompt
                ),
                metadata: record.metadata.merging([
                    "interaction_kind": InteractionInboxItem.Kind.approval.rawValue,
                    "request_id": requestID,
                ]) { _, new in new }
            )
        }
        return nil
    }

    private func questionInstruction(
        for record: DeliveryRecord,
        route: ResolvedIngressRoute,
        envelope: IngressEnvelope
    ) async throws -> IngressDeliveryInstruction? {
        if record.actorID != route.messageActorID {
            var normalizedRecord = record
            normalizedRecord.actorID = route.messageActorID
            _ = try await deliveryStore.saveDelivery(normalizedRecord)
        }
        guard let requestID = record.metadata["request_id"] else {
            return nil
        }
        if let missionStore, let question = try await missionStore.questionRequest(requestID: requestID) {
            guard question.status == .pending || question.status == .deferred else {
                return nil
            }

            var body = question.title + "\n\n" + question.prompt
            if !question.options.isEmpty {
                body += "\n\nOptions: " + question.options.joined(separator: ", ")
            }

            return IngressDeliveryInstruction(
                idempotencyKey: record.idempotencyKey,
                kind: .message,
                transport: envelope.transport,
                visibility: .sameChannel,
                workspaceID: route.runtimeScope.workspaceID,
                channelID: route.runtimeScope.channelID,
                actorID: route.messageActorID,
                targetExternalID: envelope.channelExternalID,
                chunks: IngressDeliveryFormatter.chunkText(body),
                metadata: record.metadata.merging([
                    "interaction_kind": InteractionInboxItem.Kind.question.rawValue,
                    "request_id": requestID,
                    "question_kind": question.kind.rawValue,
                    "question_options": question.options.joined(separator: "\u{1F}"),
                ]) { _, new in new }
            )
        }
        return nil
    }

    private func resolvedDirectMessageTarget(
        for route: ResolvedIngressRoute,
        envelope: IngressEnvelope
    ) async throws -> String? {
        if envelope.channelKind == .directMessage {
            return envelope.channelExternalID
        }
        let directMessageExternalID = "dm:\(envelope.actorExternalID)"
        if let binding = try await identityStore.channelBinding(
            transport: envelope.transport,
            externalID: directMessageExternalID
        ) {
            return binding.externalID
        }
        let bindings = try await identityStore.channelBindings(workspaceID: route.workspace.workspaceID)
        if let directBinding = bindings.first(where: { $0.actorID == route.messageActorID && $0.metadata["channel_kind"] == IngressEnvelope.ChannelKind.directMessage.rawValue }) {
            return directBinding.externalID
        }
        return nil
    }

    private func resolveCallbackServer(
        approvalRequestID: String?,
        questionRequestID: String?,
        fallbackScope: SessionScope
    ) async throws -> RootAgentServer {
        if let missionStore {
            if let approvalRequestID,
               let request = try await missionStore.approvalRequest(requestID: approvalRequestID) {
                let runtime = try await runtimeRegistry.runtime(sessionID: request.rootSessionID)
                return runtime.server
            }
            if let questionRequestID,
               let request = try await missionStore.questionRequest(requestID: questionRequestID) {
                let runtime = try await runtimeRegistry.runtime(sessionID: request.rootSessionID)
                return runtime.server
            }
        }
        let runtime = try await runtimeRegistry.runtime(for: fallbackScope)
        return runtime.server
    }
}

private enum IngressCallbackAction: Equatable {
    case approve(requestID: String, approved: Bool)
    case question(requestID: String, answer: String)
}

private func parseCallbackAction(_ rawValue: String) -> IngressCallbackAction? {
    let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 3 else {
        return nil
    }

    switch parts[0] {
    case "approval":
        switch parts[2] {
        case "approve":
            return .approve(requestID: parts[1], approved: true)
        case "reject":
            return .approve(requestID: parts[1], approved: false)
        default:
            return nil
        }
    case "question":
        let encoded = parts.dropFirst(2).joined(separator: ":")
        var normalized = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: normalized),
              let answer = String(data: data, encoding: .utf8) else {
            return nil
        }
        return .question(requestID: parts[1], answer: answer)
    default:
        return nil
    }
}

private struct ResolvedIngressRoute: Sendable {
    let runtimeScope: SessionScope
    let messageActorID: ActorID
    let workspace: WorkspaceRecord
    let binding: ChannelBinding

    func messageMetadata(
        merging metadata: [String: String],
        envelope: IngressEnvelope
    ) -> [String: String] {
        var merged = metadata
        merged["ingress_transport"] = envelope.transport.rawValue
        merged["ingress_actor_external_id"] = envelope.actorExternalID
        merged["ingress_channel_external_id"] = envelope.channelExternalID
        merged["ingress_channel_kind"] = envelope.channelKind.rawValue
        merged["ingress_event_kind"] = envelope.eventKind.rawValue
        merged["workspace_id"] = runtimeScope.workspaceID.rawValue
        merged["channel_id"] = runtimeScope.channelID.rawValue
        merged["message_actor_id"] = messageActorID.rawValue
        return merged
    }
}

private struct ChannelActionOutcome: Sendable {
    let waitEffect: ChannelActionResult?
    let instructions: [IngressDeliveryInstruction]
    let assistantText: String

    var hasTypedSideEffect: Bool {
        waitEffect != nil || !instructions.isEmpty
    }

    var requiresProtocolRetry: Bool {
        !hasTypedSideEffect
    }

    var isProtocolViolation: Bool {
        !hasTypedSideEffect
    }
}
