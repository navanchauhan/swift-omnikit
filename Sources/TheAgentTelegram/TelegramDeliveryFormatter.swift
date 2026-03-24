import Foundation
import TheAgentIngress

public enum TelegramDeliveryFormatter {
    public static func sendRequests(for instruction: IngressDeliveryInstruction) -> [TelegramSendMessageRequest] {
        let target = parseTarget(instruction.targetExternalID)
        return instruction.chunks.enumerated().map { index, chunk in
            TelegramSendMessageRequest(
                chatID: target.chatID,
                text: chunk,
                messageThreadID: target.messageThreadID,
                replyMarkup: index == 0 ? replyMarkup(for: instruction) : nil
            )
        }
    }

    public static func callbackAcknowledgementText(for instruction: IngressDeliveryInstruction) -> String? {
        instruction.chunks.first
    }

    private static func replyMarkup(for instruction: IngressDeliveryInstruction) -> TelegramInlineKeyboardMarkup? {
        guard let interactionKind = instruction.metadata["interaction_kind"],
              let requestID = instruction.metadata["request_id"] else {
            return nil
        }

        if interactionKind == "approval" {
            return TelegramInlineKeyboardMarkup(
                inlineKeyboard: [[
                    TelegramInlineKeyboardButton(
                        text: "Approve",
                        callbackData: TelegramCallbackCodec.encode(.approval(requestID: requestID, approved: true))
                    ),
                    TelegramInlineKeyboardButton(
                        text: "Reject",
                        callbackData: TelegramCallbackCodec.encode(.approval(requestID: requestID, approved: false))
                    ),
                ]]
            )
        }

        guard interactionKind == "question" else {
            return nil
        }

        let questionKind = instruction.metadata["question_kind"] ?? "free_text"
        guard questionKind == "confirmation" || questionKind == "single_select" else {
            return nil
        }

        let options = instruction.metadata["question_options"]?
            .split(separator: "\u{1F}")
            .map(String.init) ?? []
        guard !options.isEmpty else {
            if questionKind == "confirmation" {
                return TelegramInlineKeyboardMarkup(
                    inlineKeyboard: [[
                        TelegramInlineKeyboardButton(
                            text: "Yes",
                            callbackData: TelegramCallbackCodec.encode(.question(requestID: requestID, answer: "yes"))
                        ),
                        TelegramInlineKeyboardButton(
                            text: "No",
                            callbackData: TelegramCallbackCodec.encode(.question(requestID: requestID, answer: "no"))
                        ),
                    ]]
                )
            }
            return nil
        }

        let rows = options.map { option in
            [TelegramInlineKeyboardButton(
                text: option,
                callbackData: TelegramCallbackCodec.encode(.question(requestID: requestID, answer: option))
            )]
        }
        return TelegramInlineKeyboardMarkup(inlineKeyboard: rows)
    }

    private static func parseTarget(_ externalID: String) -> (chatID: String, messageThreadID: Int64?) {
        if externalID.hasPrefix("dm:") {
            return (chatID: String(externalID.dropFirst(3)), messageThreadID: nil)
        }

        let parts = externalID.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, let threadID = Int64(parts[1]) {
            return (chatID: parts[0], messageThreadID: threadID)
        }
        return (chatID: externalID, messageThreadID: nil)
    }
}
