import Foundation
import PhotonImessage
import OmniAgentMesh
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

public actor ImessageIngressHandler {
    private let session: PhotonImessage.Session
    private let gateway: IngressGateway
    private let deliveryStore: any DeliveryStore
    private var chatKindCache: [String: IngressEnvelope.ChannelKind] = [:]
    private var lastCursor: String?

    public init(
        session: PhotonImessage.Session,
        gateway: IngressGateway,
        deliveryStore: any DeliveryStore
    ) {
        self.session = session
        self.gateway = gateway
        self.deliveryStore = deliveryStore
    }

    public static func make(
        gateway: IngressGateway,
        deliveryStore: any DeliveryStore,
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
        return ImessageIngressHandler(
            session: session,
            gateway: gateway,
            deliveryStore: deliveryStore
        )
    }

    public func run() async throws {
        while !Task.isCancelled {
            let stream = session.subscribeMessageEvents(cursor: lastCursor)
            do {
                for try await response in stream {
                    updateCursor(from: response)
                    if let envelope = try await makeEnvelope(from: response) {
                        let result = try await gateway.handle(envelope)
                        try await deliver(result.deliveries)
                    }
                }
                try await Task.sleep(for: .seconds(1))
                } catch {
                    if error is CancellationError {
                        throw error
                    }

                    print("[iMessage] inbound message event failed: \(error)")
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }

    public func close() async {
        await session.close()
    }

    private func makeEnvelope(
        from response: PIMsg_SubscribeMessageEventsResponse
    ) async throws -> IngressEnvelope? {
        guard let payload = response.payload else {
            return nil
        }

        switch payload {
        case .messageReceived(let event):
            return try await makeEnvelope(from: event, response: response)
        case .messageSent, .messageUpdated, .heartbeat:
            return nil
        }
    }

    private func makeEnvelope(
        from event: PIMsg_MessageReceivedEvent,
        response: PIMsg_SubscribeMessageEventsResponse
    ) async throws -> IngressEnvelope? {
        let message = event.message
        guard !message.isFromMe else {
            return nil
        }

        let actorExternalID = normalizedActorExternalID(from: message.sender)
        guard !actorExternalID.isEmpty else {
            return nil
        }

        let chatGuid = normalizedChatGuid(from: event.chatGuid, message: message)
        guard !chatGuid.isEmpty else {
            return nil
        }

        let hasText = !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let attachments = mappedAttachments(from: message.attachments)
        let payloadKind: IngressEnvelope.PayloadKind = hasText ? .text : .unsupported
        let channelKind = await resolveChannelKind(for: chatGuid)
        let updateID = message.guid.isEmpty ? responseCursorFallback(response: response) : message.guid
        let responseCursor = response.cursor.value.trimmingCharacters(in: .whitespacesAndNewlines)

        var metadata: [String: String] = [
            "photon_chat_guid": chatGuid,
            "photon_message_is_from_me": String(message.isFromMe),
        ]

        if !message.guid.isEmpty {
            metadata["photon_message_guid"] = message.guid
        }
        if !responseCursor.isEmpty {
            metadata["photon_response_cursor"] = responseCursor
        }
        if !event.chatGuid.isEmpty {
            metadata["photon_event_chat_guid"] = event.chatGuid
        }
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
            text: hasText ? message.text : nil,
            attachments: attachments,
            mentionTriggerActive: false,
            replyContextActive: false,
            metadata: metadata
        )
    }

    private func deliver(_ instructions: [IngressDeliveryInstruction]) async throws {
        for instruction in instructions {
            do {
                switch instruction.kind {
                case .callbackAcknowledgement:
                    let acknowledgementText = instruction.chunks.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let acknowledgementText, !acknowledgementText.isEmpty {
                        let sentMessageIDs = try await send(
                            instruction: instruction,
                            chunks: [acknowledgementText]
                        )
                        try await markDelivery(
                            idempotencyKey: instruction.idempotencyKey,
                            instruction: instruction,
                            status: .delivered,
                            messageID: sentMessageIDs.joined(separator: ",")
                        )
                    } else {
                        try await markDelivery(
                            idempotencyKey: instruction.idempotencyKey,
                            instruction: instruction,
                            status: .delivered,
                            messageID: nil
                        )
                    }
                case .message:
                    let sentMessageIDs = try await send(
                        instruction: instruction,
                        chunks: instruction.chunks
                    )
                    try await markDelivery(
                        idempotencyKey: instruction.idempotencyKey,
                        instruction: instruction,
                        status: .delivered,
                        messageID: sentMessageIDs.joined(separator: ",")
                    )
                }
            } catch {
                try await markDelivery(
                    idempotencyKey: instruction.idempotencyKey,
                    instruction: instruction,
                    status: .failed,
                    messageID: nil,
                    errorDescription: String(describing: error)
                )
                throw error
            }
        }
    }

    private func send(
        instruction: IngressDeliveryInstruction,
        chunks: [String]
    ) async throws -> [String] {
        guard !instruction.targetExternalID.isEmpty else {
            throw ImessageOutboundError.invalidTargetExternalID
        }
        guard !chunks.isEmpty else {
            return []
        }

        var sentMessageIDs: [String] = []
        for chunk in chunks {
            let text = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }
            let receipt = try await session.send(chatGuid: instruction.targetExternalID, message: text)
            sentMessageIDs.append(receipt.guid)
        }
        return sentMessageIDs
    }

    private func markDelivery(
        idempotencyKey: String,
        instruction: IngressDeliveryInstruction,
        status: DeliveryRecord.Status,
        messageID: String?,
        errorDescription: String? = nil
    ) async throws {
        var record = try await deliveryStore.delivery(idempotencyKey: idempotencyKey) ?? DeliveryRecord(
            idempotencyKey: idempotencyKey,
            direction: .outbound,
            transport: .imessage,
            status: status,
            summary: instruction.chunks.joined(separator: "\n"),
            metadata: instruction.metadata
        )
        record.transport = .imessage
        record.actorID = instruction.actorID
        record.workspaceID = instruction.workspaceID
        record.channelID = instruction.channelID
        record.messageID = messageID
        record.status = status
        record.summary = instruction.chunks.joined(separator: "\n")
        var metadata = instruction.metadata
        metadata["target_external_id"] = instruction.targetExternalID
        metadata["delivered_message_id"] = messageID ?? ""
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

    private func mappedAttachments(from attachments: [PIMsg_AttachmentInfo]) -> [IngressEnvelope.Attachment] {
        attachments.map { attachment in
            IngressEnvelope.Attachment(
                name: attachment.fileName.isEmpty ? attachment.guid : attachment.fileName,
                contentType: attachment.mimeType.isEmpty ? "application/octet-stream" : attachment.mimeType,
                metadata: [
                    "photon_attachment_guid": attachment.guid,
                    "photon_attachment_uti": attachment.uti,
                    "photon_attachment_transferred_bytes": String(attachment.totalBytes),
                ]
            )
        }
    }

    private func normalizedActorExternalID(from sender: PIMsg_AddressInfo) -> String {
        return [
            sender.address,
            sender.uncanonicalizedID,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? ""
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

public enum ImessageOutboundError: Error, CustomStringConvertible, Sendable {
    case invalidTargetExternalID

    public var description: String {
        switch self {
        case .invalidTargetExternalID:
            return "The outbound target chat GUID is empty."
        }
    }
}
