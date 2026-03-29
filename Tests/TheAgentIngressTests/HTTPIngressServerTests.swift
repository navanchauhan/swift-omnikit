import Foundation
import Testing
import OmniAICore
import OmniAgentMesh
import TheAgentControlPlaneKit
import TheAgentWorkerKit
@testable import TheAgentIngress

@Suite
struct HTTPIngressServerTests {
    @Test
    func authenticatedMessageSubmissionReturnsAssistantReply() async throws {
        let harness = try await makeHarness(
            prefix: "http-ingress-message",
            responses: [httpIngressResponse(text: "Chief of staff reply via API.")]
        )

        let response: HTTPIngressMessageEnvelope = try await harness.postJSON(
            path: "/api/v1/messages",
            body: HTTPIngressServer.MessageRequest(
                transport: .api,
                actorExternalID: "api-user",
                actorDisplayName: "API User",
                channelExternalID: "api-channel-1",
                channelKind: .api,
                text: "Do the API task."
            ),
            expectedStatusCode: 200
        )

        #expect(response.disposition == "processed")
        #expect(response.assistantText == "Chief of staff reply via API.")
        #expect(response.deliveries.count == 1)
        #expect(await harness.adapter.state.requestCount() == 1)

        try await harness.server.stop()
        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func inboxPollingAndApprovalResponsesWorkOverAuthenticatedHTTPIngress() async throws {
        let harness = try await makeHarness(
            prefix: "http-ingress-approval",
            responses: [httpIngressResponse(text: "This response should stay unused.")]
        )

        let scope = SessionScope(
            actorID: ActorID(rawValue: "api-admin"),
            workspaceID: WorkspaceID(rawValue: "workspace-api"),
            channelID: ChannelID(rawValue: "channel-api")
        )
        let scopedServer = await harness.serverRegistry.server(for: scope)
        let worker = WorkerDaemon(
            displayName: "http-approval-worker",
            capabilities: WorkerCapabilities(["macOS"]),
            jobStore: harness.jobStore,
            artifactStore: harness.artifactStore,
            executor: LocalTaskExecutor { _, reportProgress in
                try await reportProgress("Approved over HTTP ingress", [:])
                return LocalTaskExecutionResult(summary: "Mission completed after HTTP approval.")
            }
        )
        try await scopedServer.registerLocalWorker(worker)

        let started = try await scopedServer.startMission(
            MissionStartRequest(
                title: "HTTP approval mission",
                brief: "Wait for approval from HTTP ingress.",
                capabilityRequirements: ["macOS"],
                requireApproval: true,
                approvalPrompt: "Approve the HTTP mission?"
            )
        )
        let requestID = try #require(started.approvals.first?.requestID)

        let inboxItems: [InteractionInboxItem] = try await harness.postJSON(
            path: "/api/v1/inbox",
            body: HTTPIngressServer.ScopeRequest(sessionID: scope.sessionID),
            expectedStatusCode: 200
        )
        #expect(inboxItems.contains { $0.kind == .approval && $0.id == requestID })

        let approval: ApprovalRequestRecord = try await harness.postJSON(
            path: "/api/v1/approvals",
            body: HTTPIngressServer.ApprovalDecisionRequest(
                sessionID: scope.sessionID,
                workspaceID: nil,
                channelID: nil,
                actorID: scope.actorID.rawValue,
                requestID: requestID,
                approved: true,
                responseText: "Approved over HTTP"
            ),
            expectedStatusCode: 200
        )

        #expect(approval.status == .approved)

        let finished = try await scopedServer.waitForMission(
            missionID: started.mission.missionID,
            timeoutSeconds: 5
        )
        #expect(finished.mission.status == .completed)
        #expect(finished.task?.status == .completed)

        try await harness.server.stop()
        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func missingBearerTokenIsRejected() async throws {
        let harness = try await makeHarness(
            prefix: "http-ingress-auth",
            responses: [httpIngressResponse(text: "unused")]
        )

        let request = HTTPIngressServer.MessageRequest(
            transport: .api,
            actorExternalID: "api-user",
            channelExternalID: "api-channel-2",
            channelKind: .api,
            text: "This should be rejected."
        )

        let (statusCode, body) = try await harness.postRawJSON(
            path: "/api/v1/messages",
            body: request,
            bearerToken: nil
        )

        #expect(statusCode == 400)
        #expect(String(decoding: body, as: UTF8.self).localizedStandardContains("Missing bearer authorization"))
        #expect(await harness.adapter.state.requestCount() == 0)

        try await harness.server.stop()
        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func telegramWebhookRequestsAreAcceptedAndForwardedAsync() async throws {
        let recorder = TelegramWebhookRecorder()
        let harness = try await makeHarness(
            prefix: "http-ingress-webhook",
            responses: [httpIngressResponse(text: "unused")],
            telegramWebhookForwarder: { body, headers in
                try? await Task.sleep(for: .milliseconds(25))
                await recorder.record(body: body, headers: headers)
            }
        )

        let (statusCode, data) = try await harness.postRawJSON(
            path: "/telegram/webhook",
            body: ["update_id": 42],
            bearerToken: nil
        )

        #expect(statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).localizedStandardContains("accepted"))

        for _ in 0..<20 {
            if await recorder.count() == 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let forwarded = await recorder.snapshot()
        #expect(forwarded.count == 1)
        #expect(String(decoding: forwarded[0].body, as: UTF8.self).localizedStandardContains("\"update_id\":42"))
        #expect(forwarded[0].headers["content-type"] == "application/json")

        try await harness.server.stop()
        await harness.runtimeRegistry.closeAll()
    }

    private func makeHarness(
        prefix: String,
        responses: [Response],
        telegramWebhookForwarder: HTTPIngressServer.TelegramWebhookForwarder? = nil
    ) async throws -> HTTPIngressHarness {
        let stateRoot = try makeStateRoot(prefix: prefix)
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.missionsDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let adapter = HTTPIngressTestAdapter(responses: responses)
        let client = try Client(providers: ["openai": adapter], defaultProvider: "openai")
        let serverRegistry = WorkspaceSessionRegistry(
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore
        )
        let runtimeRegistry = WorkspaceRuntimeRegistry(
            serverRegistry: serverRegistry,
            stateRoot: stateRoot,
            runtimeOptions: RootAgentRuntimeOptions(
                provider: .openai,
                model: "gpt-test",
                workingDirectory: stateRoot.rootDirectory.path()
            ),
            client: client
        )
        let gateway = IngressGateway(
            identityStore: identityStore,
            deliveryStore: deliveryStore,
            missionStore: missionStore,
            runtimeRegistry: runtimeRegistry
        )
        let server = HTTPIngressServer(
            gateway: gateway,
            runtimeRegistry: runtimeRegistry,
            expectedBearerToken: "secret-token",
            telegramWebhookForwarder: telegramWebhookForwarder,
            host: "127.0.0.1",
            port: 0
        )
        let listeningAddress = try await server.start()

        return HTTPIngressHarness(
            baseURL: listeningAddress.baseURL,
            server: server,
            serverRegistry: serverRegistry,
            runtimeRegistry: runtimeRegistry,
            jobStore: jobStore,
            artifactStore: artifactStore,
            adapter: adapter
        )
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

private struct HTTPIngressHarness {
    let baseURL: URL
    let server: HTTPIngressServer
    let serverRegistry: WorkspaceSessionRegistry
    let runtimeRegistry: WorkspaceRuntimeRegistry
    let jobStore: SQLiteJobStore
    let artifactStore: FileArtifactStore
    let adapter: HTTPIngressTestAdapter

    func postJSON<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        bearerToken: String? = "secret-token",
        expectedStatusCode: Int
    ) async throws -> Response {
        let (statusCode, data) = try await postRawJSON(path: path, body: body, bearerToken: bearerToken)
        #expect(statusCode == expectedStatusCode)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    func postRawJSON<Request: Encodable>(
        path: String,
        body: Request,
        bearerToken: String? = "secret-token"
    ) async throws -> (Int, Data) {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        return (http.statusCode, data)
    }
}

private struct HTTPIngressMessageEnvelope: Decodable {
    let disposition: String
    let assistantText: String?
    let deliveries: [IngressDeliveryInstruction]
}

private actor TelegramWebhookRecorder {
    private var forwards: [(body: Data, headers: [String: String])] = []

    func record(body: Data, headers: [String: String]) {
        forwards.append((body, headers))
    }

    func count() -> Int {
        forwards.count
    }

    func snapshot() -> [(body: Data, headers: [String: String])] {
        forwards
    }
}

private actor HTTPIngressAdapterState {
    private var responses: [Response]
    private var requestCountValue = 0
    private var index = 0

    init(responses: [Response]) {
        self.responses = responses
    }

    func nextResponse() -> Response {
        requestCountValue += 1
        let currentIndex = index
        index += 1
        if currentIndex < responses.count {
            return responses[currentIndex]
        }
        return responses.last ?? httpIngressResponse(text: "")
    }

    func requestCount() -> Int {
        requestCountValue
    }
}

private final class HTTPIngressTestAdapter: ProviderAdapter, @unchecked Sendable {
    let name = "openai"
    let state: HTTPIngressAdapterState

    init(responses: [Response]) {
        self.state = HTTPIngressAdapterState(responses: responses)
    }

    func complete(request: Request) async throws -> Response {
        await state.nextResponse()
    }

    func stream(request: Request) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let response = await state.nextResponse()
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

private func httpIngressResponse(text: String) -> Response {
    Response(
        id: "resp_\(UUID().uuidString)",
        model: "gpt-test",
        provider: "openai",
        message: Message(role: .assistant, content: [.text(text)]),
        finishReason: FinishReason(kind: .stop, raw: "stop"),
        usage: Usage(inputTokens: 1, outputTokens: 1),
        raw: nil,
        warnings: [],
        rateLimit: nil
    )
}
