import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct HTTPClient {
    let session: URLSession
    let timeout: AdapterTimeout

    init(timeout: AdapterTimeout = .default) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout.request
        config.timeoutIntervalForResource = timeout.request * 2
        self.session = URLSession(configuration: config)
        self.timeout = timeout
    }

    struct HTTPResponse {
        let data: Data
        let statusCode: Int
        let headers: [String: String]
    }

    func post(
        url: URL,
        body: Data,
        headers: [String: String]
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError(message: "Invalid HTTP response")
        }

        var responseHeaders: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                responseHeaders[k.lowercased()] = v
            }
        }

        return HTTPResponse(
            data: data,
            statusCode: httpResponse.statusCode,
            headers: responseHeaders
        )
    }

    func postStream(
        url: URL,
        body: Data,
        headers: [String: String]
    ) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError(message: "Invalid HTTP response")
        }

        let bytes = AsyncThrowingStream<UInt8, Error> { continuation in
            for byte in data {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        return (bytes, httpResponse)
    }

    static func parseRateLimitInfo(headers: [String: String]) -> RateLimitInfo? {
        let remaining = headers["x-ratelimit-remaining-requests"].flatMap(Int.init)
        let limit = headers["x-ratelimit-limit-requests"].flatMap(Int.init)
        let tokensRemaining = headers["x-ratelimit-remaining-tokens"].flatMap(Int.init)
        let tokensLimit = headers["x-ratelimit-limit-tokens"].flatMap(Int.init)

        if remaining != nil || limit != nil || tokensRemaining != nil || tokensLimit != nil {
            return RateLimitInfo(
                requestsRemaining: remaining,
                requestsLimit: limit,
                tokensRemaining: tokensRemaining,
                tokensLimit: tokensLimit
            )
        }
        return nil
    }

    static func parseRetryAfter(headers: [String: String]) -> Double? {
        guard let value = headers["retry-after"] else { return nil }
        return Double(value)
    }
}
