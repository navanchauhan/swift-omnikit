import Foundation
import Testing
import OmniAICore
import OmniAgentMesh
import TheAgentControlPlaneKit
import TheAgentWorkerKit
@testable import TheAgentIngress
@testable import TheAgentTelegram

private actor TelegramTestAdapterState {
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
        return responses.last ?? telegramProviderResponse(text: "")
    }
}

private final class TelegramTestAdapter: ProviderAdapter, @unchecked Sendable {
    let name = "openai"
    let state: TelegramTestAdapterState

    init(responses: [Response]) {
        self.state = TelegramTestAdapterState(responses: responses)
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

private func telegramProviderResponse(text: String) -> Response {
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

private actor MockTelegramBotClient: TelegramBotAPI {
    nonisolated let me: TelegramUser
    private var queuedUpdateBatches: [[TelegramUpdate]]
    private(set) var sentMessages: [TelegramSendMessageRequest] = []
    private(set) var answeredCallbacks: [(id: String, text: String?)] = []
    private var sentMessageCounter: Int64 = 10_000

    init(me: TelegramUser, queuedUpdateBatches: [[TelegramUpdate]] = []) {
        self.me = me
        self.queuedUpdateBatches = queuedUpdateBatches
    }

    func queueUpdates(_ batches: [[TelegramUpdate]]) {
        queuedUpdateBatches.append(contentsOf: batches)
    }

    func getMe() async throws -> TelegramUser {
        me
    }

    func getUpdates(
        offset: Int?,
        timeoutSeconds: Int,
        allowedUpdates: [String],
        limit: Int
    ) async throws -> [TelegramUpdate] {
        guard !queuedUpdateBatches.isEmpty else {
            return []
        }
        let next = queuedUpdateBatches.removeFirst()
        if let offset {
            return next.filter { $0.updateID >= offset }
        }
        return next
    }

    func sendMessage(_ request: TelegramSendMessageRequest) async throws -> TelegramMessage {
        sentMessages.append(request)
        sentMessageCounter += 1
        return TelegramMessage(
            messageID: sentMessageCounter,
            from: me,
            chat: TelegramChat(id: Int64(request.chatID) ?? 0, type: .private, title: nil, username: nil, firstName: nil, lastName: nil),
            date: Int64(Date().timeIntervalSince1970),
            text: request.text
        )
    }

    func answerCallbackQuery(
        callbackQueryID: String,
        text: String?,
        showAlert: Bool
    ) async throws {
        answeredCallbacks.append((callbackQueryID, text))
    }

    func setWebhook(url: String, secretToken: String?, allowedUpdates: [String]) async throws {}

    func deleteWebhook(dropPendingUpdates: Bool) async throws {}

    func sentMessagesSnapshot() -> [TelegramSendMessageRequest] {
        sentMessages
    }

    func answeredCallbacksSnapshot() -> [(id: String, text: String?)] {
        answeredCallbacks
    }
}

@Suite
struct TelegramIngressTests {
    @Test
    func webhookHandlerRejectsInvalidSecretToken() async throws {
        let harness = try await makeHarness(prefix: "telegram-secret", responses: [telegramProviderResponse(text: "unused")])
        let handler = try await TelegramWebhookHandler.make(
            client: harness.telegramClient,
            gateway: harness.gateway,
            deliveryStore: harness.deliveryStore,
            expectedSecretToken: "expected-secret"
        )
        let body = try JSONEncoder().encode(
            TelegramUpdate(
                updateID: 1,
                message: TelegramMessage(
                    messageID: 10,
                    from: TelegramUser(id: 42, isBot: false, firstName: "Alice", lastName: nil, username: "alice"),
                    chat: TelegramChat(id: 42, type: .private, title: nil, username: nil, firstName: "Alice", lastName: nil),
                    date: 100,
                    text: "hello"
                ),
                callbackQuery: nil
            )
        )

        await #expect(throws: TelegramWebhookHandlerError.self) {
            _ = try await handler.handle(body: body, providedSecretToken: "wrong")
        }

        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func sharedChatsOnlyTriggerOnMentionAndSensitiveApprovalsFallBackToDmBootstrap() async throws {
        let harness = try await makeHarness(
            prefix: "telegram-shared",
            responses: [telegramProviderResponse(text: "Chief of staff reply.")]
        )
        let handler = try await TelegramWebhookHandler.make(
            client: harness.telegramClient,
            gateway: harness.gateway,
            deliveryStore: harness.deliveryStore
        )

        let ignored = try await handler.handle(
            update: TelegramUpdate(
                updateID: 10,
                message: TelegramMessage(
                    messageID: 100,
                    from: TelegramUser(id: 1, isBot: false, firstName: "Alice", lastName: nil, username: "alice"),
                    chat: TelegramChat(id: -1001, type: .group, title: "Team", username: nil, firstName: nil, lastName: nil),
                    date: 100,
                    text: "ambient chatter"
                ),
                callbackQuery: nil
            )
        )
        #expect(ignored.disposition == .ignored)
        #expect((await harness.telegramClient.sentMessagesSnapshot()).isEmpty)

        let scope = SessionScope(actorID: "shared-workspace-root", workspaceID: "shared-workspace", channelID: "shared-channel")
        try await seedSharedChannel(harness: harness, scope: scope, externalChannelID: "-1001")
        let server = await harness.serverRegistry.server(for: scope)
        _ = try await server.startMission(
            MissionStartRequest(
                title: "Deploy release",
                brief: "Needs approval.",
                requireApproval: true,
                approvalPrompt: "Approve the shared release?"
            )
        )

        let processed = try await handler.handle(
            update: TelegramUpdate(
                updateID: 11,
                message: TelegramMessage(
                    messageID: 101,
                    from: TelegramUser(id: 1, isBot: false, firstName: "Alice", lastName: nil, username: "alice"),
                    chat: TelegramChat(id: -1001, type: .group, title: "Team", username: nil, firstName: nil, lastName: nil),
                    date: 101,
                    text: "@chiefbot status?"
                ),
                callbackQuery: nil
            )
        )

        let sentMessages = await harness.telegramClient.sentMessagesSnapshot()
        #expect(processed.disposition == .processed)
        #expect(sentMessages.count == 2)
        #expect(sentMessages.contains { $0.text.localizedStandardContains("Start a private DM") })

        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func callbackApprovalRoutingAcknowledgesAndCompletesMission() async throws {
        let harness = try await makeHarness(
            prefix: "telegram-approval",
            responses: [telegramProviderResponse(text: "unused root reply")]
        )
        let handler = try await TelegramWebhookHandler.make(
            client: harness.telegramClient,
            gateway: harness.gateway,
            deliveryStore: harness.deliveryStore
        )

        let scope = SessionScope(actorID: "shared-workspace-root", workspaceID: "shared-workspace", channelID: "shared-channel")
        try await seedSharedChannel(harness: harness, scope: scope, externalChannelID: "-1002")
        let server = await harness.serverRegistry.server(for: scope)
        let worker = WorkerDaemon(
            displayName: "telegram-worker",
            capabilities: WorkerCapabilities(["swift"]),
            jobStore: harness.jobStore,
            artifactStore: harness.artifactStore,
            executor: LocalTaskExecutor { task, reportProgress in
                try await reportProgress("approved", ["task_id": task.taskID])
                return LocalTaskExecutionResult(summary: "approved mission complete")
            }
        )
        try await server.registerLocalWorker(worker)

        let started = try await server.startMission(
            MissionStartRequest(
                title: "Approve release",
                brief: "Wait for approval then continue.",
                capabilityRequirements: ["swift"],
                requireApproval: true,
                approvalPrompt: "Ship it?"
            )
        )
        let requestID = try #require(started.approvals.first?.requestID)

        let callbackUpdate = TelegramUpdate(
            updateID: 50,
            message: nil,
            callbackQuery: TelegramCallbackQuery(
                id: "callback-1",
                from: TelegramUser(id: 1, isBot: false, firstName: "Alice", lastName: nil, username: "alice"),
                message: TelegramMessage(
                    messageID: 150,
                    from: harness.telegramClient.me,
                    chat: TelegramChat(id: -1002, type: .group, title: "Team", username: nil, firstName: nil, lastName: nil),
                    date: 150,
                    text: "Approval prompt"
                ),
                data: TelegramCallbackCodec.encode(.approval(requestID: requestID, approved: true))
            )
        )

        let result = try await handler.handle(update: callbackUpdate)
        let finished = try await server.waitForMission(missionID: started.mission.missionID, timeoutSeconds: 5)
        let approval = try await harness.missionStore.approvalRequest(requestID: requestID)

        #expect(result.disposition == .processed)
        #expect(finished.mission.status == .completed)
        #expect(approval?.status == .approved)
        #expect((await harness.telegramClient.answeredCallbacksSnapshot()).first?.id == "callback-1")
        #expect((await harness.telegramClient.sentMessagesSnapshot()).last?.text == "Approval recorded.")

        await harness.runtimeRegistry.closeAll()
    }

    @Test
    func pollingRunnerResumesSafelyBecauseIngressDedupeSuppressesReplay() async throws {
        let harness = try await makeHarness(
            prefix: "telegram-poll",
            responses: [telegramProviderResponse(text: "Polled once.")]
        )
        let duplicateUpdate = TelegramUpdate(
            updateID: 200,
            message: TelegramMessage(
                messageID: 200,
                from: TelegramUser(id: 5, isBot: false, firstName: "Bob", lastName: nil, username: "bob"),
                chat: TelegramChat(id: 5, type: .private, title: nil, username: nil, firstName: "Bob", lastName: nil),
                date: 200,
                text: "hello"
            ),
            callbackQuery: nil
        )
        await harness.telegramClient.queueUpdates([[duplicateUpdate], [duplicateUpdate]])

        let handler = try await TelegramWebhookHandler.make(
            client: harness.telegramClient,
            gateway: harness.gateway,
            deliveryStore: harness.deliveryStore
        )
        let runner = TelegramPollingRunner(client: harness.telegramClient, webhookHandler: handler)
        try await runner.run(timeoutSeconds: 0, maxPolls: 2)

        let sentMessages = await harness.telegramClient.sentMessagesSnapshot()
        #expect(sentMessages.count == 1)
        #expect(sentMessages.first?.text == "Polled once.")

        await harness.runtimeRegistry.closeAll()
    }

    private func seedSharedChannel(
        harness: TelegramIngressHarness,
        scope: SessionScope,
        externalChannelID: String
    ) async throws {
        try await harness.identityStore.saveWorkspace(
            WorkspaceRecord(workspaceID: scope.workspaceID, displayName: "Shared Workspace", kind: .shared)
        )
        try await harness.identityStore.saveMembership(
            WorkspaceMembership(workspaceID: scope.workspaceID, actorID: "telegram-actor-1", role: .owner)
        )
        try await harness.identityStore.saveChannelBinding(
            ChannelBinding(
                transport: .telegram,
                externalID: externalChannelID,
                workspaceID: scope.workspaceID,
                channelID: scope.channelID,
                actorID: scope.actorID,
                metadata: [
                    "channel_kind": IngressEnvelope.ChannelKind.group.rawValue,
                    "ambient_messages_enabled": "false",
                ]
            )
        )
    }

    private func makeHarness(
        prefix: String,
        responses: [Response]
    ) async throws -> TelegramIngressHarness {
        let stateRoot = try makeStateRoot(prefix: prefix)
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.missionsDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let adapter = TelegramTestAdapter(responses: responses)
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
        let telegramClient = MockTelegramBotClient(
            me: TelegramUser(id: 999, isBot: true, firstName: "Chief", lastName: nil, username: "chiefbot")
        )

        return TelegramIngressHarness(
            stateRoot: stateRoot,
            identityStore: identityStore,
            missionStore: missionStore,
            deliveryStore: deliveryStore,
            jobStore: jobStore,
            artifactStore: artifactStore,
            serverRegistry: serverRegistry,
            runtimeRegistry: runtimeRegistry,
            gateway: gateway,
            telegramClient: telegramClient
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

private struct TelegramIngressHarness {
    let stateRoot: AgentFabricStateRoot
    let identityStore: SQLiteIdentityStore
    let missionStore: SQLiteMissionStore
    let deliveryStore: SQLiteDeliveryStore
    let jobStore: SQLiteJobStore
    let artifactStore: FileArtifactStore
    let serverRegistry: WorkspaceSessionRegistry
    let runtimeRegistry: WorkspaceRuntimeRegistry
    let gateway: IngressGateway
    let telegramClient: MockTelegramBotClient
}
