import Foundation
import Testing
import OmniACP
import OmniACPModel
import OmniAIAttractor
import OmniAgentMesh
import OmniMCP
@testable import TheAgentWorkerKit

private actor ACPRecordedConfigs {
    private(set) var values: [ACPExecutionConfiguration] = []

    func append(_ value: ACPExecutionConfiguration) {
        values.append(value)
    }
}

private actor ACPAgentTasks {
    private var tasks: [Task<Void, Never>] = []

    func add(_ task: Task<Void, Never>) {
        tasks.append(task)
    }

    func cancelAll() {
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
    }
}

private actor ACPProgressRecorder {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private struct ACPRecordingTransportProvider: ACPTransportProvider {
    let recorder: ACPRecordedConfigs
    let taskStore: ACPAgentTasks

    func makeTransport(configuration: ACPExecutionConfiguration) async throws -> any Transport {
        await recorder.append(configuration)
        let (clientTransport, agentTransport) = await InMemoryTransport.createConnectedPair()
        try await clientTransport.connect()
        try await agentTransport.connect()
        let task = startMockAgent(on: agentTransport)
        await taskStore.add(task)
        return clientTransport
    }

    private func startMockAgent(on transport: InMemoryTransport) -> Task<Void, Never> {
        Task {
            let encoder = JSONEncoder()
            let stream = transport.receive()
            do {
                for try await data in stream {
                    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    let method = object?["method"] as? String
                    let hasID = object?.keys.contains("id") == true
                    guard let method, hasID else {
                        continue
                    }

                    switch method {
                    case Initialize.name:
                        let request = try JSONDecoder().decode(Request<Initialize>.self, from: data)
                        let response = Initialize.response(
                            id: request.id,
                            result: .init(
                                protocolVersion: 1,
                                agentInfo: .init(name: "WorkerACPAgent", version: "1.0.0"),
                                agentCapabilities: .init(loadSession: true, mcpCapabilities: .init(), promptCapabilities: .init())
                            )
                        )
                        try await transport.send(encoder.encode(response))
                    case SessionNew.name:
                        let request = try JSONDecoder().decode(Request<SessionNew>.self, from: data)
                        let response = SessionNew.response(id: request.id, result: .init(sessionID: "worker_session"))
                        try await transport.send(encoder.encode(response))
                    case SessionPrompt.name:
                        let request = try JSONDecoder().decode(Request<SessionPrompt>.self, from: data)
                        let notification = Message<SessionUpdateNotification>(
                            method: SessionUpdateNotification.name,
                            params: .init(
                                sessionID: request.params.sessionID,
                                update: .agentMessageChunk(
                                    .init(
                                        content: .init(
                                            text: """
                                            Worker ACP response.

                                            ```json
                                            {"outcome":"success","context_updates":{"worker_acp":"true"},"notes":"worker-session"}
                                            ```
                                            """
                                        )
                                    )
                                )
                            )
                        )
                        try await transport.send(encoder.encode(notification))
                        try await transport.send(encoder.encode(SessionPrompt.response(id: request.id, result: .init(stopReason: .endTurn))))
                    case SessionCancel.name:
                        let request = try JSONDecoder().decode(Request<SessionCancel>.self, from: data)
                        try await transport.send(encoder.encode(SessionCancel.response(id: request.id)))
                    case SessionSetMode.name:
                        let request = try JSONDecoder().decode(Request<SessionSetMode>.self, from: data)
                        try await transport.send(encoder.encode(SessionSetMode.response(id: request.id)))
                    default:
                        break
                    }
                }
            } catch {
            }
        }
    }
}

@Suite
struct ACPWorkerIntegrationTests {
    @Test
    func workerMCPServerAndACPExecutorShareRegistryAcrossProfiles() async throws {
        let registry = try ToolRegistry(
            tools: [
                WorkerTool(
                    name: "echo",
                    description: "Echo input",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "message": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("message")]),
                        "additionalProperties": .bool(false),
                    ])
                ) { arguments in
                    arguments
                },
            ]
        )
        let mcpServer = WorkerMCPServer(name: "worker-tools", registry: registry)
        let tools = try await mcpServer.listTools()
        let callResult = try await mcpServer.callTool(
            name: "echo",
            arguments: .object(["message": .string("hello")])
        )

        #expect(tools.map(\.name) == ["echo"])
        #expect(callResult.content.objectValue?["message"] == .string("hello"))

        let recorder = ACPRecordedConfigs()
        let taskStore = ACPAgentTasks()
        defer {
            Task { await taskStore.cancelAll() }
        }

        let session = ACPWorkerSession(
            toolRegistry: registry,
            transportProvider: ACPRecordingTransportProvider(recorder: recorder, taskStore: taskStore),
            delegateProvider: DefaultACPClientDelegateProvider(permissionStrategy: .autoApprove)
        )
        let executor = ACPExecutor(session: session)
        let task = TaskRecord(
            taskID: "worker-acp-task",
            rootSessionID: "root",
            capabilityRequirements: ["acp"],
            historyProjection: HistoryProjection(
                taskBrief: "Summarize the delegated task",
                summaries: ["Parent summary"],
                parentExcerpts: ["user: please summarize this"]
            )
        )

        let results = try await executor.execute(
            task: task,
            profiles: [
                .codex(configuration: .init(agentPath: "codex-agent")),
                .claude(configuration: .init(agentPath: "claude-agent")),
                .gemini(configuration: .init(agentPath: "gemini-agent")),
            ],
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        let configs = await recorder.values

        #expect(results.map(\.profileID) == ["codex", "claude", "gemini"])
        #expect(results.allSatisfy { $0.contextUpdates["worker_acp"] == "true" })
        #expect(configs.count == 3)
        #expect(configs.map(\.agentPath) == ["codex-agent", "claude-agent", "gemini-agent"])
        #expect(configs.allSatisfy { $0.mcpServers.count == 1 })
        #expect(Set(configs.flatMap(\.mcpServers).map(\.name)) == Set(["codex-worker-tools", "claude-worker-tools", "gemini-worker-tools"]))
    }

    @Test
    func workerExecutorFactoryBuildsACPExecutorForDaemonRuntime() async throws {
        let recorder = ACPRecordedConfigs()
        let taskStore = ACPAgentTasks()
        let progressRecorder = ACPProgressRecorder()
        defer {
            Task { await taskStore.cancelAll() }
        }

        let executionMode = WorkerExecutionMode.acp(
            ACPWorkerRuntimeOptions(
                profile: .codex,
                model: "gpt-5.3-codex-test",
                reasoningEffort: "medium",
                agentPath: "codex-agent",
                agentArguments: ["--stdio"],
                workingDirectory: "/tmp/worker-acp",
                modeID: "build",
                requestTimeout: .seconds(45)
            )
        )

        let executor = WorkerExecutorFactory.makeExecutor(
            mode: executionMode,
            transportProvider: ACPRecordingTransportProvider(recorder: recorder, taskStore: taskStore),
            delegateProvider: DefaultACPClientDelegateProvider(permissionStrategy: .autoApprove)
        )

        let task = TaskRecord(
            taskID: "worker-daemon-acp-task",
            rootSessionID: "root",
            capabilityRequirements: ["linux", "acp"],
            historyProjection: HistoryProjection(taskBrief: "Run the delegated ACP task")
        )

        let result = try await executor.execute(task: task) { summary, _ in
            await progressRecorder.append(summary)
        }
        let configs = await recorder.values
        let progress = await progressRecorder.values
        let capabilities = WorkerExecutorFactory.augmentCapabilities(["linux"], mode: executionMode)
        let metadata = WorkerExecutorFactory.metadata(for: executionMode)

        #expect(progress == ["Launching codex ACP session", "Received codex ACP result preview"])
        #expect(result.summary == #"codex ACP task completed: Worker ACP response. ```json {"outcome":"success","context_updates":{"worker_acp":"true"},"notes":"worker-session"} ```"#)
        #expect(result.artifacts.map(\.name) == ["codex-response.md", "codex-notes.txt"])
        #expect(result.metadata["profile_id"] == "codex")
        #expect(result.metadata["response_preview"] == #"Worker ACP response. ```json {"outcome":"success","context_updates":{"worker_acp":"true"},"notes":"worker-session"} ```"#)
        #expect(result.metadata["worker_acp"] == "true")
        #expect(configs.count == 1)
        #expect(configs.first?.agentPath == "codex-agent")
        #expect(configs.first?.agentArguments == ["--stdio"])
        #expect(configs.first?.workingDirectory == "/tmp/worker-acp")
        #expect(configs.first?.modeID == "build")
        #expect(capabilities == ["acp", "acp-codex", "linux"])
        #expect(metadata["execution_mode"] == "acp")
        #expect(metadata["acp_profile"] == "codex")
        #expect(metadata["acp_model"] == "gpt-5.3-codex-test")
        #expect(WorkerExecutorFactory.startupDescription(for: executionMode) == "using codex ACP executor (gpt-5.3-codex-test)")
    }
}
