import Foundation
import Testing
import OmniAICore
import OmniAgentMesh
import TheAgentControlPlaneKit
@testable import TheAgentIngress

@Suite
struct MultiUserRoutingTests {
    @Test
    func concurrentPersonalWorkspacesStayIsolatedAcrossActors() async throws {
        let harness = try await makeHarness(
            prefix: "multi-user-dm",
            responses: [
                multiUserResponse(text: "Alice reply."),
                multiUserResponse(text: "Bob reply."),
            ]
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try await harness.gateway.handle(
                    IngressEnvelope(
                        transport: .telegram,
                        payloadKind: .text,
                        updateID: "alice-1",
                        messageID: "alice-message-1",
                        actorExternalID: "alice",
                        actorDisplayName: "Alice",
                        channelExternalID: "dm:alice",
                        channelKind: .directMessage,
                        text: "Handle Alice's task."
                    )
                )
            }
            group.addTask {
                _ = try await harness.gateway.handle(
                    IngressEnvelope(
                        transport: .telegram,
                        payloadKind: .text,
                        updateID: "bob-1",
                        messageID: "bob-message-1",
                        actorExternalID: "bob",
                        actorDisplayName: "Bob",
                        channelExternalID: "dm:bob",
                        channelKind: .directMessage,
                        text: "Handle Bob's task."
                    )
                )
            }
            try await group.waitForAll()
        }

        let cachedSessionIDs = await harness.runtimeRegistry.cachedSessionIDs()
        #expect(cachedSessionIDs.count == 2)

        for sessionID in cachedSessionIDs {
            let interactions = try await harness.conversationStore.interactions(sessionID: sessionID, limit: nil)
            let actorIDs = Set(interactions.compactMap(\.actorID?.rawValue))
            #expect(actorIDs.count == 1)
        }

        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func sharedWorkspaceAndPersonalWorkspaceDoNotCrossTalkDuringConcurrentIngress() async throws {
        let harness = try await makeHarness(
            prefix: "multi-user-mixed",
            responses: [
                multiUserResponse(text: "Shared reply A."),
                multiUserResponse(text: "Shared reply B."),
                multiUserResponse(text: "Carol reply."),
            ]
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try await harness.gateway.handle(
                    IngressEnvelope(
                        transport: .telegram,
                        payloadKind: .text,
                        updateID: "group-a",
                        messageID: "group-a-1",
                        actorExternalID: "alice",
                        actorDisplayName: "Alice",
                        channelExternalID: "group:77",
                        channelKind: .group,
                        text: "@bot shared task A",
                        mentionTriggerActive: true
                    )
                )
            }
            group.addTask {
                _ = try await harness.gateway.handle(
                    IngressEnvelope(
                        transport: .telegram,
                        payloadKind: .text,
                        updateID: "group-b",
                        messageID: "group-b-1",
                        actorExternalID: "bob",
                        actorDisplayName: "Bob",
                        channelExternalID: "group:77",
                        channelKind: .group,
                        text: "@bot shared task B",
                        mentionTriggerActive: true
                    )
                )
            }
            group.addTask {
                _ = try await harness.gateway.handle(
                    IngressEnvelope(
                        transport: .telegram,
                        payloadKind: .text,
                        updateID: "dm-c",
                        messageID: "dm-c-1",
                        actorExternalID: "carol",
                        actorDisplayName: "Carol",
                        channelExternalID: "dm:carol",
                        channelKind: .directMessage,
                        text: "Private request."
                    )
                )
            }
            try await group.waitForAll()
        }

        let cachedSessionIDs = await harness.runtimeRegistry.cachedSessionIDs()
        #expect(cachedSessionIDs.count == 2)

        let sharedSessionID = try #require(
            cachedSessionIDs.first(where: { SessionScope.bestEffort(sessionID: $0).channelID.rawValue == "telegram-channel-group_77" })
        )
        let dmSessionID = try #require(
            cachedSessionIDs.first(where: { SessionScope.bestEffort(sessionID: $0).channelID.rawValue == "telegram-channel-dm_carol" })
        )

        let sharedInteractions = try await harness.conversationStore.interactions(sessionID: sharedSessionID, limit: nil)
        let dmInteractions = try await harness.conversationStore.interactions(sessionID: dmSessionID, limit: nil)

        let sharedActors = Set(sharedInteractions.filter { $0.role == .user }.compactMap(\.actorID?.rawValue))
        let dmActors = Set(dmInteractions.filter { $0.role == .user }.compactMap(\.actorID?.rawValue))

        #expect(sharedActors == Set(["telegram-actor-alice", "telegram-actor-bob"]))
        #expect(dmActors == Set(["telegram-actor-carol"]))

        await harness.runtimeRegistry.closeAll()
    }

    private func makeHarness(
        prefix: String,
        responses: [Response]
    ) async throws -> MultiUserHarness {
        let stateRoot = try makeStateRoot(prefix: prefix)
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.missionsDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let adapter = MultiUserTestAdapter(responses: responses)
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

        return MultiUserHarness(
            conversationStore: conversationStore,
            runtimeRegistry: runtimeRegistry,
            gateway: gateway
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

private struct MultiUserHarness {
    let conversationStore: SQLiteConversationStore
    let runtimeRegistry: WorkspaceRuntimeRegistry
    let gateway: IngressGateway
}

private actor MultiUserAdapterState {
    private var responses: [Response]
    private var index = 0

    init(responses: [Response]) {
        self.responses = responses
    }

    func nextResponse() -> Response {
        let currentIndex = index
        index += 1
        if currentIndex < responses.count {
            return responses[currentIndex]
        }
        return responses.last ?? multiUserResponse(text: "")
    }
}

private final class MultiUserTestAdapter: ProviderAdapter, @unchecked Sendable {
    let name = "openai"
    private let state: MultiUserAdapterState

    init(responses: [Response]) {
        self.state = MultiUserAdapterState(responses: responses)
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

private func multiUserResponse(text: String) -> Response {
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
