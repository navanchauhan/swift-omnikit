import Testing
import Foundation
import OmniHTTP
import OmniHTTPNIO

@testable import OmniAICore

private actor OrderRecorder {
    private var events: [String] = []
    func add(_ e: String) { events.append(e) }
    func all() -> [String] { events }
}

private struct RecordingMiddleware: Middleware {
    let name: String
    let recorder: OrderRecorder

    func complete(request: Request, next: @Sendable @escaping (Request) async throws -> Response) async throws -> Response {
        await recorder.add("\(name).in")
        let resp = try await next(request)
        await recorder.add("\(name).out")
        return resp
    }

    func stream(
        request: Request,
        next: @Sendable @escaping (Request) async throws -> AsyncThrowingStream<StreamEvent, Error>
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        await recorder.add("\(name).in")
        let s = try await next(request)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await ev in s {
                        continuation.yield(ev)
                    }
                    await recorder.add("\(name).out")
                    continuation.finish()
                } catch {
                    await recorder.add("\(name).out")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private final class StaticAdapter: ProviderAdapter, @unchecked Sendable {
    let name: String
    let response: Response
    init(name: String, response: Response) {
        self.name = name
        self.response = response
    }
    func complete(request: Request) async throws -> Response { response }
    func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(StreamEvent(type: .standard(.streamStart)))
            continuation.yield(StreamEvent(type: .standard(.finish), finishReason: response.finishReason, usage: response.usage, response: response))
            continuation.finish()
        }
    }
}

private final class HeartbeatAdapter: ProviderAdapter, @unchecked Sendable {
    let name: String
    let response: Response
    let heartbeatCount: Int
    let heartbeatInterval: Duration

    init(name: String, response: Response, heartbeatCount: Int, heartbeatInterval: Duration) {
        self.name = name
        self.response = response
        self.heartbeatCount = heartbeatCount
        self.heartbeatInterval = heartbeatInterval
    }

    func complete(request: Request) async throws -> Response { response }

    func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(StreamEvent(type: .standard(.streamStart)))
                    for beat in 0..<heartbeatCount {
                        try await Task.sleep(for: heartbeatInterval)
                        continuation.yield(
                            StreamEvent(
                                type: .standard(.providerEvent),
                                raw: .object([
                                    "event": .string("ping"),
                                    "beat": .number(Double(beat)),
                                ])
                            )
                        )
                    }
                    try await Task.sleep(for: heartbeatInterval)
                    continuation.yield(
                        StreamEvent(
                            type: .standard(.finish),
                            finishReason: response.finishReason,
                            usage: response.usage,
                            response: response
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

private actor TransportShutdownRecorder {
    private var count = 0

    func recordShutdown() {
        count += 1
    }

    func shutdownCount() -> Int {
        count
    }
}

private final class TrackingHTTPTransport: HTTPTransport, @unchecked Sendable {
    let recorder = TransportShutdownRecorder()

    func send(_ request: HTTPRequest, timeout: Duration?) async throws -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: HTTPHeaders(), body: [])
    }

    func openStream(_ request: HTTPRequest, timeout: Duration?) async throws -> HTTPStreamResponse {
        HTTPStreamResponse(statusCode: 200, headers: HTTPHeaders(), body: AsyncThrowingStream { continuation in
            continuation.finish()
        })
    }

    func shutdown() async throws {
        await recorder.recordShutdown()
    }
}

@Suite
final class ClientTests {
    @Test
    func testMiddlewareOrderOnionPattern() async throws {
        let recorder = OrderRecorder()
        let m1 = RecordingMiddleware(name: "A", recorder: recorder)
        let m2 = RecordingMiddleware(name: "B", recorder: recorder)

        let resp = Response(
            id: "r",
            model: "m",
            provider: "p",
            message: .assistant("ok"),
            finishReason: FinishReason(kind: .stop, raw: "stop"),
            usage: Usage(inputTokens: 1, outputTokens: 1)
        )

        let client = try Client(
            providers: ["p": StaticAdapter(name: "p", response: resp)],
            defaultProvider: "p",
            middleware: [m1, m2]
        )

        _ = try await client.complete(Request(model: "m", messages: [.user("hi")], provider: "p"))
        let events = await recorder.all()
        XCTAssertEqual(events, ["A.in", "B.in", "B.out", "A.out"])
    }

