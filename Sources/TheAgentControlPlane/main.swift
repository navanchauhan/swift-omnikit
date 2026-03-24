import Foundation
import OmniAgentMesh
import TheAgentControlPlaneKit

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
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let rootServer = RootAgentServer(
            sessionID: "root",
            conversationStore: conversationStore,
            jobStore: jobStore
        )

        var meshServer: HTTPMeshServer?
        if let meshPort = options.meshPort {
            let server = HTTPMeshServer(jobStore: jobStore, host: options.meshHost, port: meshPort)
            let listeningAddress = try await server.start()
            meshServer = server
            print("TheAgentControlPlane mesh listening on \(listeningAddress.host):\(listeningAddress.port)")
        }

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
                    sessionID: rootServer.sessionID
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
            return
        }

        if meshServer != nil {
            do {
                while true {
                    try await Task.sleep(for: .seconds(86_400))
                }
            } catch is CancellationError {
                if let meshServer {
                    try? await meshServer.stop()
                }
            }
            return
        }

        let snapshot = try await rootServer.restoreState()
        print("TheAgentControlPlane ready with \(snapshot.hotContext.count) hot items and \(snapshot.unresolvedNotifications.count) unresolved notifications.")
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
    var workingDirectory: String?

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
            case "--working-directory":
                index += 1
                workingDirectory = try Self.parseValue(arguments, index: index, flag: argument)
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
