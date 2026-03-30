import Foundation
import TheAgentIngress

public enum TelegramDeliveryFormatter {
    public static func sendRequests(for instruction: IngressDeliveryInstruction) -> [TelegramSendMessageRequest] {
        let target = parseTarget(instruction.targetExternalID)
        return instruction.chunks.enumerated().map { index, chunk in
            TelegramSendMessageRequest(
                chatID: target.chatID,
                text: formatTelegramHTML(chunk),
                parseMode: .html,
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

    private static func formatTelegramHTML(_ text: String) -> String {
        let normalizedLines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            normalizeListPrefix(String(line))
        }
        let escaped = escapeHTML(normalizedLines.joined(separator: "\n"))
        let withBold = replacing(
            pattern: #"\*\*(.+?)\*\*"#,
            in: escaped,
            template: "<b>$1</b>"
        )
        return replacing(
            pattern: #"(?<!\*)\*(?!\s)(.+?)(?<!\s)\*(?!\*)"#,
            in: withBold,
            template: "<i>$1</i>"
        )
    }

    private static func normalizeListPrefix(_ line: String) -> String {
        let trimmedPrefix = line.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("* ") || line.hasPrefix("- ") else {
            return trimmedPrefix == line ? line : line
        }
        let indentCount = line.prefix { $0 == " " || $0 == "\t" }.count
        let indent = String(repeating: " ", count: indentCount)
        let body = line.dropFirst(2)
        return indent + "• " + body
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func replacing(pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
