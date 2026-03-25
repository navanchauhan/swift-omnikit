import Foundation
import OmniAgentMesh
import TheAgentControlPlaneKit
import TheAgentWorkerKit

@main
enum TheAgentSupervisorMain {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let runOnce = arguments.contains("--once")
        let intervalSeconds = cliDoubleValue(named: "--interval-seconds", in: arguments) ?? 5
        let configuredRoot = ProcessInfo.processInfo.environment["THE_AGENT_STATE_ROOT"]
        let stateRoot = configuredRoot.map { AgentFabricStateRoot(rootDirectory: URL(fileURLWithPath: $0)) }
            ?? .workingDirectoryDefault()
        try stateRoot.prepare()
        let conversationStore = try SQLiteConversationStore(fileURL: stateRoot.conversationDatabaseURL)
        let jobStore = try SQLiteJobStore(fileURL: stateRoot.jobsDatabaseURL)
        let watchdog = TimeoutWatchdog(jobStore: jobStore)
        let supervisor = SupervisorService(
            jobStore: jobStore,
            conversationStore: conversationStore,
            watchdog: watchdog
        )

        if runOnce {
            let report = try await supervisor.reconcile(now: Date())
            print(
                "TheAgentSupervisor sweep recovered=\(report.recoveredTaskIDs.count) " +
                "stalled=\(report.stalledTasks.count) " +
                "notifications=\(report.notificationIDs.count)"
            )
            return
        }

        print("TheAgentSupervisor ready at \(stateRoot.runtimeDirectoryURL.path())")
        try await supervisor.runLoop(interval: .seconds(intervalSeconds))
    }

    private static func cliDoubleValue(named flag: String, in arguments: [String]) -> Double? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return Double(arguments[index + 1])
    }
}
