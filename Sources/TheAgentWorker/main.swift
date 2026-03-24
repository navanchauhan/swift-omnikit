import Foundation
import OmniAgentMesh
import TheAgentWorkerKit

@main
enum TheAgentWorkerMain {
    static func main() async throws {
        let options = try WorkerCLIOptions(arguments: Array(CommandLine.arguments.dropFirst()))

        let configuredRoot = ProcessInfo.processInfo.environment["THE_AGENT_STATE_ROOT"]
        let stateRoot: AgentFabricStateRoot
        if let configuredRoot {
            stateRoot = AgentFabricStateRoot(rootDirectory: URL(fileURLWithPath: configuredRoot))
        } else {
            stateRoot = .workingDirectoryDefault()
        }
        try stateRoot.prepare()

        let artifactStore = try FileArtifactStore(rootDirectory: stateRoot.artifactsDirectoryURL)
        let executionMode = try options.executionMode()
        let requestedCapabilities = options.capabilities.isEmpty
            ? defaultCapabilities(remote: options.meshURL != nil)
            : options.capabilities
        let capabilities = WorkerExecutorFactory.augmentCapabilities(requestedCapabilities, mode: executionMode)
        let executor = WorkerExecutorFactory.makeExecutor(mode: executionMode)

        let mode: String
        let transport: String
        let jobStore: any JobStore

        if let meshURL = options.meshURL {
            let remoteStore = HTTPMeshClient(baseURL: meshURL)
            try await remoteStore.ping()
            jobStore = remoteStore
            mode = "remote-http"
            transport = "http"
        } else {
            jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
            mode = "local"
            transport = "sqlite"
        }

        let worker = WorkerDaemon(
            displayName: options.displayName ?? ProcessInfo.processInfo.hostName,
            capabilities: WorkerCapabilities(capabilities),
            jobStore: jobStore,
            artifactStore: artifactStore,
            executor: executor
        )
        var workerMetadata = [
            "mode": mode,
            "transport": transport,
        ]
        for (key, value) in WorkerExecutorFactory.metadata(for: executionMode) {
            workerMetadata[key] = value
        }
        _ = try await worker.register(
            metadata: workerMetadata
        )

        if options.drainOnce {
            _ = try await worker.drainOnce()
            return
        }

        let executionDescription = WorkerExecutorFactory.startupDescription(for: executionMode)
            .map { " \($0)" } ?? ""
        if let meshURL = options.meshURL {
            print(
                "TheAgentWorker connected to \(meshURL.absoluteString) as \(worker.workerID) " +
                "with capabilities \(capabilities.joined(separator: ","))\(executionDescription)"
            )
            try await worker.runLoop(pollInterval: .milliseconds(Int64(options.pollIntervalSeconds * 1_000)))
        } else {
            print("TheAgentWorker registered as \(worker.workerID)\(executionDescription)")
        }
    }

    private static func defaultCapabilities(remote: Bool) -> [String] {
        var capabilities: [String] = []
        #if os(Linux)
        capabilities.append("linux")
        #elseif os(macOS)
        capabilities.append("macOS")
        #else
        capabilities.append("local")
        #endif

        if remote {
            capabilities.append("remote")
        } else {
            capabilities.append(contentsOf: ["local", "same-host"])
        }
        return Array(Set(capabilities)).sorted()
    }
}

