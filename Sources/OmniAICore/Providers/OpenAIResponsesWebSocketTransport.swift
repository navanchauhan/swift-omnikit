import Foundation

import NIOPosix
import OmniHTTP
import WebSocketKit

public protocol OpenAIResponsesWebSocketTransport: Sendable {
    func openResponseEventStream(
        url: URL,
        headers: OmniHTTP.HTTPHeaders,
        createEvent: JSONValue,
        timeout: Duration?
    ) async throws -> AsyncThrowingStream<JSONValue, Error>
}

public struct NIOOpenAIResponsesWebSocketTransport: OpenAIResponsesWebSocketTransport {
    public init() {}

    public func openResponseEventStream(
        url: URL,
        headers: OmniHTTP.HTTPHeaders,
        createEvent: JSONValue,
        timeout: Duration?
    ) async throws -> AsyncThrowingStream<JSONValue, Error> {
        let createFrameText = _ProviderHTTP.stringifyJSON(createEvent)
        let wsHeaders = toWebSocketHeaders(headers)
        let cancellationHook = _CancellationHook()

        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in
                cancellationHook.run()
            }

            Task {
                let client = WebSocketClient(eventLoopGroupProvider: .createNew)
                let finishOnce = _FinishOnce()

                let finish: @Sendable (Error?) -> Void = { error in
                    finishOnce.run {
                        if let error {
                            continuation.finish(throwing: error)
                        } else {
                            continuation.finish()
                        }
                    }
                }

                do {
                    let socket = try await connect(
                        client: client,
                        url: url,
                        headers: wsHeaders,
                        timeout: timeout
                    )

                    cancellationHook.set {
                        socket.eventLoop.execute {
                            socket.close(code: .goingAway).whenComplete { _ in }
                        }
                        try? client.syncShutdown()
                    }

                    socket.onText { ws, text in
                        do {
                            let payload = try parseJSONPayload(text)
                            continuation.yield(payload)
                            if isTerminalOpenAIEvent(payload["type"]?.stringValue) {
                                ws.close(code: .normalClosure).whenComplete { _ in }
                            }
                        } catch {
                            ws.close(code: .unexpectedServerError).whenComplete { _ in }
                            finish(StreamError(message: "OpenAI websocket invalid JSON payload", cause: error))
                        }
                    }

                    socket.onBinary { ws, buffer in
                        do {
                            var copy = buffer
                            let bytes = copy.readBytes(length: copy.readableBytes) ?? []
                            let payload = try JSONValue.parse(bytes)
                            continuation.yield(payload)
                            if isTerminalOpenAIEvent(payload["type"]?.stringValue) {
                                ws.close(code: .normalClosure).whenComplete { _ in }
                            }
                        } catch {
                            ws.close(code: .unexpectedServerError).whenComplete { _ in }
                            finish(StreamError(message: "OpenAI websocket invalid binary JSON payload", cause: error))
                        }
                    }

                    socket.onClose.whenComplete { result in
                        if case .failure(let error) = result {
                            finish(error)
                        } else {
                            finish(nil)
                        }
                    }

                    try await sendTextOnEventLoop(
                        socket: socket,
                        text: createFrameText,
                        timeout: timeout
                    )
                    try await waitForFuture(socket.onClose, timeout: timeout, phase: "receive")
                } catch {
                    finish(error)
                }

                do {
                    try client.syncShutdown()
                } catch {
                    // Ignore shutdown races from cancellation / close callbacks.
                }
            }
        }
    }
}

private func toWebSocketHeaders(_ headers: OmniHTTP.HTTPHeaders) -> WebSocketKit.HTTPHeaders {
    var out: WebSocketKit.HTTPHeaders = [:]
    for (name, value) in headers.asDictionary {
        out.add(name: name, value: value)
    }
    return out
}

private func parseJSONPayload(_ text: String) throws -> JSONValue {
    guard let data = text.data(using: .utf8) else {
        throw StreamError(message: "OpenAI websocket received non-UTF8 text frame")
    }
    return try JSONValue.parse(data)
}

private func isTerminalOpenAIEvent(_ type: String?) -> Bool {
    switch type {
    case "response.completed", "response.failed", "response.incomplete", "response.error", "error":
        return true
    default:
        return false
    }
}

private func connect(
    client: WebSocketClient,
    url: URL,
    headers: WebSocketKit.HTTPHeaders,
    timeout: Duration?
) async throws -> WebSocket {
    let scheme = (url.scheme ?? "").lowercased()
    guard scheme == "ws" || scheme == "wss", let host = url.host else {
        throw OmniHTTPError.invalidURL(url.absoluteString)
    }
    let port = url.port ?? (scheme == "wss" ? 443 : 80)
    let path = url.path.isEmpty ? "/" : url.path
    let query = url.query

    return try await withCheckedThrowingContinuation { continuation in
        let state = _ConnectResumeState()
        let future = client.connect(
            scheme: scheme,
            host: host,
            port: port,
            path: path,
            query: query,
            headers: headers
        ) { ws in
            state.resumeOnce(continuation) {
                continuation.resume(returning: ws)
            }
        }

        future.whenFailure { error in
            state.resumeOnce(continuation) {
                continuation.resume(throwing: error)
            }
        }

        if let timeout {
            let timeoutSeconds = durationSeconds(timeout)
            if timeoutSeconds > 0 {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    state.resumeOnce(continuation) {
                        continuation.resume(
                            throwing: RequestTimeoutError(
                                message: "OpenAI websocket connect timed out after \(timeoutSeconds)s"
                            )
                        )
                    }
                }
            }
        }
    }
}

private func waitForFuture(
    _ future: EventLoopFuture<Void>,
    timeout: Duration?,
    phase: String
) async throws {
    try await withCheckedThrowingContinuation { continuation in
        let state = _ConnectResumeState()
        future.whenComplete { result in
            state.resumeOnce(continuation) {
                continuation.resume(with: result)
            }
        }

        if let timeout {
            let timeoutSeconds = durationSeconds(timeout)
            if timeoutSeconds > 0 {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    state.resumeOnce(continuation) {
                        continuation.resume(
                            throwing: RequestTimeoutError(
                                message: "OpenAI websocket \(phase) timed out after \(timeoutSeconds)s"
                            )
                        )
                    }
                }
            }
        }
    }
}

private func sendTextOnEventLoop(
    socket: WebSocket,
    text: String,
    timeout: Duration?
) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let state = _ConnectResumeState()

        socket.eventLoop.execute {
            socket.send(text)
            state.resumeOnce(continuation) {
                continuation.resume()
            }
        }

        if let timeout {
            let timeoutSeconds = durationSeconds(timeout)
            if timeoutSeconds > 0 {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    state.resumeOnce(continuation) {
                        continuation.resume(
                            throwing: RequestTimeoutError(
                                message: "OpenAI websocket send timed out after \(timeoutSeconds)s"
                            )
                        )
                    }
                }
            }
        }
    }
}

private func durationSeconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + (Double(duration.components.attoseconds) / 1e18)
}

private final class _CancellationHook: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (() -> Void)?

    func set(_ callback: @escaping () -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    func run() {
        lock.lock()
        let callback = self.callback
        self.callback = nil
        lock.unlock()
        callback?()
    }
}

private final class _FinishOnce: @unchecked Sendable {
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

private final class _ConnectResumeState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resumeOnce<T>(_ continuation: CheckedContinuation<T, Error>, _ body: () -> Void) {
        lock.lock()
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()
        body()
    }
}
