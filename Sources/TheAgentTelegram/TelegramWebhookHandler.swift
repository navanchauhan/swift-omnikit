import Foundation
import OmniAgentMesh
import TheAgentIngress

public actor TelegramWebhookHandler {
    private let botUser: TelegramUser
    private let client: any TelegramBotAPI
    private let gateway: IngressGateway
    private let deliveryStore: any DeliveryStore
    private let expectedSecretToken: String?

    public init(
        botUser: TelegramUser,
        client: any TelegramBotAPI,
        gateway: IngressGateway,
        deliveryStore: any DeliveryStore,
        expectedSecretToken: String? = nil
    ) {
        self.botUser = botUser
        self.client = client
        self.gateway = gateway
        self.deliveryStore = deliveryStore
        self.expectedSecretToken = expectedSecretToken
    }

    public static func make(
        client: any TelegramBotAPI,
        gateway: IngressGateway,
        deliveryStore: any DeliveryStore,
        expectedSecretToken: String? = nil
    ) async throws -> TelegramWebhookHandler {
        let botUser = try await client.getMe()
        return TelegramWebhookHandler(
            botUser: botUser,
            client: client,
            gateway: gateway,
            deliveryStore: deliveryStore,
            expectedSecretToken: expectedSecretToken
        )
    }

    @discardableResult
    public func handle(
        body: Data,
        providedSecretToken: String?
    ) async throws -> IngressGatewayResult {
        try validateSecretToken(providedSecretToken)
        let update = try JSONDecoder().decode(TelegramUpdate.self, from: body)
        return try await handle(update: update)
    }

    @discardableResult
    public func handle(update: TelegramUpdate) async throws -> IngressGatewayResult {
        guard let envelope = makeEnvelope(from: update) else {
            return IngressGatewayResult(disposition: .ignored)
        }
        let result = try await gateway.handle(envelope)
        try await deliver(result.deliveries)
        return result
    }

    public func allowedUpdates() -> [String] {
        ["message", "callback_query"]
    }

    private func validateSecretToken(_ providedSecretToken: String?) throws {
        guard let expectedSecretToken, !expectedSecretToken.isEmpty else {
            return
        }
        guard providedSecretToken == expectedSecretToken else {
            throw TelegramWebhookHandlerError.invalidSecretToken
        }
    }

    public func deliver(_ instructions: [IngressDeliveryInstruction]) async throws {
        for instruction in instructions {
            do {
                switch instruction.kind {
                case .callbackAcknowledgement:
                    if let callbackQueryID = instruction.metadata["callback_query_id"] {
                        try await client.answerCallbackQuery(
                            callbackQueryID: callbackQueryID,
                            text: TelegramDeliveryFormatter.callbackAcknowledgementText(for: instruction),
                            showAlert: false
                        )
                    }
                    try await markDelivery(
                        idempotencyKey: instruction.idempotencyKey,
                        instruction: instruction,
                        status: .delivered,
                        messageID: instruction.metadata["callback_query_id"]
                    )
                case .message:
                    guard instruction.attachments.isEmpty else {
                        throw TelegramWebhookHandlerError.unsupportedAttachments
                    }
                    var sentMessageIDs: [String] = []
                    for request in TelegramDeliveryFormatter.sendRequests(for: instruction) {
                        let response = try await client.sendMessage(request)
                        sentMessageIDs.append(String(response.messageID))
                    }
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
            transport: .telegram,
            sessionID: nil,
            actorID: instruction.actorID,
            workspaceID: instruction.workspaceID,
            channelID: instruction.channelID,
            messageID: messageID,
            status: status,
            summary: instruction.chunks.joined(separator: "\n"),
            metadata: instruction.metadata
        )
        record.transport = .telegram
        record.actorID = instruction.actorID
        record.workspaceID = instruction.workspaceID
        record.channelID = instruction.channelID
        record.messageID = messageID
        record.status = status
        record.summary = instruction.chunks.joined(separator: "\n")
        record.metadata = instruction.metadata.merging(
            (
                errorDescription.map { ["error": $0] } ?? [:]
            ).merging([
                "target_external_id": record.metadata["target_external_id"] ?? instruction.targetExternalID,
                "delivered_message_id": messageID ?? "",
            ]) { _, new in new }
        ) { _, new in new }
        record.updatedAt = Date()
        _ = try await deliveryStore.saveDelivery(record)
    }

    private func makeEnvelope(from update: TelegramUpdate) -> IngressEnvelope? {
        if let callbackQuery = update.callbackQuery,
           let message = callbackQuery.message {
            return IngressEnvelope(
                transport: .telegram,
                payloadKind: .callback,
                updateID: String(update.updateID),
                messageID: String(message.messageID),
                actorExternalID: String(callbackQuery.from.id),
                actorDisplayName: displayName(for: callbackQuery.from),
                channelExternalID: channelExternalID(for: message.chat, threadID: message.messageThreadID, actorExternalID: String(callbackQuery.from.id)),
                channelKind: channelKind(for: message.chat, threadID: message.messageThreadID),
                callbackData: callbackQuery.data,
                mentionTriggerActive: true,
                replyContextActive: true,
                metadata: [
                    "callback_query_id": callbackQuery.id,
                    "telegram_update_id": String(update.updateID),
                ]
            )
        }

        guard let message = update.message, let from = message.from else {
            return nil
        }

        let payloadKind: IngressEnvelope.PayloadKind = {
            if message.text != nil {
                return .text
            }
            if message.hasUnsupportedMedia {
                return .unsupported
            }
            return .unsupported
        }()

        return IngressEnvelope(
            transport: .telegram,
            payloadKind: payloadKind,
            updateID: String(update.updateID),
            messageID: String(message.messageID),
            actorExternalID: String(from.id),
            actorDisplayName: displayName(for: from),
            channelExternalID: channelExternalID(for: message.chat, threadID: message.messageThreadID, actorExternalID: String(from.id)),
            channelKind: channelKind(for: message.chat, threadID: message.messageThreadID),
            text: message.text,
            attachments: message.hasUnsupportedMedia ? [
                .init(
                    name: "unsupported",
                    contentType: "application/octet-stream",
                    metadata: ["telegram_message_id": String(message.messageID)]
                ),
            ] : [],
            mentionTriggerActive: mentionTriggerActive(message.text),
            replyContextActive: replyContextActive(message.replyToMessage),
            metadata: [
                "telegram_update_id": String(update.updateID),
                "telegram_message_id": String(message.messageID),
            ]
        )
    }

    private func mentionTriggerActive(_ text: String?) -> Bool {
        guard let text, let username = botUser.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else {
            return false
        }
        return text.localizedStandardContains("@\(username)")
    }

    private func replyContextActive(_ replyToMessage: TelegramReplyMessage?) -> Bool {
        guard let replyToMessage else {
            return false
        }
        if replyToMessage.from?.id == botUser.id {
            return true
        }
        if let replyUsername = replyToMessage.from?.username,
           let botUsername = botUser.username {
            return replyUsername.caseInsensitiveCompare(botUsername) == .orderedSame
        }
        return false
    }

    private func displayName(for user: TelegramUser) -> String {
        [user.firstName, user.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func channelExternalID(
        for chat: TelegramChat,
        threadID: Int64?,
        actorExternalID: String
    ) -> String {
        if chat.type == .private {
            return "dm:\(actorExternalID)"
        }
        if let threadID {
            return "\(chat.id):\(threadID)"
        }
        return String(chat.id)
    }

    private func channelKind(for chat: TelegramChat, threadID: Int64?) -> IngressEnvelope.ChannelKind {
        switch chat.type {
        case .private:
            return .directMessage
        case .group, .supergroup, .channel:
            if threadID != nil {
                return .topic
            }
            return .group
        }
    }
}

public enum TelegramWebhookHandlerError: Error, CustomStringConvertible, Sendable {
    case invalidSecretToken
    case unsupportedAttachments

    public var description: String {
        switch self {
        case .invalidSecretToken:
            return "Telegram webhook secret token did not match the configured value."
        case .unsupportedAttachments:
            return "Telegram delivery does not support artifact attachments yet."
        }
    }
}