private struct WorkerCLIOptions {
    var meshURL: URL?
    var capabilities: [String] = []
    var pollIntervalSeconds: Double = 1
    var displayName: String?
    var drainOnce = false
    var acpProfile: String?
    var acpModel: String?
    var acpReasoningEffort = "high"
    var acpAgentPath: String?
    var acpAgentArguments: [String] = []
    var acpModeID: String?
    var acpTimeoutSeconds: Double?
    var acpWorkingDirectory: String?

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--mesh-url":
                index += 1
                meshURL = try Self.parseURL(arguments, index: index, flag: argument)
            case "--capability":
                index += 1
                capabilities.append(try Self.parseValue(arguments, index: index, flag: argument))
            case "--poll-interval":
                index += 1
                let value = try Self.parseValue(arguments, index: index, flag: argument)
                guard let seconds = Double(value), seconds > 0 else {
                    throw WorkerCLIError.invalidValue(flag: argument, value: value)
                }
                pollIntervalSeconds = seconds
            case "--name":
                index += 1
                displayName = try Self.parseValue(arguments, index: index, flag: argument)
            case "--drain-once":
                drainOnce = true
            case "--acp-profile":
                index += 1
                acpProfile = try Self.parseValue(arguments, index: index, flag: argument)
            case "--acp-model":
                index += 1
                acpModel = try Self.parseValue(arguments, index: index, flag: argument)
            case "--acp-reasoning-effort":
                index += 1
                acpReasoningEffort = try Self.parseValue(arguments, index: index, flag: argument)
            case "--acp-agent":
                index += 1
                acpAgentPath = try Self.parseValue(arguments, index: index, flag: argument)
            case "--acp-arg":
                index += 1
                acpAgentArguments.append(try Self.parseValue(arguments, index: index, flag: argument))
            case "--acp-mode":
                index += 1
                acpModeID = try Self.parseValue(arguments, index: index, flag: argument)
            case "--acp-timeout-seconds":
                index += 1
                let value = try Self.parseValue(arguments, index: index, flag: argument)
                guard let seconds = Double(value), seconds > 0 else {
                    throw WorkerCLIError.invalidValue(flag: argument, value: value)
                }
                acpTimeoutSeconds = seconds
            case "--acp-working-directory":
                index += 1
                acpWorkingDirectory = try Self.parseValue(arguments, index: index, flag: argument)
            default:
                throw WorkerCLIError.unknownArgument(argument)
            }
            index += 1
        }
    }

    private static func parseValue(_ arguments: [String], index: Int, flag: String) throws -> String {
        guard arguments.indices.contains(index) else {
            throw WorkerCLIError.missingValue(flag)
        }
        return arguments[index]
    }

    private static func parseURL(_ arguments: [String], index: Int, flag: String) throws -> URL {
        let rawValue = try parseValue(arguments, index: index, flag: flag)
        guard let url = URL(string: rawValue) else {
            throw WorkerCLIError.invalidValue(flag: flag, value: rawValue)
        }
        return url
    }

    private var hasACPOptions: Bool {
        acpProfile != nil ||
            acpModel != nil ||
            acpAgentPath != nil ||
            !acpAgentArguments.isEmpty ||
            acpModeID != nil ||
            acpTimeoutSeconds != nil ||
            acpWorkingDirectory != nil
    }

    func executionMode() throws -> WorkerExecutionMode {
        guard hasACPOptions else {
            return .local
        }

        let profile: WorkerACPProfile
        if let acpProfile {
            guard let parsedProfile = WorkerACPProfile(cliValue: acpProfile) else {
                throw WorkerCLIError.invalidValue(flag: "--acp-profile", value: acpProfile)
            }
            profile = parsedProfile
        } else {
            profile = .codex
        }

        let timeout: Duration?
        if let acpTimeoutSeconds {
            timeout = .milliseconds(Int64(acpTimeoutSeconds * 1_000))
        } else {
            timeout = nil
        }

        return .acp(
            ACPWorkerRuntimeOptions(
                profile: profile,
                model: acpModel,
                reasoningEffort: acpReasoningEffort,
                agentPath: acpAgentPath,
                agentArguments: acpAgentArguments,
                workingDirectory: acpWorkingDirectory,
                modeID: acpModeID,
                requestTimeout: timeout
            )
        )
    }
}

private enum WorkerCLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidValue(flag: String, value: String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value '\(value)' for \(flag)."
        case .unknownArgument(let argument):
            return "Unknown argument \(argument)."
        }
    }
}