    @Test
    func testProviderRoutingAndDefaultProvider() async throws {
        let r1 = Response(
            id: "r1",
            model: "m",
            provider: "p1",
            message: .assistant("one"),
            finishReason: FinishReason(kind: .stop, raw: "stop"),
            usage: Usage(inputTokens: 1, outputTokens: 1)
        )
        let r2 = Response(
            id: "r2",
            model: "m",
            provider: "p2",
            message: .assistant("two"),
            finishReason: FinishReason(kind: .stop, raw: "stop"),
            usage: Usage(inputTokens: 1, outputTokens: 1)
        )

        let client = try Client(
            providers: ["p1": StaticAdapter(name: "p1", response: r1), "p2": StaticAdapter(name: "p2", response: r2)],
            defaultProvider: "p1"
        )

        let a = try await client.complete(Request(model: "m", messages: [.user("hi")], provider: nil))
        XCTAssertEqual(a.text, "one")

        let b = try await client.complete(Request(model: "m", messages: [.user("hi")], provider: "p2"))
        XCTAssertEqual(b.text, "two")
    }

    @Test
    func testConfigurationErrorWhenNoDefaultProvider() async {
        let client = try! Client(providers: [:], defaultProvider: nil)
        do {
            _ = try await client.complete(Request(model: "m", messages: [.user("hi")], provider: nil))
            XCTFail("Expected ConfigurationError")
        } catch is ConfigurationError {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @Test
    func testStreamTimeoutTreatsProviderEventsAsLiveness() async throws {
        let response = Response(
            id: "heartbeat",
            model: "m",
            provider: "p",
            message: .assistant("ok"),
            finishReason: FinishReason(kind: .stop, raw: "stop"),
            usage: Usage(inputTokens: 1, outputTokens: 1)
        )

        let client = try Client(
            providers: [
                "p": HeartbeatAdapter(
                    name: "p",
                    response: response,
                    heartbeatCount: 3,
                    heartbeatInterval: .milliseconds(400)
                )
            ],
            defaultProvider: "p"
        )

        let stream = try await client.stream(
            Request(
                model: "m",
                messages: [.user("hi")],
                provider: "p",
                timeout: .seconds(1)
            )
        )

        var providerEvents = 0
        var finish: Response?
        for try await event in stream {
            if event.type.rawValue == StreamEventType.providerEvent.rawValue {
                providerEvents += 1
            }
            if event.type.rawValue == StreamEventType.finish.rawValue {
                finish = event.response
            }
        }

        XCTAssertEqual(providerEvents, 3)
        XCTAssertEqual(finish?.text, "ok")
    }

    @Test
    func testDefaultHTTPTransportUsesPlatformAppropriateImplementation() {
        let transport = defaultHTTPTransport()
        #if os(Linux)
        XCTAssertTrue(transport is NIOHTTPTransport)
        #else
        XCTAssertTrue(transport is URLSessionHTTPTransport)
        #endif
    }

    @Test
    func testClientCloseShutsDownOwnedTransportOnce() async throws {
        let response = Response(
            id: "r",
            model: "m",
            provider: "p",
            message: .assistant("ok"),
            finishReason: FinishReason(kind: .stop, raw: "stop"),
            usage: Usage(inputTokens: 1, outputTokens: 1)
        )
        let transport = TrackingHTTPTransport()
        let client = try Client(
            providers: ["p": StaticAdapter(name: "p", response: response)],
            defaultProvider: "p",
            ownedTransport: transport
        )

        await client.close()
        await client.close()

        let shutdownCount = await transport.recorder.shutdownCount()
        XCTAssertEqual(shutdownCount, 1)
    }
}
