import Foundation
import Testing
import OmniAgentsSDK
import OmniAICore

private actor _ComputerState {
    var createCount = 0
    var disposeCount = 0
    func created() { createCount += 1 }
    func disposed() { disposeCount += 1 }
}

private struct DummyComputer: AsyncComputer {
    var environment: Environment { .browser }
    var dimensions: (Int, Int) { (1, 1) }
    func screenshot() async throws -> String { "img" }
    func click(x: Int, y: Int, button: Button) async throws {}
    func doubleClick(x: Int, y: Int) async throws {}
    func scroll(x: Int, y: Int, scrollX: Int, scrollY: Int) async throws {}
    func type(_ text: String) async throws {}
    func wait() async throws {}
    func move(x: Int, y: Int) async throws {}
    func keypress(_ keys: [String]) async throws {}
    func drag(_ path: [(Int, Int)]) async throws {}
}

struct SurfaceParityTests {
    @Test
    func snake_case_config_and_session_helpers_exist_and_work() throws {
        set_default_openai_key("sk-test", use_for_tracing: true)
        set_default_openai_api(.responses)
        set_default_openai_responses_transport(.http)
        set_tracing_export_api_key("trace-key")
        set_tracing_disabled(false)

        let snapshot = getGlobalConfig()
        #expect(snapshot.defaultOpenAIKey == "sk-test")
        #expect(snapshot.defaultOpenAIAPI == .responses)
        #expect(snapshot.defaultOpenAIResponsesTransport == .http)
        #expect(snapshot.tracingExportAPIKey == "trace-key")

        let session = OpenAIResponsesCompactionSession(sessionID: "s")
        #expect(is_openai_responses_compaction_aware_session(session))
    }

    @Test
    func snake_case_websocket_helper_exists() {
        let session = responses_websocket_session()
        #expect(session.provider.useResponsesWebSocket)
    }

    @Test
    func agent_tool_invocation_is_exposed_for_tool_context_results() {
        let ctx = ToolContext<Void>(
            context: (),
            toolName: "delegate",
            toolCallID: "call_123",
            toolArguments: "{\"x\":1}",
            agent: nil,
            runConfig: nil
        )
        let result = RunResult<Void>(
            input: .string("hello"),
            newItems: [],
            rawResponses: [],
            finalOutput: "ok",
            inputGuardrailResults: [],
            outputGuardrailResults: [],
            toolInputGuardrailResults: [],
            toolOutputGuardrailResults: [],
            contextWrapper: ctx,
            lastAgent: "agent"
        )

        #expect(result.agent_tool_invocation == AgentToolInvocation(toolName: "delegate", toolCallID: "call_123", toolArguments: "{\"x\":1}"))
    }

    @Test
    func resolve_and_dispose_computer_helpers_manage_provider_lifecycle() async throws {
        let state = _ComputerState()
        let provider = ComputerProvider(
            create: {
                await state.created()
                return DummyComputer()
            },
            dispose: { _ in
                await state.disposed()
            }
        )
        let tool = ComputerTool(computer: .provider(provider))
        let context = RunContextWrapper<Any>(context: ())

        _ = try await resolve_computer(tool: tool, run_context: context)
        _ = try await resolveComputer(tool: tool, runContext: context)

        #expect(await state.createCount == 1)
        await dispose_resolved_computers(run_context: context)
        #expect(await state.disposeCount == 1)
    }

    @Test
    func tracing_helper_exports_create_expected_span_kinds() {
        #expect(!gen_trace_id().isEmpty)
        #expect(!gen_span_id().isEmpty)

        #expect(agent_span(name: "a").data?.kind == "agent")
        #expect(custom_span(name: "c").data?.kind == "custom")
        #expect(function_span(name: "f").data?.kind == "function")
        #expect(generation_span().data?.kind == "generation")
        #expect(guardrail_span(name: "g").data?.kind == "guardrail")
        #expect(handoff_span().data?.kind == "handoff")
        #expect(mcp_tools_span().data?.kind == "mcp_list_tools")
        #expect(speech_span().data?.kind == "speech")
        #expect(speech_group_span().data?.kind == "speech_group")
        #expect(transcription_span().data?.kind == "transcription")
    }

    @Test
    func tool_output_dict_aliases_are_usable_json_dictionaries() {
        let text: ToolOutputTextDict = ["type": .string("text"), "text": .string("hello")]
        let image: ToolOutputImageDict = ["type": .string("image"), "image_url": .string("https://example.com/image.png")]
        let file: ToolOutputFileContentDict = ["type": .string("file"), "file_id": .string("file_123")]
        #expect(text["type"] == .string("text"))
        #expect(image["type"] == .string("image"))
        #expect(file["type"] == .string("file"))
    }
}
