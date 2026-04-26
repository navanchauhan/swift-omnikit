import Foundation
import OmniAgentDeliveryCore
import OmniAgentMesh
import OmniAIAgent
import TheAgentControlPlaneKit
import TheAgentIngress
import TheAgentTelegram
import TheAgentImessage

/// Concurrency-safe stderr writer for use in Sendable closures and Tasks.
private struct StderrWriter: Sendable {
    func write(_ message: String) {
        let standardError = FileHandle.standardError
        standardError.write(Data(message.utf8))
    }
}

private let stderrWriter = StderrWriter()

private actor CodexMediaDescriptionProvider: MediaDescriptionProviding {
    func describeImageAttachment(_ attachment: StagedAttachment) async throws -> String? {
        guard let localPath = attachment.localPath else {
            return nil
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: localPath))
        return try await RootAgentToolbox.describeImage(
            data: data,
            contentType: attachment.contentType,
            name: attachment.name
        )
    }
}

@main
enum TheAgentControlPlaneMain {
    static func main() async throws {
        let options = try ControlPlaneCLIOptions(arguments: Array(CommandLine.arguments.dropFirst()))

        let configuredRoot = ProcessInfo.processInfo.environment["THE_AGENT_STATE_ROOT"]
        let stateRoot: AgentFabricStateRoot
        if let configuredRoot {
            stateRoot = AgentFabricStateRoot(rootDirectory: URL(fileURLWithPath: configuredRoot))
        } else {
            stateRoot = .workingDirectoryDefault()
        }
        try stateRoot.prepare()

        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let identityStore = try SQLiteIdentityStore(fileURL: stateRoot.identityDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let missionStore = try SQLiteMissionStore(fileURL: stateRoot.missionsDatabaseURL)
        let skillStore = try SQLiteSkillStore(fileURL: stateRoot.skillsDatabaseURL)
        let deliveryStore = try SQLiteDeliveryStore(fileURL: stateRoot.deliveriesDatabaseURL)
        let deploymentStore = try SQLiteDeploymentStore(fileURL: stateRoot.deploymentDatabaseURL)
        let scheduledPromptStore = FileScheduledPromptStore(
            fileURL: stateRoot.runtimeDirectoryURL.appending(path: "scheduled-prompts.json")
        )
        let artifactStore = try FileArtifactStore(
            rootDirectory: stateRoot.artifactsDirectoryURL,
            maximumArtifactBytes: 50 * 1_024 * 1_024
        )
        let releaseBundleStore = try FileReleaseBundleStore(
            rootDirectory: stateRoot.releasesDirectoryURL.appending(path: "bundles", directoryHint: .isDirectory)
        )
        let deployHealthService = DeployHealthService { release in
            let workers = (try? await jobStore.workers()) ?? []
            let now = Date()
            let freshWorkers = workers.filter { now.timeIntervalSince($0.lastHeartbeatAt) <= 120 && $0.state != .drained }
            let healthy = !freshWorkers.isEmpty
            return DeployHealthOutcome(
                status: healthy ? .healthy : .unhealthy,
                summary: healthy
                    ? "canary health check passed with \(freshWorkers.count) fresh worker(s)"
                    : "no fresh workers were available during canary verification",
                metadata: [
                    "fresh_worker_count": String(freshWorkers.count),
                    "service": release.service ?? "unspecified",
                    "target_environment": release.targetEnvironment ?? "unspecified",
                ]
            )
        }
        let releaseController = ReleaseController(
            deploymentStore: deploymentStore,
            supervisor: Supervisor(releasesDirectory: stateRoot.releasesDirectoryURL),
            healthService: deployHealthService
        )
        let pairingStore = PairingStore(fileURL: stateRoot.runtimeDirectoryURL.appending(path: "pairings.json"))
        let channelPolicyManager = ChannelPolicyManager(
            identityStore: identityStore,
            pairingStore: pairingStore
        )
        let onboardingWizard = OnboardingWizard(policyManager: channelPolicyManager)
        let attachmentStager = AttachmentStager(artifactStore: artifactStore)
        _ = try await SessionScopeBootstrapper(
            identityStore: identityStore,
            conversationStore: conversationStore,
            jobStore: jobStore
        ).bootstrap()
        try await PolicyBootstrapper.applyEnvironmentOverrides(identityStore: identityStore)
        let serverRegistry = WorkspaceSessionRegistry(
            stateRoot: stateRoot,
            identityStore: identityStore,
            conversationStore: conversationStore,
            jobStore: jobStore,
            missionStore: missionStore,
            skillStore: skillStore,
            artifactStore: artifactStore,
            deliveryStore: deliveryStore,
            pairingStore: pairingStore,
            releaseBundleStore: releaseBundleStore,
            releaseController: releaseController
        )
        let runtimeRegistry = WorkspaceRuntimeRegistry(
            serverRegistry: serverRegistry,
            stateRoot: stateRoot,
            runtimeOptions: RootAgentRuntimeOptions(
                provider: options.provider,
                model: options.model,
                workingDirectory: options.workingDirectory,
                sessionConfig: SessionConfig(reasoningEffort: options.reasoningEffort),
                enableNativeWebSearch: true,
                yoloMode: options.yoloMode
            )
        )
        let gateway = IngressGateway(
            identityStore: identityStore,
            deliveryStore: deliveryStore,
            missionStore: missionStore,
            runtimeRegistry: runtimeRegistry,
            policyManager: channelPolicyManager,
            onboardingWizard: onboardingWizard,
            attachmentStager: attachmentStager,
            mediaDescriptionProvider: CodexMediaDescriptionProvider()
        )
        let rootServer = await serverRegistry.server(sessionID: "root")
        let interactionBridge = MeshInteractionBridgeService(
            serverRegistry: serverRegistry,
            missionStore: missionStore
        )
        var supervisorTask: Task<Void, Never>?
        var scheduledPromptTask: Task<Void, Never>?

        var meshServer: HTTPMeshServer?
        if let meshPort = options.meshPort {
            let server = HTTPMeshServer(
                jobStore: jobStore,
                artifactStore: artifactStore,
                interactionBridge: interactionBridge,
                host: options.meshHost,
                port: meshPort
            )
            let listeningAddress = try await server.start()
            meshServer = server
            print("TheAgentControlPlane mesh listening on \(listeningAddress.host):\(listeningAddress.port)")
        }

        let telegramBotToken = options.telegramBotToken ?? ProcessInfo.processInfo.environment["THE_AGENT_TELEGRAM_BOT_TOKEN"]
        var telegramWebhookHandler: TelegramWebhookHandler?
        var telegramPollingTask: Task<Void, Never>?
        if let telegramBotToken, !telegramBotToken.isEmpty {
            let telegramClient = TelegramBotClient(token: telegramBotToken)
            let handler = try await TelegramWebhookHandler.make(
                client: telegramClient,
                gateway: gateway,
                deliveryStore: deliveryStore,
                expectedSecretToken: options.telegramWebhookSecret
            )
            telegramWebhookHandler = handler

            if let webhookURL = options.telegramWebhookURL, !webhookURL.isEmpty {
                try await telegramClient.setWebhook(
                    url: webhookURL,
                    secretToken: options.telegramWebhookSecret,
                    allowedUpdates: await handler.allowedUpdates()
                )
                print("TheAgentControlPlane telegram webhook configured for \(webhookURL)")
            }

            if options.telegramPollingEnabled {
                try await telegramClient.deleteWebhook(dropPendingUpdates: false)
                let runner = TelegramPollingRunner(
                    client: telegramClient,
                    webhookHandler: handler,
                    allowedUpdates: await handler.allowedUpdates(),
                    onError: { error in
                        stderrWriter.write("Telegram polling error: \(error)\n")
                    }
                )
                telegramPollingTask = Task {
                    do {
                        try await runner.run(
                            timeoutSeconds: options.telegramPollTimeoutSeconds,
                            limit: options.telegramPollLimit
                        )
                    } catch is CancellationError {
                    } catch {
                        stderrWriter.write("Telegram polling stopped: \(error)\n")
                    }
                }
                print("TheAgentControlPlane telegram polling enabled.")
            }
        }

        let photonProjectID = options.photonProjectID
            ?? ProcessInfo.processInfo.environment["PHOTON_PROJECT_ID"]
        let photonProjectSecret = options.photonProjectSecret
            ?? ProcessInfo.processInfo.environment["PHOTON_PROJECT_SECRET"]
            ?? ProcessInfo.processInfo.environment["PHOTON_SECRET_KEY"]
            ?? ProcessInfo.processInfo.environment["PHOTON_PROJECT_SECRET_KEY"]
        var imessageIngressHandler: ImessageIngressHandler?
        var imessageIngressTask: Task<Void, Never>?

        if let photonProjectID,
           let photonProjectSecret,
           !photonProjectID.isEmpty,
           !photonProjectSecret.isEmpty {
            do {
                let handler = try await ImessageIngressHandler.make(
                    gateway: gateway,
                    deliveryStore: deliveryStore,
                    artifactStore: artifactStore,
                    projectID: photonProjectID,
                    projectSecret: photonProjectSecret
                )
                imessageIngressHandler = handler
                imessageIngressTask = Task {
                    do {
                        try await handler.run()
                    } catch is CancellationError {
                    } catch {
                        stderrWriter.write("iMessage stream failed: \(error)\n")
                    }
                }
                print("TheAgentControlPlane iMessage listener connected for project \(photonProjectID).")
            } catch {
                stderrWriter.write("TheAgentControlPlane iMessage listener failed: \(error)\n")
            }
        } else if options.photonProjectID != nil || options.photonProjectSecret != nil {
            stderrWriter.write("TheAgentControlPlane iMessage listener not started: both project ID and secret are required.\n")
        }

        var ingressServer: HTTPIngressServer?
        if let ingressPort = options.httpIngressPort {
            let telegramWebhookForwarder: HTTPIngressServer.TelegramWebhookForwarder?
            if let handler = telegramWebhookHandler {
                telegramWebhookForwarder = { body, headers in
                    _ = try? await handler.handle(
                        body: body,
                        providedSecretToken: headers["x-telegram-bot-api-secret-token"]
                    )
                }
            } else {
                telegramWebhookForwarder = nil
            }
            let server = HTTPIngressServer(
                gateway: gateway,
                runtimeRegistry: runtimeRegistry,
                deliveryStore: deliveryStore,
                expectedBearerToken: options.httpIngressBearerToken,
                telegramWebhookForwarder: telegramWebhookForwarder,
                host: options.httpIngressHost,
                port: ingressPort
            )
            let listeningAddress = try await server.start()
            ingressServer = server
            print("TheAgentControlPlane ingress listening on \(listeningAddress.host):\(listeningAddress.port)")
        }

        let scheduledTelegramHandler = telegramWebhookHandler
        let scheduledImessageHandler = imessageIngressHandler
        let scheduledRunner = ScheduledPromptRunner(
            store: scheduledPromptStore,
            gateway: gateway,
            deliverySink: { instructions in
                let grouped = Dictionary(grouping: instructions, by: \.transport)
                for (transport, transportInstructions) in grouped {
                    switch transport {
                    case .telegram:
                        if let scheduledTelegramHandler {
                            try await scheduledTelegramHandler.deliver(transportInstructions)
                        } else {
                            try await markScheduledDeliveriesUndeliverable(
                                transportInstructions,
                                deliveryStore: deliveryStore,
                                reason: "telegram delivery handler is not configured"
                            )
                        }
                    case .imessage:
                        if let scheduledImessageHandler {
                            try await scheduledImessageHandler.deliver(transportInstructions)
                        } else {
                            try await markScheduledDeliveriesUndeliverable(
                                transportInstructions,
                                deliveryStore: deliveryStore,
                                reason: "imessage delivery handler is not configured"
                            )
                        }
                    default:
                        try await markScheduledDeliveriesUndeliverable(
                            transportInstructions,
                            deliveryStore: deliveryStore,
                            reason: "no scheduled delivery handler for \(transport.rawValue)"
                        )
                    }
                }
            }
        )
        scheduledPromptTask = Task {
            do {
                try await scheduledRunner.run()
            } catch is CancellationError {
            } catch {
                stderrWriter.write("Scheduled prompt loop stopped: \(error)\n")
            }
        }
        print("TheAgentControlPlane scheduled prompt runner enabled.")

        if options.listWorkers {
            try await printWorkers(jobStore: jobStore)
        }

        if let prompt = options.promptText {
            let runtime = try await RootAgentRuntime.make(
                server: rootServer,
                stateRoot: stateRoot,
                options: RootAgentRuntimeOptions(
                    provider: options.provider,
                    model: options.model,
                    workingDirectory: options.workingDirectory,
                    sessionID: rootServer.sessionID,
                    sessionConfig: SessionConfig(reasoningEffort: options.reasoningEffort),
                    enableNativeWebSearch: true,
                    yoloMode: options.yoloMode
                )
            )
            let result = try await runtime.submitUserText(prompt)
            if result.assistantText.isEmpty {
                print("Root agent completed without a final text response.")
            } else {
                print(result.assistantText)
            }
            await runtime.close()

            if let meshServer {
                try await meshServer.stop()
            }
            if let ingressServer {
                try await ingressServer.stop()
            }
            telegramPollingTask?.cancel()
            imessageIngressTask?.cancel()
            await imessageIngressHandler?.close()
            scheduledPromptTask?.cancel()
            supervisorTask?.cancel()
            await runtimeRegistry.closeAll()
            return
        }

        if let brief = options.delegateBrief {
            let task = try await rootServer.delegateTask(
                brief: brief,
                capabilityRequirements: options.capabilities
            )
            print("Submitted task \(task.taskID) with requirements \(options.capabilities.joined(separator: ","))")

            if let waitSeconds = options.waitSeconds {
                try await waitForTask(taskID: task.taskID, timeoutSeconds: waitSeconds, jobStore: jobStore)
            }

            if let meshServer {
                try await meshServer.stop()
            }
            if let ingressServer {
                try await ingressServer.stop()
            }
            telegramPollingTask?.cancel()
            imessageIngressTask?.cancel()
            await imessageIngressHandler?.close()
            scheduledPromptTask?.cancel()
            supervisorTask?.cancel()
            await runtimeRegistry.closeAll()
            return
        }

        if meshServer != nil || ingressServer != nil || telegramPollingTask != nil || imessageIngressTask != nil {
            supervisorTask = Task {
                do {
                    while !Task.isCancelled {
                        _ = try await rootServer.runSupervisorSweep(now: Date())
                        try await Task.sleep(for: .seconds(5))
                    }
                } catch is CancellationError {
                } catch {
                    stderrWriter.write("Supervisor loop stopped: \(error)\n")
                }
            }
            do {
                while true {
                    try await Task.sleep(for: .seconds(86_400))
                }
            } catch is CancellationError {
                if let meshServer {
                    try? await meshServer.stop()
                }
                if let ingressServer {
                    try? await ingressServer.stop()
                }
                telegramPollingTask?.cancel()
                imessageIngressTask?.cancel()
                await imessageIngressHandler?.close()
                scheduledPromptTask?.cancel()
                supervisorTask?.cancel()
            }
            await runtimeRegistry.closeAll()
            return
        }

        let snapshot = try await rootServer.restoreState()
        print("TheAgentControlPlane ready with \(snapshot.hotContext.count) hot items and \(snapshot.unresolvedNotifications.count) unresolved notifications.")
        scheduledPromptTask?.cancel()
    }

    private static func printWorkers(jobStore: any JobStore) async throws {
        let workers = try await jobStore.workers()
        if workers.isEmpty {
            print("No registered workers.")
            return
        }

        for worker in workers {
            print(
                "\(worker.workerID) \(worker.displayName) " +
                "state=\(worker.state.rawValue) " +
                "capabilities=\(worker.capabilities.joined(separator: ","))"
            )
        }
    }

    private static func markScheduledDeliveriesUndeliverable(
        _ instructions: [IngressDeliveryInstruction],
        deliveryStore: any DeliveryStore,
        reason: String
    ) async throws {
        for instruction in instructions {
            var metadata = instruction.metadata
            metadata["target_external_id"] = instruction.targetExternalID
            metadata["error"] = reason
            _ = try await deliveryStore.saveDelivery(
                DeliveryRecord(
                    idempotencyKey: instruction.idempotencyKey,
                    direction: .outbound,
                    transport: instruction.transport,
                    actorID: instruction.actorID,
                    workspaceID: instruction.workspaceID,
                    channelID: instruction.channelID,
                    status: .failed,
                    summary: instruction.chunks.joined(separator: "\n"),
                    metadata: metadata
                )
            )
        }
    }

    private static func waitForTask(
        taskID: String,
        timeoutSeconds: Double,
        jobStore: any JobStore
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastSequence: Int?

        while Date() < deadline {
            let events = try await jobStore.events(taskID: taskID, afterSequence: lastSequence)
            for event in events {
                lastSequence = event.sequenceNumber
                print("[\(event.kind.rawValue)] \(event.summary ?? "")")
            }

            if let task = try await jobStore.task(taskID: taskID),
               task.status.isTerminal {
                print("Task \(task.taskID) finished with status \(task.status.rawValue)")
                return
            }

            try await Task.sleep(for: .milliseconds(250))
        }

        throw ControlPlaneCLIError.timeout(taskID: taskID, seconds: timeoutSeconds)
    }
}

private struct ControlPlaneCLIOptions {
    var meshHost = "0.0.0.0"
    var meshPort: Int?
    var delegateBrief: String?
    var promptText: String?
    var capabilities: [String] = []
    var waitSeconds: Double?
    var listWorkers = false
    var provider: RootAgentProvider = .openai
    var model: String?
    var reasoningEffort: String?
    var yoloMode = false
    var workingDirectory: String?
    var httpIngressHost = "127.0.0.1"
    var httpIngressPort: Int?
    var httpIngressBearerToken: String?
    var telegramBotToken: String?
    var telegramWebhookURL: String?
    var telegramWebhookSecret: String?
    var telegramPollingEnabled = false
    var telegramPollTimeoutSeconds = 1
    var telegramPollLimit = 100
    var photonProjectID: String?
    var photonProjectSecret: String?

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--mesh-host":
                index += 1
                meshHost = try Self.parseValue(arguments, index: index, flag: argument)
            case "--mesh-port":
                index += 1
                let value = try Self.parseValue(arguments, index: index, flag: argument)
                guard let port = Int(value), port >= 0 else {
                    throw ControlPlaneCLIError.invalidValue(flag: argument, value: value)
                }
                meshPort = port
            case "--delegate":
                index += 1
                delegateBrief = try Self.parseValue(arguments, index: index, flag: argument)
            case "--prompt":
                index += 1
                promptText = try Self.parseValue(arguments, index: index, flag: argument)
            case "--capability":
                index += 1
                capabilities.append(try Self.parseValue(arguments, index: index, flag: argument))
            case "--wait-seconds":
                index += 1
                let value = try Self.parseValue(arguments, index: index, flag: argument)
                guard let seconds = Double(value), seconds > 0 else {
                    throw ControlPlaneCLIError.invalidValue(flag: argument, value: value)
                }
                waitSeconds = seconds
            case "--provider":
                index += 1
                let value = try Self.parseValue(arguments, index: index, flag: argument)
                guard let provider = RootAgentProvider(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
                    throw ControlPlaneCLIError.invalidValue(flag: argument, value: value)
                }
                self.provider = provider
            case "--model":
                index += 1
                model = try Self.parseValue(arguments, index: index, flag: argument)
            case "--reasoning-effort":
                index += 1
                reasoningEffort = try Self.parseValue(arguments, index: index, flag: argument)
            case "--yolo":
                yoloMode = true
            case "--working-directory":
                index += 1
                workingDirectory = try Self.parseValue(arguments, index: index, flag: argument)
            case "--http-ingress-host":
                index += 1
                httpIngressHost = try Self.parseValue(arguments, index: index, flag: argument)
            case "--http-ingress-port":
                index += 1
                let value = try Self.parseValue(arguments, index: index, flag: argument)
                guard let port = Int(value), port >= 0 else {
                    throw ControlPlaneCLIError.invalidValue(flag: argument, value: value)
                }
                httpIngressPort = port
            case "--http-ingress-bearer-token":
                index += 1
                httpIngressBearerToken = try Self.parseValue(arguments, index: index, flag: argument)
            case "--telegram-bot-token":
                index += 1
                telegramBotToken = try Self.parseValue(arguments, index: index, flag: argument)
            case "--telegram-webhook-url":
                index += 1
                telegramWebhookURL = try Self.parseValue(arguments, index: index, flag: argument)
            case "--telegram-webhook-secret":
                index += 1
                telegramWebhookSecret = try Self.parseValue(arguments, index: index, flag: argument)
            case "--telegram-polling":
                telegramPollingEnabled = true
            case "--telegram-poll-timeout-seconds":
                index += 1
                let value = try Self.parseValue(arguments, index: index, flag: argument)
                guard let seconds = Int(value), seconds >= 0 else {
                    throw ControlPlaneCLIError.invalidValue(flag: argument, value: value)
                }
                telegramPollTimeoutSeconds = seconds
            case "--telegram-poll-limit":
                index += 1
                let value = try Self.parseValue(arguments, index: index, flag: argument)
                guard let limit = Int(value), limit > 0 else {
                    throw ControlPlaneCLIError.invalidValue(flag: argument, value: value)
                }
                telegramPollLimit = limit
            case "--photon-project-id":
                index += 1
                photonProjectID = try Self.parseValue(arguments, index: index, flag: argument)
            case "--photon-project-secret":
                index += 1
                photonProjectSecret = try Self.parseValue(arguments, index: index, flag: argument)
            case "--list-workers":
                listWorkers = true
            default:
                throw ControlPlaneCLIError.unknownArgument(argument)
            }
            index += 1
        }

        let primaryActions = [delegateBrief != nil, promptText != nil].filter { $0 }
        if primaryActions.count > 1 {
            throw ControlPlaneCLIError.conflictingActions(["--delegate", "--prompt"])
        }
    }

    private static func parseValue(_ arguments: [String], index: Int, flag: String) throws -> String {
        guard arguments.indices.contains(index) else {
            throw ControlPlaneCLIError.missingValue(flag)
        }
        return arguments[index]
    }
}

private enum ControlPlaneCLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidValue(flag: String, value: String)
    case unknownArgument(String)
    case conflictingActions([String])
    case timeout(taskID: String, seconds: Double)

    var description: String {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value '\(value)' for \(flag)."
        case .unknownArgument(let argument):
            return "Unknown argument \(argument)."
        case .conflictingActions(let flags):
            return "Options \(flags.joined(separator: ", ")) cannot be used together."
        case .timeout(let taskID, let seconds):
            return "Timed out waiting \(seconds) seconds for task \(taskID)."
        }
    }
}

private extension TaskRecord.Status {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .submitted, .waiting, .assigned, .running:
            return false
        }
    }
}
