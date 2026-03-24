import Foundation

public enum TelegramCallbackAction: Equatable, Sendable {
    case approval(requestID: String, approved: Bool)
    case question(requestID: String, answer: String)
}

public enum TelegramCallbackCodec {
    public static func encode(_ action: TelegramCallbackAction) -> String {
        switch action {
        case .approval(let requestID, let approved):
            return "approval:\(requestID):\(approved ? "approve" : "reject")"
        case .question(let requestID, let answer):
            return "question:\(requestID):\(base64URLEncode(answer))"
        }
    }

    public static func decode(_ rawValue: String) -> TelegramCallbackAction? {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else {
            return nil
        }

        switch parts[0] {
        case "approval":
            switch parts[2] {
            case "approve":
                return .approval(requestID: parts[1], approved: true)
            case "reject":
                return .approval(requestID: parts[1], approved: false)
            default:
                return nil
            }
        case "question":
            let encoded = parts.dropFirst(2).joined(separator: ":")
            guard let decoded = base64URLDecode(encoded) else {
                return nil
            }
            return .question(requestID: parts[1], answer: decoded)
        default:
            return nil
        }
    }

    private static func base64URLEncode(_ text: String) -> String {
        Data(text.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ text: String) -> String? {
        var normalized = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: normalized) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
