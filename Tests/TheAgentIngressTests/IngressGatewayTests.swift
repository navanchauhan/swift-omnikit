import Foundation
import Testing
import OmniAICore
import OmniAgentMesh
import TheAgentControlPlaneKit
@testable import TheAgentIngress

private actor IngressTestAdapterState {
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
        return responses.last ?? ingressResponse(text: "")
    }

    func requestCount() -> Int {
        requestCountValue
    }
}

private final class IngressTestAdapter: ProviderAdapter, @unchecked Sendable {
    let name = "openai"
    let state: IngressTestAdapterState

    init(responses: [Response]) {
        self.state = IngressTestAdapterState(responses: responses)
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

private func ingressResponse(text: String) -> Response {
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

@Suite
struct IngressGatewayTests {
    @Test
    func directMessagesAutoProvisionPersonalWorkspaceAndRouteThroughScopedRuntime() async throws {
        let harness = try await makeHarness(
            prefix: "ingress-dm",
            responses: [ingressResponse(text: "Chief of staff completed the task.")]
        )

        let result = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "update-1",
                messageID: "message-1",
                actorExternalID: "alice",
                actorDisplayName: "Alice",
                channelExternalID: "dm:alice",
                channelKind: .directMessage,
                text: "Handle this for me."
            )
        )

        let workspace = try await harness.identityStore.workspace(workspaceID: "telegram-dm-alice")
        let membership = try await harness.identityStore.membership(workspaceID: "telegram-dm-alice", actorID: "telegram-actor-alice")
        let binding = try await harness.identityStore.channelBinding(transport: .telegram, externalID: "dm:alice")
        let cachedSessionIDs = await harness.runtimeRegistry.cachedSessionIDs()
        let inboundDeliveries = try await harness.deliveryStore.deliveries(direction: .inbound, sessionID: cachedSessionIDs.first, status: nil)
        let outboundDeliveries = try await harness.deliveryStore.deliveries(direction: .outbound, sessionID: cachedSessionIDs.first, status: nil)

        #expect(result.disposition == .processed)
        #expect(result.assistantText == "Chief of staff completed the task.")
        #expect(result.deliveries.count == 1)
        #expect(result.deliveries.first?.chunks == ["Chief of staff completed the task."])
        #expect(workspace?.kind == .personal)
        #expect(membership?.role == .owner)
        #expect(binding?.workspaceID == "telegram-dm-alice")
        #expect(cachedSessionIDs.count == 1)
        #expect(inboundDeliveries.count == 1)
        #expect(outboundDeliveries.count == 1)
        #expect(await harness.adapter.state.requestCount() == 1)

        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func duplicateUpdatesAreSuppressedDurably() async throws {
        let harness = try await makeHarness(
            prefix: "ingress-duplicate",
            responses: [ingressResponse(text: "Only once.")]
        )

        let envelope = IngressEnvelope(
            transport: .telegram,
            payloadKind: .text,
            updateID: "duplicate-1",
            messageID: "message-1",
            actorExternalID: "alice",
            channelExternalID: "dm:alice",
            channelKind: .directMessage,
            text: "Do it once."
        )

        let first = try await harness.gateway.handle(envelope)
        let second = try await harness.gateway.handle(envelope)
        let allDeliveries = try await harness.deliveryStore.deliveries(direction: nil, sessionID: nil, status: nil)

        #expect(first.disposition == .processed)
        #expect(second.disposition == .duplicate)
        #expect(allDeliveries.filter { $0.direction == .inbound }.count == 1)
        #expect(await harness.adapter.state.requestCount() == 1)

        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func sharedChannelsIgnoreAmbientMessagesByDefault() async throws {
        let harness = try await makeHarness(
            prefix: "ingress-ignore",
            responses: [ingressResponse(text: "This should not be used.")]
        )

        let result = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "group-1",
                messageID: "group-message-1",
                actorExternalID: "alice",
                channelExternalID: "group:42",
                channelKind: .group,
                text: "ambient chatter"
            )
        )

        let deliveries = try await harness.deliveryStore.deliveries(direction: .inbound, sessionID: nil, status: .ignored)

        #expect(result.disposition == .ignored)
        #expect(result.deliveries.isEmpty)
        #expect(await harness.runtimeRegistry.cachedSessionIDs().isEmpty)
        #expect(deliveries.count == 1)
        #expect(await harness.adapter.state.requestCount() == 0)

        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func mentionedSharedMessagesUseOneRuntimeAcrossMultipleActors() async throws {
        let harness = try await makeHarness(
            prefix: "ingress-shared",
            responses: [
                ingressResponse(text: "First reply."),
                ingressResponse(text: "Second reply."),
            ]
        )

        _ = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "shared-1",
                messageID: "group-message-1",
                actorExternalID: "alice",
                channelExternalID: "group:42",
                channelKind: .group,
                text: "@bot do the first thing",
                mentionTriggerActive: true
            )
        )
        _ = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "shared-2",
                messageID: "group-message-2",
                actorExternalID: "bob",
                channelExternalID: "group:42",
                channelKind: .group,
                text: "@bot do the second thing",
                mentionTriggerActive: true
            )
        )

        let cachedSessionIDs = await harness.runtimeRegistry.cachedSessionIDs()
        let sessionID = try #require(cachedSessionIDs.first)
        let interactions = try await harness.conversationStore.interactions(sessionID: sessionID, limit: nil)
        let userActorIDs = interactions
            .filter { $0.role == .user }
            .compactMap(\.actorID?.rawValue)

        #expect(cachedSessionIDs.count == 1)
        #expect(userActorIDs == ["telegram-actor-alice", "telegram-actor-bob"])
        #expect(await harness.adapter.state.requestCount() == 2)

        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func longResponsesAreChunkedIntoMultipleDeliveries() async throws {
        let longReply = String(repeating: "a", count: 8_100)
        let harness = try await makeHarness(
            prefix: "ingress-chunking",
            responses: [ingressResponse(text: longReply)]
        )

        let result = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "chunk-1",
                messageID: "chunk-message-1",
                actorExternalID: "alice",
                channelExternalID: "dm:alice",
                channelKind: .directMessage,
                text: "Send a long response."
            )
        )

        #expect(result.disposition == .processed)
        #expect(result.deliveries.count == 3)
        #expect(result.deliveries.allSatisfy { $0.chunks.first?.count ?? 0 <= 3_500 })

        await harness.runtimeRegistry.closeAll()
    }

    private func makeHarness(
        prefix: String,
        responses: [Response]
    ) async throws -> IngressTestHarness {
        let stateRoot = try makeStateRoot(prefix: prefix)
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.missionsDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let adapter = IngressTestAdapter(responses: responses)
        let client = try Client(providers: ["openai": adapter], defaultProvider: "openai")
        let serverRegistry = WorkspaceSessionRegistry(
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore,
            hotWindowLimit: 8
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

        return IngressTestHarness(
            conversationStore: conversationStore,
            identityStore: identityStore,
            deliveryStore: deliveryStore,
            runtimeRegistry: runtimeRegistry,
            gateway: gateway,
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

private struct IngressTestHarness {
    let conversationStore: SQLiteConversationStore
    let identityStore: SQLiteIdentityStore
    let deliveryStore: SQLiteDeliveryStore
    let runtimeRegistry: WorkspaceRuntimeRegistry
    let gateway: IngressGateway
    let adapter: IngressTestAdapter
}
