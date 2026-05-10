import Foundation
import Testing
import OmniAICore
import OmniAIAgent
import OmniAgentMesh
import TheAgentWorkerKit
@testable import TheAgentControlPlaneKit

private actor RootOrchestratorTestAdapterState {
    private var responses: [Response]
    private var requests: [Request] = []
    private var index = 0

    init(responses: [Response]) {
        self.responses = responses
    }

    func nextResponse(for request: Request) -> Response {
        requests.append(request)
        let currentIndex = index
        index += 1
        if currentIndex < responses.count {
            return responses[currentIndex]
        }
        guard let last = responses.last else {
            preconditionFailure("RootOrchestratorTestAdapterState requires at least one response")
        }
        return last
    }

    func requestCount() -> Int {
        requests.count
    }
}

private final class RootOrchestratorTestAdapter: ProviderAdapter, @unchecked Sendable {
    let name = "openai"
    let state: RootOrchestratorTestAdapterState

    init(responses: [Response]) {
        self.state = RootOrchestratorTestAdapterState(responses: responses)
    }

    func complete(request: Request) async throws -> Response {
        await state.nextResponse(for: request)
    }

    func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let response = await state.nextResponse(for: request)
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

private func rootOrchestratorResponse(
    provider: String = "openai",
    model: String = "gpt-test",
    text: String = "",
    toolCalls: [ToolCall] = [],
    finishReason: String = "stop"
) -> Response {
    var parts: [ContentPart] = []
    if !text.isEmpty {
        parts.append(.text(text))
    }
    for call in toolCalls {
        parts.append(.toolCall(call))
    }
    return Response(
        id: "resp_\(UUID().uuidString)",
        model: model,
        provider: provider,
        message: Message(role: .assistant, content: parts),
        finishReason: FinishReason(
            kind: FinishReason.Kind(rawValue: finishReason) ?? .other,
            raw: finishReason
        ),
        usage: Usage(inputTokens: 1, outputTokens: 1),
        raw: nil,
        warnings: [],
        rateLimit: nil
    )
}

@Suite
struct RootOrchestratorTests {
    @Test
    func runtimeClockSectionIncludesHumanAndISOTimestamps() {
        let contextBuffer = RootPromptContextBuffer()
        let profile = RootOrchestratorProfile(
            wrapping: OpenAIProfile(model: "gpt-test"),
            contextBuffer: contextBuffer,
            additionalTools: []
        )
        let now = Date(timeIntervalSince1970: 1_762_260_245)

        let section = profile.buildRuntimeClockSection(now: now)

        #expect(section.contains("# Runtime Clock Context"))
        #expect(section.contains("Current local date/time:"))
        #expect(section.contains("Current timestamp (ISO 8601):"))
        #expect(section.contains("2025-11-04T12:44:05"))
    }

    @Test
    func openAIRootDefaultsToGPT54AndAdvertisesDirectCodingTools() async throws {
        let contextBuffer = RootPromptContextBuffer()
        let profile = RootOrchestratorProfile(
            wrapping: OpenAIProfile(
                model: RootAgentProvider.openai.defaultModel,
                includeWebSearch: true
            ),
            contextBuffer: contextBuffer,
            additionalTools: [],
            enableNativeWebSearch: true,
            enableSubagentTools: true
        )
        let environment = LocalExecutionEnvironment(workingDir: FileManager.default.currentDirectoryPath)
        try await environment.initialize()

        let prompt = profile.buildSystemPrompt(
            environment: environment,
            projectDocs: nil,
            userInstructions: nil,
            gitContext: nil
        )

        #expect(RootAgentProvider.openai.defaultModel == "gpt-5.4")
        #expect(profile.toolRegistry.names().contains("exec_command"))
        #expect(profile.toolRegistry.names().contains("write_stdin"))
        #expect(prompt.localizedStandardContains("exec_command"))
        #expect(prompt.localizedStandardContains("write_stdin"))
        #expect(prompt.localizedStandardContains("native web research"))
        #expect(prompt.localizedStandardContains("spawn_agent"))
        #expect(prompt.localizedStandardContains("do not claim you lack tool access"))
        #expect(prompt.localizedStandardContains("only user-facing agent persona"))
        #expect(prompt.localizedStandardContains("workers and subagents are not user-facing"))
        #expect(prompt.localizedStandardContains("a little sarcastic"))
        #expect(prompt.localizedStandardContains("avoid corporate filler"))
        #expect(prompt.localizedStandardContains("all lowercase"))
        #expect(prompt.localizedStandardContains("no emojis"))
        #expect(prompt.localizedStandardContains("do not end normal user-facing sentences with periods"))
        #expect(prompt.localizedStandardContains("default to plain text"))
        #expect(prompt.localizedStandardContains("use markdown only when structure materially helps"))
        #expect(prompt.localizedStandardContains("try not to use bullet lists or numbered lists"))
        #expect(prompt.localizedStandardContains("exact identifiers and field names"))
        #expect(prompt.localizedStandardContains("retry the same search or action at most three times"))
        #expect(prompt.localizedStandardContains("use the smallest tool that can complete the task"))
        #expect(prompt.localizedStandardContains("prefer direct tool calls for simple work"))
        #expect(prompt.localizedStandardContains("runtime clock context"))
        #expect(prompt.localizedStandardContains("current local date/time"))
        #expect(prompt.localizedStandardContains("current timestamp (iso 8601)"))
        #expect(prompt.localizedStandardContains("when the user asks what time or date it is right now"))
    }

