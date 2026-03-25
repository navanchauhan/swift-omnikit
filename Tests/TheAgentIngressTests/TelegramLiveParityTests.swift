import Foundation
import Testing
import OmniAICore
import OmniAgentMesh
import TheAgentControlPlaneKit
import TheAgentWorkerKit
@testable import TheAgentIngress
@testable import TheAgentTelegram

private actor TelegramLiveAdapterState {
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
        return responses.last ?? telegramLiveResponse(text: "")
    }
}

private final class TelegramLiveAdapter: ProviderAdapter, @unchecked Sendable {
    let name = "openai"
    let state: TelegramLiveAdapterState

    init(responses: [Response]) {
        self.state = TelegramLiveAdapterState(responses: responses)
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

private func telegramLiveResponse(text: String) -> Response {
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

private actor TelegramLiveBotClient: TelegramBotAPI {
    nonisolated let me: TelegramUser
    private var sentMessages: [TelegramSendMessageRequest] = []
    private var answeredCallbacks: [(id: String, text: String?)] = []
    private var sentMessageCounter: Int64 = 20_000

    init(me: TelegramUser) {
        self.me = me
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
        []
    }

    func sendMessage(_ request: TelegramSendMessageRequest) async throws -> TelegramMessage {
        sentMessages.append(request)
        sentMessageCounter += 1
        return TelegramMessage(
            messageID: sentMessageCounter,
            from: me,
            chat: TelegramChat(
                id: Int64(request.chatID) ?? 0,
                type: .private,
                title: nil,
                username: nil,
                firstName: nil,
                lastName: nil
            ),
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
struct TelegramLiveParityTests {
    @Test
    func dmPairingApprovalAndMissionCompletionWorkEndToEnd() async throws {
        let harness = try await makeHarness()
        let handler = try await TelegramWebhookHandler.make(
            client: harness.telegramClient,
            gateway: harness.gateway,
            deliveryStore: harness.deliveryStore
        )

        let first = try await handler.handle(
            update: TelegramUpdate(
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
        let pairing = try #require(await harness.pairingStore.activeRecord(transport: .telegram, actorExternalID: "42"))
        let second = try await handler.handle(
            update: TelegramUpdate(
                updateID: 2,
                message: TelegramMessage(
                    messageID: 11,
                    from: TelegramUser(id: 42, isBot: false, firstName: "Alice", lastName: nil, username: "alice"),
                    chat: TelegramChat(id: 42, type: .private, title: nil, username: nil, firstName: "Alice", lastName: nil),
                    date: 101,
                    text: "/pair \(pairing.code)"
                ),
                callbackQuery: nil
            )
        )

        let binding = try #require(await harness.identityStore.channelBinding(transport: .telegram, externalID: "dm:42"))
        let scope = SessionScope(
            actorID: ActorID(rawValue: "telegram-actor-42"),
            workspaceID: binding.workspaceID,
            channelID: binding.channelID
        )
        let server = await harness.serverRegistry.server(for: scope)
        let worker = WorkerDaemon(
            displayName: "telegram-live-worker",
            capabilities: WorkerCapabilities(["swift"]),
            jobStore: harness.jobStore,
            artifactStore: harness.artifactStore,
            executor: LocalTaskExecutor { _, reportProgress in
                try await reportProgress("mission running", [:])
                return LocalTaskExecutionResult(summary: "mission complete")
            }
        )
        try await server.registerLocalWorker(worker)
        let started = try await server.startMission(
            MissionStartRequest(
                title: "Ship release",
                brief: "Complete the release after approval.",
                executionMode: .workerTask,
                capabilityRequirements: ["swift"],
                expectedOutputs: ["artifact"],
                requireApproval: true,
                approvalPrompt: "Ship it?"
            )
        )
        let requestID = try #require(started.approvals.first?.requestID)

        let statusResult = try await handler.handle(
            update: TelegramUpdate(
                updateID: 3,
                message: TelegramMessage(
                    messageID: 12,
                    from: TelegramUser(id: 42, isBot: false, firstName: "Alice", lastName: nil, username: "alice"),
                    chat: TelegramChat(id: 42, type: .private, title: nil, username: nil, firstName: "Alice", lastName: nil),
                    date: 102,
                    text: "status?"
                ),
                callbackQuery: nil
            )
        )
        let callbackResult = try await handler.handle(
            update: TelegramUpdate(
                updateID: 4,
                message: nil,
                callbackQuery: TelegramCallbackQuery(
                    id: "callback-approve-1",
                    from: TelegramUser(id: 42, isBot: false, firstName: "Alice", lastName: nil, username: "alice"),
                    message: TelegramMessage(
                        messageID: 13,
                        from: harness.telegramClient.me,
                        chat: TelegramChat(id: 42, type: .private, title: nil, username: nil, firstName: "Alice", lastName: nil),
                        date: 103,
                        text: "Ship it?"
                    ),
                    data: TelegramCallbackCodec.encode(.approval(requestID: requestID, approved: true))
                )
            )
        )
        let finished = try await server.waitForMission(missionID: started.mission.missionID, timeoutSeconds: 5)
        let sentMessages = await harness.telegramClient.sentMessagesSnapshot()

        #expect(first.assistantText?.localizedStandardContains("Pairing required") == true)
        #expect(second.assistantText == "Pairing complete. You can continue.")
        #expect(statusResult.assistantText == "Status noted.")
        #expect(callbackResult.disposition == .processed)
        #expect(finished.mission.status == .completed)
        #expect(sentMessages.contains { $0.text.localizedStandardContains("Pairing required") })
        #expect(sentMessages.contains { $0.text == "Pairing complete. You can continue." })
        #expect(sentMessages.contains { $0.text.localizedStandardContains("Ship it?") && $0.replyMarkup != nil })
        #expect(sentMessages.contains { $0.text == "Approval recorded." })
        #expect((await harness.telegramClient.answeredCallbacksSnapshot()).first?.id == "callback-approve-1")

        await harness.runtimeRegistry.closeAll()
    }

    private func makeHarness() async throws -> TelegramLiveHarness {
        let stateRoot = try makeStateRoot(prefix: "telegram-live-parity")
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.deliveriesDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let pairingStore = PairingStore(fileURL: stateRoot.runtimeDirectoryURL.appending(path: "pairings.json"))
        let adapter = TelegramLiveAdapter(responses: [telegramLiveResponse(text: "Status noted.")])
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
        let telegramClient = TelegramLiveBotClient(
            me: TelegramUser(id: 999, isBot: true, firstName: "Chief", lastName: nil, username: "chiefbot")
        )

        return TelegramLiveHarness(
            identityStore: identityStore,
            pairingStore: pairingStore,
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

private struct TelegramLiveHarness {
    let identityStore: SQLiteIdentityStore
    let pairingStore: PairingStore
    let deliveryStore: SQLiteDeliveryStore
    let jobStore: SQLiteJobStore
    let artifactStore: FileArtifactStore
    let serverRegistry: WorkspaceSessionRegistry
    let runtimeRegistry: WorkspaceRuntimeRegistry
    let gateway: IngressGateway
    let telegramClient: TelegramLiveBotClient
}
