import Foundation

public func retry<T>(
    policy: RetryPolicy = .default,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var lastError: Error?

    for attempt in 0...policy.maxRetries {
        do {
            return try await operation()
        } catch {
            lastError = error

            // Check if retryable
            if let providerError = error as? ProviderError, !providerError.retryable {
                throw error
            }
            if error is ConfigurationError || error is AbortError || error is InvalidToolCallError || error is NoObjectGeneratedError {
                throw error
            }

            // Don't retry if we've exhausted attempts
            if attempt >= policy.maxRetries {
                throw error
            }

            // Calculate delay
            var delay = policy.delay(forAttempt: attempt)

            // Check Retry-After header
            if let providerError = error as? ProviderError, let retryAfter = providerError.retryAfter {
                if retryAfter > policy.maxDelay {
                    throw error  // Don't wait that long
                }
                delay = retryAfter
            }

            policy.onRetry?(error, attempt, delay)

            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    throw lastError ?? SDKError(message: "Retry failed with no error")
}