    @Test
    func deliveryMetadataSerializerIncludesRolloutStateHealthAndSummary() {
        let serialized = RootAgentToolbox.testingSerializeDeliveryMetadata(
            [
                "delivery_mode": "deployable",
                "delivery_service": "the-agent",
                "deploy_target": "canary",
                "release_bundle_id": "bundle-1",
                "release_id": "release-1",
                "deployment_state": "live",
                "health_status": "healthy",
                "delivery_summary": "deployed cleanly",
                "release_generation": "2",
                "rollback_release_id": "release-0",
            ]
        )

        #expect(serialized["mode"] as? String == "deployable")
        #expect(serialized["service"] as? String == "the-agent")
        #expect(serialized["target_environment"] as? String == "canary")
        #expect(serialized["release_bundle_id"] as? String == "bundle-1")
        #expect(serialized["release_id"] as? String == "release-1")
        #expect(serialized["deployment_state"] as? String == "live")
        #expect(serialized["health_status"] as? String == "healthy")
        #expect(serialized["delivery_summary"] as? String == "deployed cleanly")
        #expect(serialized["release_generation"] as? String == "2")
        #expect(serialized["rollback_release_id"] as? String == "release-0")
    }

    @Test
    func rootRuntimeDefaultsLLMInactivityTimeoutTo180Seconds() {
        let config = RootAgentRuntimeOptions().effectiveSessionConfig()

        #expect(config.llmInactivityTimeoutSeconds == 180)
    }

    @Test
    func rootRuntimePreservesExplicitLLMInactivityTimeout() {
        let config = RootAgentRuntimeOptions(
            sessionConfig: SessionConfig(llmInactivityTimeoutSeconds: 42)
        ).effectiveSessionConfig()

        #expect(config.llmInactivityTimeoutSeconds == 42)
    }

    @Test
    func rootRuntimeYoloEnablesSubagentsAndNativeWebSearch() async throws {
        let stateRoot = try makeStateRoot(prefix: "root-yolo-runtime")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let rootServer = RootAgentServer(
            sessionID: "root",
            conversationStore: conversationStore,
            jobStore: jobStore,
            hotWindowLimit: 4,
            notificationPolicy: NotificationPolicy(interruptThreshold: .important),
            scheduler: RootScheduler(jobStore: jobStore)
        )
        let adapter = RootOrchestratorTestAdapter(
            responses: [
                rootOrchestratorResponse(text: "ready"),
            ]
        )
        let client = try Client(
            providers: ["openai": adapter],
            defaultProvider: "openai"
        )

        let runtime = try await RootAgentRuntime.make(
            server: rootServer,
            stateRoot: stateRoot,
            options: RootAgentRuntimeOptions(
                provider: .openai,
                model: "gpt-5.4",
                workingDirectory: stateRoot.rootDirectory.path(),
                yoloMode: true
            ),
            client: client
        )

        let toolNames = runtime.profile.toolRegistry.names()
        let sessionConfig = await runtime.session.config
        let providerOptions = runtime.profile.providerOptions()
        let openAIOptions = providerOptions?["openai"]?.objectValue

        #expect(toolNames.contains("spawn_agent"))
        #expect(toolNames.contains("send_input"))
        #expect(toolNames.contains("wait"))
        #expect(toolNames.contains("close_agent"))
        #expect(sessionConfig.reasoningEffort == "high")
        #expect(sessionConfig.parallelToolCalls == true)
        #expect(sessionConfig.maxSubagentDepth >= 3)
        #expect(openAIOptions?[OpenAIProviderOptionKeys.includeNativeWebSearch]?.boolValue == true)
        #expect(openAIOptions?[OpenAIProviderOptionKeys.webSearchExternalWebAccess]?.boolValue == true)

        await runtime.close()
    }

