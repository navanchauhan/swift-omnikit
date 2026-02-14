import XCTest
@testable import OmniAILLMClient

// MARK: - 8.8 Error Handling & Retry Tests

final class ErrorHandlingTests: XCTestCase {

    func testRetryPolicyDelayCalculation() {
        let policy = RetryPolicy(maxRetries: 3, baseDelay: 1.0, backoffMultiplier: 2.0, jitter: false)
        XCTAssertEqual(policy.delay(forAttempt: 0), 1.0)
        XCTAssertEqual(policy.delay(forAttempt: 1), 2.0)
        XCTAssertEqual(policy.delay(forAttempt: 2), 4.0)
        XCTAssertEqual(policy.delay(forAttempt: 3), 8.0)
    }

    func testRetryPolicyMaxDelay() {
        let policy = RetryPolicy(maxRetries: 10, baseDelay: 1.0, maxDelay: 5.0, backoffMultiplier: 2.0, jitter: false)
        XCTAssertEqual(policy.delay(forAttempt: 10), 5.0)
    }

    func testRetryPolicyJitter() {
        let policy = RetryPolicy(maxRetries: 3, baseDelay: 1.0, backoffMultiplier: 2.0, jitter: true)
        // With jitter, delays should be in range [base*0.5, base*1.5]
        let delay = policy.delay(forAttempt: 0)
        XCTAssertGreaterThanOrEqual(delay, 0.5)
        XCTAssertLessThanOrEqual(delay, 1.5)
    }

    func testErrorHierarchy() {
        let auth = AuthenticationError(message: "bad key", provider: "test")
        XCTAssertTrue(auth is ProviderError)
        XCTAssertTrue(auth is SDKError)
        XCTAssertFalse(auth.retryable)

        let rate = RateLimitError(message: "too many", provider: "test", retryAfter: 5.0)
        XCTAssertTrue(rate.retryable)
        XCTAssertEqual(rate.retryAfter, 5.0)

        let server = ServerError(message: "internal", provider: "test", statusCode: 500)
        XCTAssertTrue(server.retryable)
        XCTAssertEqual(server.statusCode, 500)

        let notFound = NotFoundError(message: "not found", provider: "test")
        XCTAssertFalse(notFound.retryable)

        let config = ConfigurationError(message: "no provider")
        XCTAssertTrue(config is SDKError)
    }

    func testErrorMapping() {
        let error400 = ErrorMapper.mapHTTPError(statusCode: 400, message: "bad request", provider: "test")
        XCTAssertTrue(error400 is InvalidRequestError)

        let error401 = ErrorMapper.mapHTTPError(statusCode: 401, message: "unauthorized", provider: "test")
        XCTAssertTrue(error401 is AuthenticationError)

        let error403 = ErrorMapper.mapHTTPError(statusCode: 403, message: "forbidden", provider: "test")
        XCTAssertTrue(error403 is AccessDeniedError)

        let error404 = ErrorMapper.mapHTTPError(statusCode: 404, message: "not found", provider: "test")
        XCTAssertTrue(error404 is NotFoundError)

        let error429 = ErrorMapper.mapHTTPError(statusCode: 429, message: "rate limited", provider: "test", retryAfter: 2.0)
        XCTAssertTrue(error429 is RateLimitError)
        XCTAssertTrue(error429.retryable)

        let error500 = ErrorMapper.mapHTTPError(statusCode: 500, message: "internal error", provider: "test")
        XCTAssertTrue(error500 is ServerError)
        XCTAssertTrue(error500.retryable)

        let error413 = ErrorMapper.mapHTTPError(statusCode: 413, message: "too large", provider: "test")
        XCTAssertTrue(error413 is ContextLengthError)
    }

    func testMessageBasedClassification() {
        // Context length from message
        let ctxError = ErrorMapper.mapHTTPError(statusCode: 400, message: "context length exceeded", provider: "test")
        XCTAssertTrue(ctxError is ContextLengthError)

        // Content filter from message
        let filterError = ErrorMapper.mapHTTPError(statusCode: 400, message: "content filter triggered", provider: "test")
        XCTAssertTrue(filterError is ContentFilterError)
    }

    func testRetryWithNonRetryableError() async {
        var attempts = 0
        do {
            let _: String = try await retry(policy: RetryPolicy(maxRetries: 3)) {
                attempts += 1
                throw AuthenticationError(message: "bad key", provider: "test")
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(attempts, 1, "Non-retryable error should not retry")
        }
    }

    func testMaxRetriesZeroDisablesRetry() async {
        var attempts = 0
        do {
            let _: String = try await retry(policy: RetryPolicy(maxRetries: 0)) {
                attempts += 1
                throw ServerError(message: "error", provider: "test")
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(attempts, 1, "maxRetries=0 should not retry")
        }
    }
}
