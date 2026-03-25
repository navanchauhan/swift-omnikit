import Foundation
import Testing
import OmniAICore
import OmniAgentMesh
import TheAgentControlPlaneKit
@testable import TheAgentIngress

private actor TelegramPairingAdapterState {
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
        return responses.last ?? telegramIngressResponse(text: "")
    }

    func requestCount() -> Int {
        requestCountValue
    }
}

private final class TelegramPairingAdapter: ProviderAdapter, @unchecked Sendable {
    let name = "openai"
    let state: TelegramPairingAdapterState

    init(responses: [Response]) {
        self.state = TelegramPairingAdapterState(responses: responses)
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

private func telegramIngressResponse(text: String) -> Response {
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
struct TelegramPairingTests {
    @Test
    func directMessagesRequirePairingBeforeRuntimeExecution() async throws {
        let harness = try await makeHarness(
            prefix: "telegram-pairing",
            responses: [telegramIngressResponse(text: "Paired reply.")]
        )

        let first = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "pairing-1",
                messageID: "pairing-message-1",
                actorExternalID: "alice",
                actorDisplayName: "Alice",
                channelExternalID: "dm:alice",
                channelKind: .directMessage,
                text: "hello"
            )
        )
        let pairing = try #require(await harness.pairingStore.activeRecord(transport: .telegram, actorExternalID: "alice"))
        let second = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "pairing-2",
                messageID: "pairing-message-2",
                actorExternalID: "alice",
                actorDisplayName: "Alice",
                channelExternalID: "dm:alice",
                channelKind: .directMessage,
                text: "/pair \(pairing.code)"
            )
        )
        let third = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "pairing-3",
                messageID: "pairing-message-3",
                actorExternalID: "alice",
                actorDisplayName: "Alice",
                channelExternalID: "dm:alice",
                channelKind: .directMessage,
                text: "now do the thing"
            )
        )

        let actor = try await harness.identityStore.actor(actorID: ActorID(rawValue: "telegram-actor-alice"))

        #expect(first.assistantText?.localizedStandardContains("Pairing required") == true)
        #expect(second.assistantText == "Pairing complete. You can continue.")
        #expect(third.assistantText == "Paired reply.")
        #expect(actor?.metadata["paired"] == "true")
        #expect(await harness.adapter.state.requestCount() == 1)

        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func globalTelegramAllowlistBlocksUnlistedDirectMessagesBeforePairing() async throws {
        let harness = try await makeHarness(
            prefix: "telegram-pairing-global-allowlist",
            responses: [telegramIngressResponse(text: "Paired reply.")]
        )

        try await harness.identityStore.saveWorkspace(
            WorkspaceRecord(
                workspaceID: WorkspaceID(rawValue: "root"),
                displayName: "TheAgent Root Workspace",
                kind: .service,
                metadata: [
                    "telegram_allowlist_external_actor_ids": "alice",
                ]
            )
        )

        let blocked = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "pairing-global-1",
                messageID: "pairing-global-message-1",
                actorExternalID: "bob",
                actorDisplayName: "Bob",
                channelExternalID: "dm:bob",
                channelKind: .directMessage,
                text: "hello"
            )
        )
        let firstAllowed = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "pairing-global-2",
                messageID: "pairing-global-message-2",
                actorExternalID: "alice",
                actorDisplayName: "Alice",
                channelExternalID: "dm:alice",
                channelKind: .directMessage,
                text: "hello"
            )
        )
        let pairing = try #require(await harness.pairingStore.activeRecord(transport: .telegram, actorExternalID: "alice"))
        let secondAllowed = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "pairing-global-3",
                messageID: "pairing-global-message-3",
                actorExternalID: "alice",
                actorDisplayName: "Alice",
                channelExternalID: "dm:alice",
                channelKind: .directMessage,
                text: "/pair \(pairing.code)"
            )
        )
        let thirdAllowed = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "pairing-global-4",
                messageID: "pairing-global-message-4",
                actorExternalID: "alice",
                actorDisplayName: "Alice",
                channelExternalID: "dm:alice",
                channelKind: .directMessage,
                text: "now do the thing"
            )
        )

        #expect(blocked.assistantText == "You are not allowlisted for this workspace.")
        #expect(firstAllowed.assistantText?.localizedStandardContains("Pairing required") == true)
        #expect(secondAllowed.assistantText == "Pairing complete. You can continue.")
        #expect(thirdAllowed.assistantText == "Paired reply.")
        #expect(await harness.adapter.state.requestCount() == 1)

        await harness.runtimeRegistry.closeAll()
    }

    private func makeHarness(
        prefix: String,
        responses: [Response]
    ) async throws -> TelegramPairingHarness {
        let stateRoot = try makeStateRoot(prefix: prefix)
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.deliveriesDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let pairingStore = PairingStore(fileURL: stateRoot.runtimeDirectoryURL.appending(path: "pairings.json"))
        let adapter = TelegramPairingAdapter(responses: responses)
        let client = try Client(providers: ["openai": adapter], defaultProvider: "openai")
        let serverRegistry = WorkspaceSessionRegistry(
            stateRoot: stateRoot,
            identityStore: identityStore,
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore,
            pairingStore: pairingStore,
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
        let policyManager = ChannelPolicyManager(
            identityStore: identityStore,
            pairingStore: pairingStore
        )
        let gateway = IngressGateway(
            identityStore: identityStore,
            deliveryStore: deliveryStore,
            missionStore: missionStore,
            runtimeRegistry: runtimeRegistry,
            policyManager: policyManager,
            onboardingWizard: OnboardingWizard(policyManager: policyManager),
            attachmentStager: AttachmentStager(artifactStore: artifactStore)
        )

        return TelegramPairingHarness(
            identityStore: identityStore,
            pairingStore: pairingStore,
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

private struct TelegramPairingHarness {
    let identityStore: SQLiteIdentityStore
    let pairingStore: PairingStore
    let runtimeRegistry: WorkspaceRuntimeRegistry
    let gateway: IngressGateway
    let adapter: TelegramPairingAdapter
}