    @Test
    func rootRuntimeUsesSessionLoopToDelegateWaitAndResolveNotifications() async throws {
        let stateRoot = try makeStateRoot(prefix: "root-orchestrator")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let scheduler = RootScheduler(jobStore: jobStore)
        let rootServer = RootAgentServer(
            sessionID: "root",
            conversationStore: conversationStore,
            jobStore: jobStore,
            hotWindowLimit: 4,
            notificationPolicy: NotificationPolicy(interruptThreshold: .important),
            scheduler: scheduler
        )

        let worker = WorkerDaemon(
            displayName: "local-orchestrated-worker",
            capabilities: WorkerCapabilities(["macOS", "swift"]),
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: LocalTaskExecutor { task, reportProgress in
                try await reportProgress("Worker started task", ["task_id": task.taskID])
                return LocalTaskExecutionResult(summary: "Worker finished delegated task")
            },
            leaseDuration: 5
        )
        try await rootServer.registerLocalWorker(worker, at: Date())

        let adapter = RootOrchestratorTestAdapter(
            responses: [
                rootOrchestratorResponse(
                    toolCalls: [
                        ToolCall(
                            id: "call-list-workers",
                            name: "list_workers",
                            arguments: [:],
                            rawArguments: nil
                        ),
                    ],
                    finishReason: "tool_calls"
                ),
                rootOrchestratorResponse(
                    toolCalls: [
                        ToolCall(
                            id: "call-delegate",
                            name: "delegate_task",
                            arguments: [
                                "brief": .string("Run the delegated task"),
                                "capability_requirements": .array([.string("macOS")]),
                                "expected_outputs": .array([.string("status-note")]),
                            ],
                            rawArguments: nil
                        ),
                    ],
                    finishReason: "tool_calls"
                ),
                rootOrchestratorResponse(
                    toolCalls: [
                        ToolCall(
                            id: "call-wait",
                            name: "wait_for_task",
                            arguments: [
                                "timeout_seconds": .number(5),
                            ],
                            rawArguments: nil
                        ),
                    ],
                    finishReason: "tool_calls"
                ),
                rootOrchestratorResponse(
                    toolCalls: [
                        ToolCall(
                            id: "call-list-notifications",
                            name: "list_notifications",
                            arguments: [:],
                            rawArguments: nil
                        ),
                    ],
                    finishReason: "tool_calls"
                ),
                rootOrchestratorResponse(
                    toolCalls: [
                        ToolCall(
                            id: "call-resolve-notification",
                            name: "resolve_notification",
                            arguments: [:],
                            rawArguments: nil
                        ),
                    ],
                    finishReason: "tool_calls"
                ),
                rootOrchestratorResponse(
                    text: "Delegated task completed and the notification was resolved."
                ),
            ]
        )
        let client = try Client(
            providers: ["openai": adapter],
            defaultProvider: "openai"
        )

        let runtime = try await RootAgentRuntime.make(
            server: rootServer,
            stateRoot: stateRoot,
            options: RootAgentRuntimeOptions(
                provider: .openai,
                model: "gpt-test",
                workingDirectory: stateRoot.rootDirectory.path()
            ),
            client: client
        )

        let result = try await runtime.submitUserText("Use a worker if that is the right execution path.")

        #expect(result.assistantText == "Delegated task completed and the notification was resolved.")
        #expect(result.snapshot.unresolvedNotifications.isEmpty)

        let tasks = try await rootServer.listTasks()
        #expect(tasks.count == 1)
        #expect(tasks.first?.status == .completed)
        #expect(tasks.first?.assignedAgentID == worker.workerID)

        if let taskID = tasks.first?.taskID {
            let events = try await jobStore.events(taskID: taskID, afterSequence: nil)
            let progressEvents = events.filter { $0.kind == .progress }
            #expect(events.map(\.kind) == [.submitted, .assigned, .started, .progress, .progress, .completed])
            #expect(progressEvents.contains { $0.summary?.localizedStandardContains("task started") == true })
            #expect(progressEvents.contains { $0.summary == "Worker started task" })
        } else {
            Issue.record("Expected one task to be created by delegate_task.")
        }

        let snapshot = try await rootServer.restoreState()
        #expect(snapshot.hotContext.contains { item in
            item.role == .assistant && item.content == result.assistantText
        })
        #expect(snapshot.unresolvedNotifications.isEmpty)
        #expect(await adapter.state.requestCount() == 6)

        await runtime.close()
    }

    private func makeStateRoot(prefix: String) throws -> AgentFabricStateRoot {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateRoot = AgentFabricStateRoot(rootDirectory: rootDirectory)
        try stateRoot.prepare()
        return stateRoot
    }
}
