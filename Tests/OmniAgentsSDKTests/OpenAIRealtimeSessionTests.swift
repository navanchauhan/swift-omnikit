import Foundation
import Testing
import OmniAgentsSDK
import OmniAICore
import OmniHTTP

private final class StubRealtimeSDKSession: RealtimeWebSocketSession, @unchecked Sendable {
    private actor State {
        var sentTexts: [String] = []
        var closedCodes: [RealtimeWebSocketCloseCode?] = []
        func append(text: String) { sentTexts.append(text) }
        func append(code: RealtimeWebSocketCloseCode?) { closedCodes.append(code) }
        func snapshot() -> ([String], [RealtimeWebSocketCloseCode?]) { (sentTexts, closedCodes) }
    }

    private let state = State()
    private let stream: AsyncThrowingStream<RealtimeWebSocketMessage, Error>

    init(messages: [RealtimeWebSocketMessage], keepOpen: Bool = false) {
        self.stream = AsyncThrowingStream { continuation in
            for message in messages { continuation.yield(message) }
            if !keepOpen { continuation.finish() }
        }
    }

    func send(text: String, timeout: Duration?) async throws {
        let _ = timeout
        await state.append(text: text)
    }

    func send(binary: Data, timeout: Duration?) async throws {
        let _ = timeout
        Issue.record("binary send not expected")
    }

    func incomingMessages() -> AsyncThrowingStream<RealtimeWebSocketMessage, Error> { stream }

    func close(code: RealtimeWebSocketCloseCode?) async {
        await state.append(code: code)
    }

    func snapshot() async -> ([String], [RealtimeWebSocketCloseCode?]) { await state.snapshot() }
}

private final class StubRealtimeSDKTransport: RealtimeWebSocketTransport, @unchecked Sendable {
    let session: StubRealtimeSDKSession
    init(session: StubRealtimeSDKSession) { self.session = session }
    func connect(url: URL, headers: OmniHTTP.HTTPHeaders, timeout: Duration?) async throws -> any RealtimeWebSocketSession {
        let _ = url; let _ = headers; let _ = timeout
        return session
    }
}

struct OpenAIRealtimeSessionTests {
    private func parseSent(_ texts: [String]) throws -> [JSONValue] {
        try texts.map { try JSONValue.parse(Data($0.utf8)) }
    }

    @Test
    func runner_connects_and_sends_session_update_with_function_tools() async throws {
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) else { return }
        struct EchoArgs: Decodable, Sendable { let text: String }
        let agent = Agent<Void>(
            name: "assistant",
            instructions: .text("Help the user."),
            tools: [functionTool(name: "echo", description: "Echo text") { (_: ToolContext<Any>, args: EchoArgs) async throws in
                args.text
            }]
        )
        let sessionTransport = StubRealtimeSDKSession(messages: [], keepOpen: true)
        let client = OpenAIRealtimeClient(apiKey: "sk-test", transport: StubRealtimeSDKTransport(session: sessionTransport))
        let runner = OpenAIRealtimeRunner(startingAgent: agent, options: .init(model: "gpt-realtime-mini", voice: .alloy, inputAudioFormat: .pcm16k, outputAudioFormat: .pcm24k), client: client)

        _ = try await runner.run(context: ())
        let sent = try parseSent(await sessionTransport.snapshot().0)
        #expect(sent.count == 1)
        #expect(sent[0]["type"]?.stringValue == "session.update")
        #expect(sent[0]["session"]?["instructions"]?.stringValue == "Help the user.")
        #expect(sent[0]["session"]?["tools"]?.arrayValue?.first?["name"]?.stringValue == "echo")
    }

    @Test
    func session_audio_helpers_send_base64_events() async throws {
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) else { return }
        let agent = Agent<Void>(name: "assistant", instructions: .text("Help"))
        let transportSession = StubRealtimeSDKSession(messages: [], keepOpen: true)
        let client = OpenAIRealtimeClient(apiKey: "sk-test", transport: StubRealtimeSDKTransport(session: transportSession))
        let session = OpenAIRealtimeSession(agent: agent, context: (), client: client)
        try await session.connect()
        try await session.appendInputAudio(Data([1, 2, 3]))
        try await session.commitInputAudio()
        let sent = try parseSent(await transportSession.snapshot().0)
        #expect(sent[1]["type"]?.stringValue == "input_audio_buffer.append")
        #expect(sent[1]["audio"]?.stringValue == Data([1,2,3]).base64EncodedString())
        #expect(sent[2]["type"]?.stringValue == "input_audio_buffer.commit")
    }

    @Test
    func function_call_done_invokes_tool_and_sends_output_then_response_create() async throws {
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) else { return }
        struct EchoArgs: Decodable, Sendable { let text: String }
        let agent = Agent<Void>(
            name: "assistant",
            instructions: .text("Help"),
            tools: [functionTool(name: "echo", description: "Echo text") { (_: ToolContext<Any>, args: EchoArgs) async throws in
                ["echo": JSONValue.string(args.text)]
            }]
        )
        let functionCallEvent = try JSONSerialization.data(withJSONObject: [
            "type": "response.function_call_arguments.done",
            "call_id": "call_1",
            "name": "echo",
            "arguments": "{\"text\":\"hi\"}",
        ])
        let transportSession = StubRealtimeSDKSession(messages: [.text(String(decoding: functionCallEvent, as: UTF8.self))], keepOpen: true)
        let client = OpenAIRealtimeClient(apiKey: "sk-test", transport: StubRealtimeSDKTransport(session: transportSession))
        let session = OpenAIRealtimeSession(agent: agent, context: (), client: client)
        try await session.connect()
        try await Task.sleep(nanoseconds: 50_000_000)
        let sent = try parseSent(await transportSession.snapshot().0)
        #expect(sent.count == 3)
        #expect(sent[1]["type"]?.stringValue == "conversation.item.create")
        #expect(sent[2]["type"]?.stringValue == "response.create")
        await session.close()
    }

    @Test
    func handoff_function_call_updates_agent_and_reconfigures_session() async throws {
        guard #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) else { return }
        let secondary = Agent<Void>(name: "secondary", instructions: .text("Second agent"))
        let primary = Agent<Void>(
            name: "primary",
            instructions: .text("First agent"),
            handoffs: [handoff(secondary, toolName: "transfer_to_secondary", toolDescription: "handoff")]
        )
        let handoffEvent = try JSONSerialization.data(withJSONObject: [
            "type": "response.function_call_arguments.done",
            "call_id": "call_h1",
            "name": "transfer_to_secondary",
            "arguments": "{}",
        ])
        let transportSession = StubRealtimeSDKSession(messages: [.text(String(decoding: handoffEvent, as: UTF8.self))], keepOpen: true)
        let client = OpenAIRealtimeClient(apiKey: "sk-test", transport: StubRealtimeSDKTransport(session: transportSession))
        let session = OpenAIRealtimeSession(agent: primary, context: (), client: client)
        try await session.connect()
        try await Task.sleep(nanoseconds: 50_000_000)
        let sent = try parseSent(await transportSession.snapshot().0)
        #expect(sent.count == 4)
        #expect(sent[0]["session"]?["instructions"]?.stringValue == "First agent")
        #expect(sent[1]["session"]?["instructions"]?.stringValue == "Second agent")
        #expect(sent[2]["type"]?.stringValue == "conversation.item.create")
        #expect(sent[3]["type"]?.stringValue == "response.create")
        let snapshot = await session.snapshot()
        #expect(snapshot.currentAgentName == "secondary")
        await session.close()
    }
}
