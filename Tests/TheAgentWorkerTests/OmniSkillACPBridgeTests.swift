import Foundation
import Testing
import OmniACP
import OmniACPModel
import OmniAIAttractor
import OmniAgentMesh
import OmniMCP
import OmniSkills
@testable import TheAgentWorkerKit

private actor ACPBridgeRecorder {
    private var configurations: [ACPExecutionConfiguration] = []
    private var prompts: [String] = []

    func append(configuration: ACPExecutionConfiguration) {
        configurations.append(configuration)
    }

    func append(promptBlocks: [ContentBlock]) {
        prompts.append(Self.render(promptBlocks: promptBlocks))
    }

    nonisolated private static func render(promptBlocks: [ContentBlock]) -> String {
        promptBlocks.map { block in
            switch block {
            case .text(let value):
                value.text
            case .image:
                "[image]"
            case .audio:
                "[audio]"
            case .resource(let value):
                value.resource.text ?? "[resource \(value.resource.uri)]"
            case .resourceLink(let value):
                value.uri
            }
        }.joined(separator: "\n")
    }

    func append(prompt: String) {
        prompts.append(prompt)
    }

    func firstConfiguration() -> ACPExecutionConfiguration? {
        configurations.first
    }

    func firstPrompt() -> String? {
        prompts.first
    }
}

private actor ACPBridgeAgentTasks {
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

private struct ACPBridgeTransportProvider: ACPTransportProvider {
    let recorder: ACPBridgeRecorder
    let taskStore: ACPBridgeAgentTasks

    func makeTransport(configuration: ACPExecutionConfiguration) async throws -> any Transport {
        await recorder.append(configuration: configuration)
        let (clientTransport, agentTransport) = await InMemoryTransport.createConnectedPair()
        try await clientTransport.connect()
        try await agentTransport.connect()
        let task = Task {
            await runMockAgent(on: agentTransport)
        }
        await taskStore.add(task)
        return clientTransport
    }

    private func runMockAgent(on transport: InMemoryTransport) async {
        let encoder = JSONEncoder()
        do {
            for try await data in transport.receive() {
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                guard let method = object?["method"] as? String,
                      object?.keys.contains("id") == true else {
                    continue
                }

                switch method {
                case Initialize.name:
                    let request = try JSONDecoder().decode(Request<Initialize>.self, from: data)
                    let response = Initialize.response(
                        id: request.id,
                        result: .init(
                            protocolVersion: 1,
                            agentInfo: .init(name: "ACPBridgeAgent", version: "1.0.0"),
                            agentCapabilities: .init(loadSession: true, mcpCapabilities: .init(), promptCapabilities: .init())
                        )
                    )
                    try await transport.send(encoder.encode(response))
                case SessionNew.name:
                    let request = try JSONDecoder().decode(Request<SessionNew>.self, from: data)
                    try await transport.send(encoder.encode(SessionNew.response(id: request.id, result: .init(sessionID: "bridge-session"))))
                case SessionPrompt.name:
                    let request = try JSONDecoder().decode(Request<SessionPrompt>.self, from: data)
                    await recorder.append(promptBlocks: request.params.prompt)
                    let notification = Message<SessionUpdateNotification>(
                        method: SessionUpdateNotification.name,
                        params: .init(
                            sessionID: request.params.sessionID,
                            update: .agentMessageChunk(
                                .init(
                                    content: .init(
                                        text: """
                                        ACP bridge response.

                                        ```json
                                        {"outcome":"success","context_updates":{"bridge":"acp"},"notes":"skill-bridge"}
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

@Suite
struct OmniSkillACPBridgeTests {
    @Test
    func acpWorkerSessionProjectsOmniSkillPromptAndWorkerTools() async throws {
        let recorder = ACPBridgeRecorder()
        let taskStore = ACPBridgeAgentTasks()
        defer {
            Task { await taskStore.cancelAll() }
        }

        let registry = try ToolRegistry()
        let session = ACPWorkerSession(
            toolRegistry: registry,
            transportProvider: ACPBridgeTransportProvider(recorder: recorder, taskStore: taskStore),
            delegateProvider: DefaultACPClientDelegateProvider(permissionStrategy: .autoApprove)
        )
        let projections = [
            OmniSkillWorkerToolProjection(
                skillID: "repo.helper",
                name: "review_findings",
                description: "Return the review rubric.",
                instruction: "List blocking findings first."
            ),
        ]
        let rawToolJSON = try String(decoding: JSONEncoder().encode(projections), as: UTF8.self)
        let task = TaskRecord(
            taskID: "skill-acp-task",
            rootSessionID: "root",
            capabilityRequirements: ["acp"],
            historyProjection: HistoryProjection(
                taskBrief: "Run the ACP skill bridge.",
                constraints: ["stay deterministic"],
                expectedOutputs: ["summary.md"]
            ),
            metadata: [
                "omni_skills.active_ids": "repo.helper",
                "omni_skills.prompt_overlay": "Use repo helper guidance.",
                "omni_skills.codergen_overlay": "Prefer safe patches.",
                "omni_skills.worker_tools_json": rawToolJSON,
                "model_route_tier": "implementer",
                "model_route_provider": "openai",
                "model_route_model": "gpt-5.4",
                "model_route_reasoning_effort": "high",
            ]
        )

        let result = try await session.run(
            task: task,
            profile: .codex(configuration: .init(agentPath: "codex-agent")),
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        let configuration = try #require(await recorder.firstConfiguration())
        let prompt = try #require(await recorder.firstPrompt())

        #expect(result.profileID == "codex")
        #expect(result.contextUpdates["bridge"] == "acp")
        #expect(result.toolServerNames == ["codex-worker-tools"])
        #expect(prompt.localizedStandardContains("Active skills"))
        #expect(prompt.localizedStandardContains("Use repo helper guidance"))
        #expect(prompt.localizedStandardContains("Prefer safe patches"))
        #expect(prompt.localizedStandardContains("Preferred model route: openai/gpt-5.4"))
        #expect(configuration.mcpServers.count == 1)
        #expect(configuration.mcpServers.first?.name == "codex-worker-tools")
        #expect(configuration.mcpServers.first?.env.contains(where: { $0.localizedStandardContains("skill.repo.helper.review_findings") }) == true)
    }
}
