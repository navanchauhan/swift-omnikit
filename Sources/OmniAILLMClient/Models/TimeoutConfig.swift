import Foundation

public struct TimeoutConfig: Sendable {
    public var total: TimeInterval?
    public var perStep: TimeInterval?

    public init(total: TimeInterval? = nil, perStep: TimeInterval? = nil) {
        self.total = total
        self.perStep = perStep
    }
}

public struct AdapterTimeout: Sendable {
    public var connect: TimeInterval
    public var request: TimeInterval
    public var streamRead: TimeInterval

    public init(connect: TimeInterval = 10, request: TimeInterval = 120, streamRead: TimeInterval = 30) {
        self.connect = connect
        self.request = request
        self.streamRead = streamRead
    }

    public static let `default` = AdapterTimeout()
}

public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval
    public var backoffMultiplier: Double
    public var jitter: Bool
    public var onRetry: (@Sendable (Error, Int, TimeInterval) -> Void)?

    public init(
        maxRetries: Int = 2,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        backoffMultiplier: Double = 2.0,
        jitter: Bool = true,
        onRetry: (@Sendable (Error, Int, TimeInterval) -> Void)? = nil
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.jitter = jitter
        self.onRetry = onRetry
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        var d = min(baseDelay * pow(backoffMultiplier, Double(attempt)), maxDelay)
        if jitter {
            d *= Double.random(in: 0.5...1.5)
        }
        return d
    }

    public static let `default` = RetryPolicy()
    public static let none = RetryPolicy(maxRetries: 0)
}
