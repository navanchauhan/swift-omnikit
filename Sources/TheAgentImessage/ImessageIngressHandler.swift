import Foundation
import PhotonImessage
import OmniAgentMesh
import TheAgentControlPlaneKit
import TheAgentIngress

public enum ImessageIngressHandlerError: Error, CustomStringConvertible, Sendable {
    case missingCredentials

    public var description: String {
        switch self {
        case .missingCredentials:
            return "PHOTON_PROJECT_ID and PHOTON_PROJECT_SECRET are required."
        }
    }
}

private struct ImessageSentMessage: Sendable {
    var messageID: String
    var clientMessageID: String?
    var effectID: String?
    var attachmentID: String?
}

public actor ImessageIngressHandler {
    private var session: PhotonImessage.Session
    private let gateway: IngressGateway
    private let deliveryStore: any DeliveryStore
    private let artifactStore: (any ArtifactStore)?
    private let projectID: String
    private let projectSecret: String
    private var chatKindCache: [String: IngressEnvelope.ChannelKind] = [:]
    private var lastCursor: String?
    private var sentMessageIDs: Set<String> = []
    private var sentClientMessageIDs: Set<String> = []

    public init(
        session: PhotonImessage.Session,
        gateway: IngressGateway,
        deliveryStore: any DeliveryStore,
        artifactStore: (any ArtifactStore)? = nil,
        projectID: String,
        projectSecret: String
    ) {
        self.session = session
        self.gateway = gateway
        self.deliveryStore = deliveryStore
        self.artifactStore = artifactStore
        self.projectID = projectID
        self.projectSecret = projectSecret
    }

    public static func make(
        gateway: IngressGateway,
        deliveryStore: any DeliveryStore,
        artifactStore: (any ArtifactStore)? = nil,
        projectID: String?,
        projectSecret: String?
    ) async throws -> ImessageIngressHandler {
        guard
            let projectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines),
            let projectSecret = projectSecret?.trimmingCharacters(in: .whitespacesAndNewlines),
            !projectID.isEmpty,
            !projectSecret.isEmpty
        else {
            throw ImessageIngressHandlerError.missingCredentials
        }

        let session = try await PhotonImessage.Session.connect(
            credentials: .init(projectId: projectID, projectSecret: projectSecret)
        )
        let handler = ImessageIngressHandler(
            session: session,
            gateway: gateway,
            deliveryStore: deliveryStore,
            artifactStore: artifactStore,
            projectID: projectID,
            projectSecret: projectSecret
        )
        await ChannelActionRegistry.shared.register(handler, for: .imessage)
        return handler
    }

    public func run() async throws {
        while !Task.isCancelled {
            let currentSession = session
            let stream = currentSession.subscribeMessageEvents(cursor: lastCursor)
            do {
                for try await response in stream {
                    updateCursor(from: response)
                    if let envelope = try await makeEnvelope(from: response) {
                        let result = try await handleWithTypingIndicator(envelope)
                        try await deliver(result.deliveries)
                    }
                }
                try await Task.sleep(for: .seconds(1))
            } catch {
                if error is CancellationError {
                    throw error
                }

                print("[iMessage] inbound message event failed: \(error)")
                if isPhotonAuthenticationError(error) {
                    do {
                        try await reconnectSession()
                    } catch {
                        print("[iMessage] reconnect failed: \(error)")
                    }
                }
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func close() async {
        await ChannelActionRegistry.shared.unregister(transport: .imessage)
        await session.close()
    }

    private func handleWithTypingIndicator(_ envelope: IngressEnvelope) async throws -> IngressGatewayResult {
        let chatGuid = envelope.channelExternalID.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentSession = session
        let typingTask: Task<Void, Never>? = chatGuid.isEmpty ? nil : Task { [currentSession] in
            while !Task.isCancelled {
                do {
                    try await currentSession.startTyping(chatGuid: chatGuid)
                } catch {
                    print("[iMessage] start typing failed: \(error)")
                    return
                }

                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
        }

        defer {
            typingTask?.cancel()
            if !chatGuid.isEmpty {
                Task { [currentSession] in
                    do {
                        try await currentSession.stopTyping(chatGuid: chatGuid)
                    } catch {
                        print("[iMessage] stop typing failed: \(error)")
                    }
                }
            }
        }

        return try await gateway.handle(envelope)
    }

    private func makeEnvelope(
        from response: PIMsg_SubscribeMessageEventsResponse
    ) async throws -> IngressEnvelope? {
        guard let payload = response.payload else {
            return nil
        }

        switch payload {
        case .messageReceived(let event):
            return try await makeEnvelope(
                message: event.message,
                eventChatGuid: event.chatGuid,
                updateType: nil,
                response: response
            )
        case .messageUpdated(let event):
            return try await makeEnvelope(
                message: event.message,
                eventChatGuid: event.chatGuid,
                updateType: event.updateType,
                response: response
            )
        case .messageSent(let event):
            return try await makeEnvelope(
                message: event.message,
                eventChatGuid: event.chatGuid,
                updateType: "message_sent",
                response: response,
                allowOwnMediaEvents: true,
                responseClientMessageID: event.clientMessageID
            )
        case .heartbeat:
            return nil
        }
    }

    private func makeEnvelope(
        message originalMessage: PIMsg_Message,
        eventChatGuid: String,
        updateType: String?,
        response: PIMsg_SubscribeMessageEventsResponse,
        allowOwnMediaEvents: Bool = false,
        responseClientMessageID: String? = nil
    ) async throws -> IngressEnvelope? {
        var message = originalMessage
        if message.attachments.isEmpty,
           containsAttachmentPlaceholder(message.text),
           !message.guid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let hydrated = try? await session.getMessage(guid: message.guid),
               !hydrated.attachments.isEmpty {
                message = hydrated
            } else {
                print("[iMessage] waiting for media payload for placeholder message \(message.guid)")
                return nil
            }
        }

        let isReaction = isReactionMessage(message)
        if message.isFromMe && !isReaction {
            guard allowOwnMediaEvents, !message.attachments.isEmpty else {
                return nil
            }
            if await isKnownOutboundMessage(message, responseClientMessageID: responseClientMessageID) {
                return nil
            }
        }

        let chatGuid = normalizedChatGuid(from: eventChatGuid, message: message)
        guard !chatGuid.isEmpty else {
            return nil
        }

        let actorExternalID = message.isFromMe && allowOwnMediaEvents
            ? normalizedActorExternalIDForOwnMediaEvent(chatGuid: chatGuid, message: message)
            : normalizedActorExternalID(from: message.sender)
        guard !actorExternalID.isEmpty else {
            return nil
        }

        let meaningfulText = meaningfulText(from: message.text)
        let hasText = !meaningfulText.isEmpty
        let attachments = try await mappedAttachments(from: message.attachments)
        let payloadKind: IngressEnvelope.PayloadKind = (hasText || isReaction || !attachments.isEmpty) ? .text : .unsupported
        let channelKind = await resolveChannelKind(for: chatGuid)
        let baseUpdateID = message.guid.isEmpty ? responseCursorFallback(response: response) : message.guid
        let updateID = mediaAwareUpdateID(base: baseUpdateID, message: message)
        let responseCursor = response.cursor.value.trimmingCharacters(in: .whitespacesAndNewlines)

        var metadata: [String: String] = [
            "photon_chat_guid": chatGuid,
            "photon_message_is_from_me": String(message.isFromMe),
        ]

        if !message.guid.isEmpty {
            metadata["photon_message_guid"] = message.guid
        }
        if let updateType = updateType?.trimmingCharacters(in: .whitespacesAndNewlines), !updateType.isEmpty {
            metadata["photon_update_type"] = updateType
        }
        if let responseClientMessageID = responseClientMessageID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !responseClientMessageID.isEmpty {
            metadata["photon_response_client_message_id"] = responseClientMessageID
        }
        if !message.clientMessageID.isEmpty {
            metadata["photon_client_message_id"] = message.clientMessageID
        }
        if !responseCursor.isEmpty {
            metadata["photon_response_cursor"] = responseCursor
        }
        if !eventChatGuid.isEmpty {
            metadata["photon_event_chat_guid"] = eventChatGuid
        }
        addReactionMetadata(from: message, to: &metadata)
        if !message.sender.address.isEmpty {
            metadata["photon_sender_address"] = message.sender.address
        }
        if !message.sender.country.isEmpty {
            metadata["photon_sender_country"] = message.sender.country
        }
        if !message.sender.service.isEmpty {
            metadata["photon_sender_service"] = message.sender.service
        }
        if !message.sender.uncanonicalizedID.isEmpty {
            metadata["photon_sender_uncanonicalized_id"] = message.sender.uncanonicalizedID
        }

        return IngressEnvelope(
            transport: .imessage,
            payloadKind: payloadKind,
            updateID: updateID,
            messageID: message.guid.isEmpty ? nil : message.guid,
            actorExternalID: actorExternalID,
            actorDisplayName: message.sender.address,
            channelExternalID: chatGuid,
            channelKind: channelKind,
            eventKind: isReaction ? .reaction : (hasText ? .humanMessage : .memory),
            text: isReaction ? reactionEventText(from: message) : (hasText ? meaningfulText : nil),
            attachments: attachments,
            mentionTriggerActive: false,
            replyContextActive: false,
            metadata: metadata
        )
    }

    private func isReactionMessage(_ message: PIMsg_Message) -> Bool {
        let associatedGuid = message.hasAssociatedMessageGuid
            ? message.associatedMessageGuid.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let associatedEmoji = message.hasAssociatedMessageEmoji
            ? message.associatedMessageEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let associatedType = message.hasAssociatedMessageType
            ? message.associatedMessageType.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        return !associatedGuid.isEmpty ||
            !associatedEmoji.isEmpty ||
            isMeaningfulReactionType(associatedType)
    }

    private func isMeaningfulReactionType(_ associatedMessageType: String) -> Bool {
        let normalized = associatedMessageType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "0" else {
            return false
        }
        return true
    }

    private func addReactionMetadata(from message: PIMsg_Message, to metadata: inout [String: String]) {
        guard isReactionMessage(message) else {
            return
        }
        metadata["channel_event_kind"] = "reaction"
        if message.hasAssociatedMessageGuid {
            metadata["photon_associated_message_guid"] = message.associatedMessageGuid
        }
        if message.hasAssociatedMessageType {
            metadata["photon_associated_message_type"] = message.associatedMessageType
            metadata["reaction_name"] = normalizedReactionName(from: message.associatedMessageType)
        }
        if message.hasAssociatedMessageEmoji {
            metadata["photon_associated_message_emoji"] = message.associatedMessageEmoji
            metadata["reaction_emoji"] = message.associatedMessageEmoji
        }
    }

    private func reactionEventText(from message: PIMsg_Message) -> String {
        let reactionType = message.hasAssociatedMessageType ? message.associatedMessageType : "unknown"
        let reactionName = normalizedReactionName(from: reactionType)
        let emoji = message.hasAssociatedMessageEmoji ? message.associatedMessageEmoji : emojiForReactionName(reactionName)
        let target = message.hasAssociatedMessageGuid ? message.associatedMessageGuid : "unknown"
        return "Incoming iMessage reaction: \(emoji) (\(reactionName)); associated_message_guid=\(target); associated_message_type=\(reactionType)"
    }

    private func normalizedReactionName(from associatedMessageType: String) -> String {
        let trimmed = associatedMessageType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let withoutPrefix = trimmed.hasPrefix("-") ? String(trimmed.dropFirst()) : trimmed
        if withoutPrefix.contains("love") {
            return "love"
        }
        if withoutPrefix.contains("like") {
            return "like"
        }
        if withoutPrefix.contains("dislike") {
            return "dislike"
        }
        if withoutPrefix.contains("laugh") {
            return "laugh"
        }
        if withoutPrefix.contains("emphas") || withoutPrefix.contains("exclamation") {
            return "emphasize"
        }
        if withoutPrefix.contains("question") {
            return "question"
        }
        return withoutPrefix.isEmpty ? "unknown" : withoutPrefix
    }

    private func emojiForReactionName(_ reactionName: String) -> String {
        switch reactionName {
        case "love":
            return "\u{2764}\u{FE0F}"
        case "like":
            return "\u{1F44D}"
        case "dislike":
            return "\u{1F44E}"
        case "laugh":
            return "\u{1F602}"
        case "emphasize":
            return "\u{203C}\u{FE0F}"
        case "question":
            return "?"
        default:
            return reactionName
        }
    }

    public func deliver(_ instructions: [IngressDeliveryInstruction]) async throws {
        for instruction in instructions {
            do {
                try await deliverOnce(instruction)
            } catch {
                if isPhotonAuthenticationError(error) {
                    do {
                        try await reconnectSession()
                        try await deliverOnce(instruction)
                        continue
                    } catch {
                        try await markDelivery(
                            idempotencyKey: instruction.idempotencyKey,
                            instruction: instruction,
                            status: .failed,
                            sentMessages: [],
                            errorDescription: String(describing: error)
                        )
                        throw error
                    }
                }
                try await markDelivery(
                    idempotencyKey: instruction.idempotencyKey,
                    instruction: instruction,
                    status: .failed,
                    sentMessages: [],
                    errorDescription: String(describing: error)
                )
                throw error
            }
        }
    }

    private func deliverOnce(_ instruction: IngressDeliveryInstruction) async throws {
        switch instruction.kind {
        case .callbackAcknowledgement:
            let acknowledgementText = instruction.chunks.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let acknowledgementText, !acknowledgementText.isEmpty {
                let sentMessages = try await send(
                    instruction: instruction,
                    chunks: [acknowledgementText]
                )
                try await markDelivery(
                    idempotencyKey: instruction.idempotencyKey,
                    instruction: instruction,
                    status: .delivered,
                    sentMessages: sentMessages
                )
            } else {
                try await markDelivery(
                    idempotencyKey: instruction.idempotencyKey,
                    instruction: instruction,
                    status: .delivered,
                    sentMessages: []
                )
            }
        case .message:
            let sentMessages = try await send(
                instruction: instruction,
                chunks: instruction.chunks
            )
            try await markDelivery(
                idempotencyKey: instruction.idempotencyKey,
                instruction: instruction,
                status: .delivered,
                sentMessages: sentMessages
            )
        }
    }

    private func reconnectSession() async throws {
        print("[iMessage] reconnecting Photon session after authentication failure.")
        let oldSession = session
        let newSession = try await PhotonImessage.Session.connect(
            credentials: .init(projectId: projectID, projectSecret: projectSecret)
        )
        session = newSession
        await oldSession.close()
        chatKindCache.removeAll()
    }

    private func isPhotonAuthenticationError(_ error: any Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("unauthenticated") ||
            description.contains("invalid token") ||
            description.contains("(16)")
    }

    private func send(
        instruction: IngressDeliveryInstruction,
        chunks: [String]
    ) async throws -> [ImessageSentMessage] {
        guard !instruction.targetExternalID.isEmpty else {
            throw ImessageOutboundError.invalidTargetExternalID
        }
        guard !chunks.isEmpty || !instruction.attachments.isEmpty else {
            return []
        }

        var sentMessages: [ImessageSentMessage] = []
        var pendingEffectID = await ChannelActionRegistry.shared.consumePendingReplyEffect(
            transport: .imessage,
            targetExternalID: instruction.targetExternalID
        )

        if !instruction.attachments.isEmpty {
            let caption = chunks
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            for (index, attachment) in instruction.attachments.enumerated() {
                let appliedEffectID = pendingEffectID
                let clientMessageID = makeClientMessageID()
                let receipt = try await sendAttachment(
                    attachment,
                    chatGuid: instruction.targetExternalID,
                    caption: index == 0 && !caption.isEmpty ? caption : nil,
                    effectID: appliedEffectID,
                    clientMessageID: clientMessageID
                )
                pendingEffectID = nil
                rememberSentMessage(receipt, fallbackClientMessageID: clientMessageID)
                sentMessages.append(ImessageSentMessage(
                    messageID: receipt.guid,
                    clientMessageID: receipt.clientMessageID.isEmpty ? clientMessageID : receipt.clientMessageID,
                    effectID: appliedEffectID,
                    attachmentID: attachment.artifactID
                ))
            }
            return sentMessages
        }

        for chunk in chunks {
            let text = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }
            let appliedEffectID = pendingEffectID
            let clientMessageID = makeClientMessageID()
            let receipt = try await session.send(
                chatGuid: instruction.targetExternalID,
                message: text,
                clientMessageId: clientMessageID,
                effectId: appliedEffectID
            )
            pendingEffectID = nil
            rememberSentMessage(receipt, fallbackClientMessageID: clientMessageID)
            sentMessages.append(ImessageSentMessage(
                messageID: receipt.guid,
                clientMessageID: receipt.clientMessageID.isEmpty ? clientMessageID : receipt.clientMessageID,
                effectID: appliedEffectID
            ))
        }
        return sentMessages
    }

    private func sendAttachment(
        _ attachment: IngressDeliveryAttachment,
        chatGuid: String,
        caption: String?,
        effectID: String?,
        clientMessageID: String
    ) async throws -> PIMsg_MessageSendReceipt {
        guard let artifactStore else {
            throw ImessageOutboundError.artifactStoreUnavailable
        }
        guard let record = try await artifactStore.record(artifactID: attachment.artifactID) else {
            throw ImessageOutboundError.artifactNotFound(attachment.artifactID)
        }
        guard let data = try await artifactStore.data(for: attachment.artifactID), !data.isEmpty else {
            throw ImessageOutboundError.artifactDataMissing(attachment.artifactID)
        }

        let fileName = safeFileName(attachment.name ?? record.name)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "the-agent-imessage-attachments", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let fileURL = temporaryDirectory.appending(path: "\(UUID().uuidString)-\(fileName)")
        try data.write(to: fileURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let upload = try await session.uploadAttachment(filePath: fileURL.path())
        let uploadedGuid = upload.attachment.guid.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await session.send(
            chatGuid: chatGuid,
            message: caption,
            clientMessageId: clientMessageID,
            effectId: effectID,
            attachmentPath: uploadedGuid.isEmpty ? fileURL.path() : nil,
            attachmentName: fileName,
            attachmentGuid: uploadedGuid.isEmpty ? nil : uploadedGuid
        )
    }

    private func markDelivery(
        idempotencyKey: String,
        instruction: IngressDeliveryInstruction,
        status: DeliveryRecord.Status,
        sentMessages: [ImessageSentMessage],
        errorDescription: String? = nil
    ) async throws {
        let messageID = sentMessages.map(\.messageID).joined(separator: ",")
        let clientMessageID = sentMessages.compactMap(\.clientMessageID).joined(separator: ",")
        let appliedEffectIDs = sentMessages.compactMap(\.effectID)
        let attachmentIDs = sentMessages.compactMap(\.attachmentID).joined(separator: ",")
        var record = try await deliveryStore.delivery(idempotencyKey: idempotencyKey) ?? DeliveryRecord(
            idempotencyKey: idempotencyKey,
            direction: .outbound,
            transport: .imessage,
            status: status,
            summary: deliverySummary(instruction),
            metadata: instruction.metadata
        )
        record.transport = .imessage
        record.actorID = instruction.actorID
        record.workspaceID = instruction.workspaceID
        record.channelID = instruction.channelID
        record.messageID = messageID.isEmpty ? nil : messageID
        record.status = status
        record.summary = deliverySummary(instruction)
        var metadata = instruction.metadata
        metadata["target_external_id"] = instruction.targetExternalID
        metadata["delivered_message_id"] = messageID
        metadata["delivered_client_message_id"] = clientMessageID
        metadata["attachment_artifact_ids"] = instruction.attachments.map(\.artifactID).joined(separator: ",")
        metadata["delivered_attachment_artifact_ids"] = attachmentIDs
        if !appliedEffectIDs.isEmpty {
            metadata["applied_effect_id"] = appliedEffectIDs.joined(separator: ",")
        }
        if let errorDescription {
            metadata["error"] = errorDescription
        }
        record.metadata = metadata
        record.updatedAt = Date()
        _ = try await deliveryStore.saveDelivery(record)
    }

    private func updateCursor(from response: PIMsg_SubscribeMessageEventsResponse) {
        let cursor = response.cursor.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cursor.isEmpty else {
            return
        }
        lastCursor = cursor
    }

    private func mappedAttachments(from attachments: [PIMsg_AttachmentInfo]) async throws -> [IngressEnvelope.Attachment] {
        var mapped: [IngressEnvelope.Attachment] = []
        for attachment in attachments {
            let contentType = normalizedContentType(for: attachment)
            var metadata = [
                "photon_attachment_guid": attachment.guid,
                "photon_attachment_uti": attachment.uti,
                "photon_attachment_transferred_bytes": String(attachment.totalBytes),
            ]
            if attachment.hasWidth {
                metadata["image_width"] = String(attachment.width)
            }
            if attachment.hasHeight {
                metadata["image_height"] = String(attachment.height)
            }
            if isImageAttachment(attachment, contentType: contentType),
               attachment.totalBytes <= 50 * 1_024 * 1_024 {
                do {
                    let data = try await session.downloadAttachment(guid: attachment.guid)
                    metadata["inline_base64"] = data.base64EncodedString()
                    metadata["photon_attachment_downloaded"] = "true"
                } catch {
                    metadata["photon_attachment_download_error"] = String(describing: error)
                }
            }
            mapped.append(
                IngressEnvelope.Attachment(
                    name: attachment.fileName.isEmpty ? attachment.guid : attachment.fileName,
                    contentType: contentType,
                    metadata: metadata
                )
            )
        }
        return mapped
    }

    private func containsAttachmentPlaceholder(_ text: String) -> Bool {
        text.contains("\u{FFFC}")
    }

    private func meaningfulText(from text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mediaAwareUpdateID(base: String, message: PIMsg_Message) -> String {
        guard !message.attachments.isEmpty else {
            return base
        }
        let signature = message.attachments
            .map { attachment in
                [
                    attachment.guid,
                    attachment.originalGuid,
                    attachment.fileName,
                    String(attachment.totalBytes),
                ]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ":")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
        guard !signature.isEmpty else {
            return "\(base).media"
        }
        return "\(base).media.\(stableHash(signature))"
    }

    private func stableHash(_ rawValue: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in rawValue.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func normalizedContentType(for attachment: PIMsg_AttachmentInfo) -> String {
        let mimeType = attachment.mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mimeType.isEmpty {
            return mimeType
        }
        switch attachment.uti.lowercased() {
        case "public.png":
            return "image/png"
        case "public.jpeg", "public.jpg":
            return "image/jpeg"
        case "com.compuserve.gif":
            return "image/gif"
        case "org.webmproject.webp", "public.webp":
            return "image/webp"
        case "public.heic":
            return "image/heic"
        case "public.heif":
            return "image/heif"
        default:
            return "application/octet-stream"
        }
    }

    private func isImageAttachment(_ attachment: PIMsg_AttachmentInfo, contentType: String) -> Bool {
        if contentType.lowercased().hasPrefix("image/") {
            return true
        }
        let lowercasedName = attachment.fileName.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff"].contains { ext in
            lowercasedName.hasSuffix(".\(ext)")
        }
    }

    private func deliverySummary(_ instruction: IngressDeliveryInstruction) -> String {
        let text = instruction.chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        let attachmentIDs = instruction.attachments.map(\.artifactID).joined(separator: ",")
        return attachmentIDs.isEmpty ? "" : "attachments: \(attachmentIDs)"
    }

    private func safeFileName(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "attachment" : trimmed
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let sanitized = String(fallback.map { allowed.contains($0) ? $0 : "_" })
        return sanitized.isEmpty ? "attachment" : sanitized
    }

    private func makeClientMessageID() -> String {
        "omnikit-\(UUID().uuidString)"
    }

    private func rememberSentMessage(_ receipt: PIMsg_MessageSendReceipt, fallbackClientMessageID: String) {
        let messageID = receipt.guid.trimmingCharacters(in: .whitespacesAndNewlines)
        if !messageID.isEmpty {
            sentMessageIDs.insert(messageID)
        }
        let clientMessageID = (receipt.clientMessageID.isEmpty ? fallbackClientMessageID : receipt.clientMessageID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !clientMessageID.isEmpty {
            sentClientMessageIDs.insert(clientMessageID)
        }
    }

    private func isKnownOutboundMessage(
        _ message: PIMsg_Message,
        responseClientMessageID: String?
    ) async -> Bool {
        let messageID = message.guid.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageClientID = message.clientMessageID.trimmingCharacters(in: .whitespacesAndNewlines)
        let responseClientID = responseClientMessageID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !messageID.isEmpty, sentMessageIDs.contains(messageID) {
            return true
        }
        if !messageClientID.isEmpty, sentClientMessageIDs.contains(messageClientID) {
            return true
        }
        if !responseClientID.isEmpty, sentClientMessageIDs.contains(responseClientID) {
            return true
        }

        guard let deliveries = try? await deliveryStore.deliveries(
            direction: .outbound,
            sessionID: nil,
            status: nil
        ) else {
            return false
        }
        return deliveries.contains { record in
            guard record.transport == .imessage else {
                return false
            }
            return containsIdentifier(messageID, in: record.messageID) ||
                containsIdentifier(messageID, in: record.metadata["delivered_message_id"]) ||
                containsIdentifier(messageClientID, in: record.metadata["delivered_client_message_id"]) ||
                containsIdentifier(responseClientID, in: record.metadata["delivered_client_message_id"])
        }
    }

    private func containsIdentifier(_ identifier: String, in rawValue: String?) -> Bool {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let rawValue else {
            return false
        }
        return rawValue
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(trimmed)
    }

    private func normalizedActorExternalID(from sender: PIMsg_AddressInfo) -> String {
        return [
            sender.address,
            sender.uncanonicalizedID,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? ""
    }

    private func normalizedActorExternalIDForOwnMediaEvent(
        chatGuid: String,
        message: PIMsg_Message
    ) -> String {
        let directChatPeer = chatGuid
            .split(separator: ";", omittingEmptySubsequences: false)
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if !directChatPeer.isEmpty {
            return directChatPeer
        }
        return normalizedActorExternalID(from: message.sender)
    }

    private func normalizedChatGuid(from eventChatGuid: String, message: PIMsg_Message) -> String {
        let eventValue = eventChatGuid.trimmingCharacters(in: .whitespacesAndNewlines)
        if !eventValue.isEmpty {
            return eventValue
        }
        if let first = message.chatGuids.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !first.isEmpty {
            return first
        }
        return ""
    }

    private func responseCursorFallback(response: PIMsg_SubscribeMessageEventsResponse) -> String {
        let cursorValue = response.cursor.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cursorValue.isEmpty {
            return cursorValue
        }
        return UUID().uuidString
    }

    private func resolveChannelKind(for chatGuid: String) async -> IngressEnvelope.ChannelKind {
        if let cached = chatKindCache[chatGuid] {
            return cached
        }

        do {
            let chat = try await session.getChat(guid: chatGuid)
            let kind: IngressEnvelope.ChannelKind = chat.isGroup ? .group : .directMessage
            chatKindCache[chatGuid] = kind
            return kind
        } catch {
            chatKindCache[chatGuid] = .api
            return .api
        }
    }
}

extension ImessageIngressHandler: ChannelActionPerforming {
    public nonisolated var channelActionCapabilities: Set<ChannelActionCapability> {
        [.react, .setReplyEffect, .typing, .send]
    }

    public func react(
        targetExternalID: String,
        messageID: String,
        reaction: String,
        partIndex: Int,
        emoji: String?
    ) async throws -> ChannelActionResult {
        let receipt = try await session.sendReaction(
            chatGuid: targetExternalID,
            messageGuid: messageID,
            reaction: reaction,
            partIndex: Int32(partIndex),
            emoji: emoji
        )
        return ChannelActionResult(
            sideEffect: .reactToMessage,
            transport: .imessage,
            targetExternalID: targetExternalID,
            messageID: receipt.guid.isEmpty ? messageID : receipt.guid,
            metadata: [
                "target_message_id": messageID,
                "reaction": reaction,
                "part_index": String(partIndex),
                "emoji": emoji ?? "",
            ]
        )
    }
}

public enum ImessageOutboundError: Error, CustomStringConvertible, Sendable {
    case invalidTargetExternalID
    case artifactStoreUnavailable
    case artifactNotFound(String)
    case artifactDataMissing(String)

    public var description: String {
        switch self {
        case .invalidTargetExternalID:
            return "The outbound target chat GUID is empty."
        case .artifactStoreUnavailable:
            return "The iMessage delivery handler is not configured with artifact storage."
        case .artifactNotFound(let artifactID):
            return "Artifact \(artifactID) was not found."
        case .artifactDataMissing(let artifactID):
            return "Artifact \(artifactID) has no readable data."
        }
    }
}
