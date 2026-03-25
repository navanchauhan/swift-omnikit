import Foundation
import Testing
import OmniAICore
import OmniAgentMesh
import TheAgentControlPlaneKit
@testable import TheAgentIngress

private actor TelegramPolicyAdapterState {
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
        return responses.last ?? telegramPolicyResponse(text: "")
    }

    func requestCount() -> Int {
        requestCountValue
    }
}

private final class TelegramPolicyAdapter: ProviderAdapter, @unchecked Sendable {
    let name = "openai"
    let state: TelegramPolicyAdapterState

    init(responses: [Response]) {
        self.state = TelegramPolicyAdapterState(responses: responses)
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

private func telegramPolicyResponse(text: String) -> Response {
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
struct TelegramPolicyTests {
    @Test
    func sharedChannelAllowlistBlocksUnknownActorsButAllowsKnownMembers() async throws {
        let harness = try await makeHarness(
            prefix: "telegram-policy",
            responses: [telegramPolicyResponse(text: "Allowlisted reply.")]
        )

        let workspaceID = WorkspaceID(rawValue: "telegram-workspace-group_42")
        let channelID = ChannelID(rawValue: "telegram-channel-group_42")
        try await harness.identityStore.saveWorkspace(
            WorkspaceRecord(
                workspaceID: workspaceID,
                displayName: "group:42",
                kind: .shared,
                metadata: [
                    "allowlist_external_actor_ids": "alice",
                    "ambient_channel_handling": "false",
                ]
            )
        )
        try await harness.identityStore.saveChannelBinding(
            ChannelBinding(
                transport: .telegram,
                externalID: "group:42",
                workspaceID: workspaceID,
                channelID: channelID,
                actorID: ActorID(rawValue: "\(workspaceID.rawValue)-root"),
                metadata: [
                    "require_mention": "true",
                    "channel_kind": "group",
                ]
            )
        )

        let blocked = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "policy-1",
                messageID: "policy-message-1",
                actorExternalID: "bob",
                actorDisplayName: "Bob",
                channelExternalID: "group:42",
                channelKind: .group,
                text: "@bot do it",
                mentionTriggerActive: true
            )
        )
        let allowed = try await harness.gateway.handle(
            IngressEnvelope(
                transport: .telegram,
                payloadKind: .text,
                updateID: "policy-2",
                messageID: "policy-message-2",
                actorExternalID: "alice",
                actorDisplayName: "Alice",
                channelExternalID: "group:42",
                channelKind: .group,
                text: "@bot do it",
                mentionTriggerActive: true
            )
        )

        #expect(blocked.assistantText == "You are not allowlisted for this workspace.")
        #expect(allowed.assistantText == "Allowlisted reply.")
        #expect(await harness.adapter.state.requestCount() == 1)

        await harness.runtimeRegistry.closeAll()
    }

    private func makeHarness(
        prefix: String,
        responses: [Response]
    ) async throws -> TelegramPolicyHarness {
        let stateRoot = try makeStateRoot(prefix: prefix)
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.deliveriesDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let pairingStore = PairingStore(fileURL: stateRoot.runtimeDirectoryURL.appending(path: "pairings.json"))
        let adapter = TelegramPolicyAdapter(responses: responses)
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

        return TelegramPolicyHarness(
            identityStore: identityStore,
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

private struct TelegramPolicyHarness {
    let identityStore: SQLiteIdentityStore
    let runtimeRegistry: WorkspaceRuntimeRegistry
    let gateway: IngressGateway
    let adapter: TelegramPolicyAdapter
}
