import Foundation
import OmniHTTP

#if canImport(Darwin)
public struct URLSessionOpenAIResponsesWebSocketTransport: OpenAIResponsesWebSocketTransport {
    public init() {}

    public func openResponseEventStream(
        url: URL,
        headers: OmniHTTP.HTTPHeaders,
        createEvent: JSONValue,
        timeout: Duration?
    ) async throws -> AsyncThrowingStream<JSONValue, Error> {
        var request = URLRequest(url: url)
        for (name, value) in headers.asDictionary {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let createFrameText = _ProviderHTTP.stringifyJSON(createEvent)

        return AsyncThrowingStream { continuation in
            let finish = _URLSessionFinishOnce()
            let session = URLSession(configuration: .ephemeral)
            let task = session.webSocketTask(with: request)

            continuation.onTermination = { _ in
                task.cancel(with: .goingAway, reason: nil)
                session.invalidateAndCancel()
            }

            Task {
                do {
                    task.resume()
                    try await send(task: task, text: createFrameText, timeout: timeout)

                    while !Task.isCancelled {
                        let message = try await receive(task: task, timeout: timeout)
                        let payload: JSONValue
                        switch message {
                        case .string(let text):
                            payload = try parsePayload(text: text)
                        case .data(let data):
                            payload = try JSONValue.parse(data)
                        @unknown default:
                            continue
                        }

                        continuation.yield(payload)

                        if isTerminalEvent(payload["type"]?.stringValue) {
                            task.cancel(with: .normalClosure, reason: nil)
                            finish.run { continuation.finish() }
                            return
                        }
                    }

                    finish.run { continuation.finish() }
                } catch {
                    finish.run { continuation.finish(throwing: error) }
                }
            }
        }
    }

    private func send(
        task: URLSessionWebSocketTask,
        text: String,
        timeout: Duration?
    ) async throws {
        _ = timeout
        try await task.send(.string(text))
    }

    private func receive(
        task: URLSessionWebSocketTask,
        timeout: Duration?
    ) async throws -> URLSessionWebSocketTask.Message {
        _ = timeout
        return try await task.receive()
    }

    private func parsePayload(text: String) throws -> JSONValue {
        guard let data = text.data(using: .utf8) else {
            throw StreamError(message: "OpenAI websocket received non-UTF8 text frame")
        }
        return try JSONValue.parse(data)
    }

    private func isTerminalEvent(_ type: String?) -> Bool {
        switch type {
        case "response.completed", "response.failed", "response.incomplete", "response.error", "error":
            return true
        default:
            return false
        }
    }
}

private final class _URLSessionFinishOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func run(_ body: () -> Void) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        body()
    }
}
#endif
