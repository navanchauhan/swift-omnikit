import Foundation
import Testing
@testable import OmniAIAttractor
@testable import OmniAICore

private final class EmptyAssistantTurnAdapter: ProviderAdapter, @unchecked Sendable {
    let name: String

    init(name: String = "anthropic") {
        self.name = name
    }

    func complete(request: Request) async throws -> Response {
        Response(
            id: "resp_empty",
            model: request.model,
            provider: request.provider ?? name,
            message: Message(role: .assistant, content: []),
            finishReason: .stop,
            usage: Usage(inputTokens: 1, outputTokens: 0)
        )
    }

    func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let response = try await complete(request: request)
        return AsyncThrowingStream { continuation in
            continuation.yield(StreamEvent(type: .standard(.streamStart)))
            continuation.yield(
                StreamEvent(
                    type: .standard(.finish),
                    finishReason: response.finishReason,
                    usage: response.usage,
                    response: response
                )
            )
            continuation.finish()
        }
    }
}

private final class ToolThenTimeoutAdapter: ProviderAdapter, @unchecked Sendable {
    let name: String
    private let filePath: String
    private let lock = NSLock()
    private var requestCount = 0

    init(filePath: String, name: String = "anthropic") {
        self.filePath = filePath
        self.name = name
    }

    func complete(request: Request) async throws -> Response {
        throw RequestTimeoutError(message: "complete() should not be used in ToolThenTimeoutAdapter")
    }

    func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let currentRequest = nextRequestNumber()
        if currentRequest == 1 {
            let response = Response(
                id: "resp_tool_then_timeout",
                model: request.model,
                provider: request.provider ?? name,
                message: Message(
                    role: .assistant,
                    content: [
                        .text("I am reviewing the implementation spec before writing the verdict."),
                        .toolCall(
                            ToolCall(
                                id: "call_read_spec",
                                name: "Read",
                                arguments: ["file_path": .string(filePath)],
                                rawArguments: nil
                            )
                        ),
                    ]
                ),
                finishReason: .toolCalls,
                usage: Usage(inputTokens: 1, outputTokens: 8)
            )

            return AsyncThrowingStream { continuation in
                continuation.yield(StreamEvent(type: .standard(.streamStart)))
                continuation.yield(
                    StreamEvent(
                        type: .standard(.finish),
                        finishReason: response.finishReason,
                        usage: response.usage,
                        response: response
                    )
                )
                continuation.finish()
            }
        }

        return AsyncThrowingStream { continuation in
            continuation.yield(StreamEvent(type: .standard(.streamStart)))
            continuation.finish(throwing: RequestTimeoutError(message: "LLM inactivity timeout after 90s"))
        }
    }

    private func nextRequestNumber() -> Int {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        return requestCount
    }
}

private final class TextOnlyNoJSONAdapter: ProviderAdapter, @unchecked Sendable {
    let name: String

    init(name: String = "openai") {
        self.name = name
    }

    func complete(request: Request) async throws -> Response {
        Response(
            id: "resp_text_only_no_json",
            model: request.model,
            provider: request.provider ?? name,
            message: Message(role: .assistant, content: [.text("i checked the host and i am about to write the artifact now")]),
            finishReason: .stop,
            usage: Usage(inputTokens: 1, outputTokens: 12)
        )
    }

    func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let response = try await complete(request: request)
        return AsyncThrowingStream { continuation in
            continuation.yield(StreamEvent(type: .standard(.streamStart)))
            continuation.yield(
                StreamEvent(
                    type: .standard(.finish),
                    finishReason: response.finishReason,
                    usage: response.usage,
                    response: response
                )
            )
            continuation.finish()
        }
    }
}

@Suite
struct CodingAgentBackendTests {
    @Test
    func emptyAssistantTurnReturnsRetryInsteadOfPoisoningFollowup() async throws {
        let adapter = EmptyAssistantTurnAdapter()
        let client = try Client(providers: ["anthropic": adapter], defaultProvider: "anthropic")

        let workingDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CodingAgentBackendTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let backend = CodingAgentBackend(client: client, workingDirectory: workingDirectory.path)
        let result = try await backend.run(
            prompt: "Produce a merge verdict.",
            model: "claude-opus-4-6",
            provider: "anthropic",
            reasoningEffort: "high",
            context: PipelineContext(["_graph_goal": "Regression test"])
        )

        #expect(result.status == .retry)
        #expect(result.notes.localizedStandardContains("no assistant text and no tool calls"))
    }

    @Test
    func sessionTimeoutAfterSubstantiveWorkReturnsRetryInsteadOfFollowup() async throws {
        let workingDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CodingAgentBackendTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let specFile = workingDirectory.appendingPathComponent("implementation-spec.md")
        try "spec placeholder".write(to: specFile, atomically: true, encoding: .utf8)

        let adapter = ToolThenTimeoutAdapter(filePath: specFile.path)
        let client = try Client(providers: ["anthropic": adapter], defaultProvider: "anthropic")

        let backend = CodingAgentBackend(client: client, workingDirectory: workingDirectory.path)
        let result = try await backend.run(
            prompt: "Produce a merge verdict.",
            model: "claude-opus-4-6",
            provider: "anthropic",
            reasoningEffort: "high",
            context: PipelineContext(["_graph_goal": "Regression test"])
        )

        #expect(result.status == .retry)
        #expect(result.notes.localizedStandardContains("retryable llm error"))
        #expect(result.notes.localizedStandardContains("requesttimeouterror"))
    }

    @Test
    func missingStructuredStatusReturnsRetryInsteadOfPartialSuccess() async throws {
        let adapter = TextOnlyNoJSONAdapter()
        let client = try Client(providers: ["openai": adapter], defaultProvider: "openai")

        let workingDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CodingAgentBackendTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let backend = CodingAgentBackend(client: client, workingDirectory: workingDirectory.path)
        let result = try await backend.run(
            prompt: "prove the worker ran hostname and wrote the artifact",
            model: "gpt-5.4",
            provider: "openai",
            reasoningEffort: "high",
            context: PipelineContext(["_graph_goal": "Regression test"])
        )

        #expect(result.status == .retry)
        #expect(result.notes.localizedStandardContains("no structured status block"))
        #expect(result.notes.localizedStandardContains("retrying stage"))
    }

    @Test
    func storageRootUsesTheAgentStateRootWhenPresent() throws {
        let workingDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CodingAgentBackendTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let stateRoot = workingDirectory.appendingPathComponent("worker-state", isDirectory: true)
        let previous = ProcessInfo.processInfo.environment["THE_AGENT_STATE_ROOT"]
        setenv("THE_AGENT_STATE_ROOT", stateRoot.path, 1)
        defer {
            if let previous {
                setenv("THE_AGENT_STATE_ROOT", previous, 1)
            } else {
                unsetenv("THE_AGENT_STATE_ROOT")
            }
        }

        let backend = CodingAgentBackend(client: nil, workingDirectory: workingDirectory.path)
        let resolved = backend.resolvedStorageRoot()

        #expect(resolved.path == stateRoot.appendingPathComponent("attractor-agent-state", isDirectory: true).path)
    }
}
