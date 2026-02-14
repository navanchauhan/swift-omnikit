import Foundation

public class SDKError: Error, @unchecked Sendable {
    public let message: String
    public let cause: Error?

    public init(message: String, cause: Error? = nil) {
        self.message = message
        self.cause = cause
    }

    public var localizedDescription: String { message }
}

public class ProviderError: SDKError {
    public let provider: String
    public let statusCode: Int?
    public let errorCode: String?
    public let retryable: Bool
    public let retryAfter: Double?
    public let raw: [String: Any]?

    public init(
        message: String,
        provider: String,
        statusCode: Int? = nil,
        errorCode: String? = nil,
        retryable: Bool = false,
        retryAfter: Double? = nil,
        raw: [String: Any]? = nil,
        cause: Error? = nil
    ) {
        self.provider = provider
        self.statusCode = statusCode
        self.errorCode = errorCode
        self.retryable = retryable
        self.retryAfter = retryAfter
        self.raw = raw
        super.init(message: message, cause: cause)
    }
}

public final class AuthenticationError: ProviderError {
    public init(message: String, provider: String, statusCode: Int? = 401, errorCode: String? = nil, raw: [String: Any]? = nil) {
        super.init(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryable: false, raw: raw)
    }
}

public final class AccessDeniedError: ProviderError {
    public init(message: String, provider: String, statusCode: Int? = 403, errorCode: String? = nil, raw: [String: Any]? = nil) {
        super.init(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryable: false, raw: raw)
    }
}

public final class NotFoundError: ProviderError {
    public init(message: String, provider: String, statusCode: Int? = 404, errorCode: String? = nil, raw: [String: Any]? = nil) {
        super.init(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryable: false, raw: raw)
    }
}

public final class InvalidRequestError: ProviderError {
    public init(message: String, provider: String, statusCode: Int? = 400, errorCode: String? = nil, raw: [String: Any]? = nil) {
        super.init(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryable: false, raw: raw)
    }
}

public final class RateLimitError: ProviderError {
    public init(message: String, provider: String, statusCode: Int? = 429, errorCode: String? = nil, retryAfter: Double? = nil, raw: [String: Any]? = nil) {
        super.init(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryable: true, retryAfter: retryAfter, raw: raw)
    }
}

public final class ServerError: ProviderError {
    public init(message: String, provider: String, statusCode: Int? = 500, errorCode: String? = nil, raw: [String: Any]? = nil) {
        super.init(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryable: true, raw: raw)
    }
}

public final class ContentFilterError: ProviderError {
    public init(message: String, provider: String, statusCode: Int? = nil, errorCode: String? = nil, raw: [String: Any]? = nil) {
        super.init(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryable: false, raw: raw)
    }
}

public final class ContextLengthError: ProviderError {
    public init(message: String, provider: String, statusCode: Int? = 413, errorCode: String? = nil, raw: [String: Any]? = nil) {
        super.init(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryable: false, raw: raw)
    }
}

public final class QuotaExceededError: ProviderError {
    public init(message: String, provider: String, statusCode: Int? = nil, errorCode: String? = nil, raw: [String: Any]? = nil) {
        super.init(message: message, provider: provider, statusCode: statusCode, errorCode: errorCode, retryable: false, raw: raw)
    }
}

public final class RequestTimeoutError: SDKError {
    public override init(message: String = "Request timed out", cause: Error? = nil) {
        super.init(message: message, cause: cause)
    }
}

public final class AbortError: SDKError {
    public init(message: String = "Request was cancelled") {
        super.init(message: message)
    }
}

public final class NetworkError: SDKError {
    public override init(message: String, cause: Error? = nil) {
        super.init(message: message, cause: cause)
    }
}

public final class StreamError: SDKError {
    public override init(message: String, cause: Error? = nil) {
        super.init(message: message, cause: cause)
    }
}

public final class InvalidToolCallError: SDKError {
    public init(message: String) {
        super.init(message: message)
    }
}

public final class NoObjectGeneratedError: SDKError {
    public init(message: String) {
        super.init(message: message)
    }
}

public final class ConfigurationError: SDKError {
    public init(message: String) {
        super.init(message: message)
    }
}

public final class UnsupportedToolChoiceError: SDKError {
    public init(mode: String, provider: String) {
        super.init(message: "Tool choice mode '\(mode)' is not supported by provider '\(provider)'")
    }
}
