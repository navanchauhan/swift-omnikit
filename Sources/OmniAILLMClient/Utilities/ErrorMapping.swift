import Foundation

struct ErrorMapper {
    static func mapHTTPError(
        statusCode: Int,
        message: String,
        provider: String,
        errorCode: String? = nil,
        raw: [String: Any]? = nil,
        retryAfter: Double? = nil
    ) -> ProviderError {
        // First check status code
        switch statusCode {
        case 400, 422:
            // Check message for more specific errors
            let lowerMsg = message.lowercased()
            if lowerMsg.contains("context length") || lowerMsg.contains("too many tokens") || lowerMsg.contains("maximum context") {
                return ContextLengthError(message: message, provider: provider, statusCode: statusCode, raw: raw)
            }
            if lowerMsg.contains("content filter") || lowerMsg.contains("safety") {
                return ContentFilterError(message: message, provider: provider, statusCode: statusCode, raw: raw)
            }
            return InvalidRequestError(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, raw: raw)
        case 401:
            return AuthenticationError(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, raw: raw)
        case 403:
            return AccessDeniedError(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, raw: raw)
        case 404:
            return NotFoundError(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, raw: raw)
        case 408:
            return ProviderError(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryable: true, retryAfter: retryAfter, raw: raw)
        case 413:
            return ContextLengthError(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, raw: raw)
        case 429:
            return RateLimitError(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryAfter: retryAfter, raw: raw)
        case 500...504:
            return ServerError(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, raw: raw)
        default:
            // Apply message-based classification for ambiguous cases
            let lowerMsg = message.lowercased()
            if lowerMsg.contains("not found") || lowerMsg.contains("does not exist") {
                return NotFoundError(message: message, provider: provider, statusCode: statusCode, raw: raw)
            }
            if lowerMsg.contains("unauthorized") || lowerMsg.contains("invalid key") || lowerMsg.contains("invalid api key") {
                return AuthenticationError(message: message, provider: provider, statusCode: statusCode, raw: raw)
            }
            if lowerMsg.contains("context length") || lowerMsg.contains("too many tokens") {
                return ContextLengthError(message: message, provider: provider, statusCode: statusCode, raw: raw)
            }
            if lowerMsg.contains("content filter") || lowerMsg.contains("safety") {
                return ContentFilterError(message: message, provider: provider, statusCode: statusCode, raw: raw)
            }
            // Unknown errors default to retryable
            return ProviderError(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryable: true, raw: raw)
        }
    }

    static func parseErrorResponse(data: Data, provider: String) -> (message: String, errorCode: String?, raw: [String: Any]?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (String(data: data, encoding: .utf8) ?? "Unknown error", nil, nil)
        }

        var message = "Unknown error"
        var errorCode: String?

        if let error = json["error"] as? [String: Any] {
            message = error["message"] as? String ?? message
            errorCode = error["code"] as? String ?? error["type"] as? String
        } else if let msg = json["message"] as? String {
            message = msg
        } else if let msg = json["error"] as? String {
            message = msg
        }

        return (message, errorCode, json)
    }
}
