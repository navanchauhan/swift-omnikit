import Foundation
import Testing

@testable import OmniAIAttractor

@Suite
struct RunManifestTests {
    @Test
    func beginRunSetsRunningStateAndPID() {
        var manifest = RunManifest(
            dotPath: "/tmp/test.dot",
            backend: "agent",
            workingDirectory: "/tmp/workdir",
            logsRoot: "/tmp/logs",
            currentNode: "Plan"
        )

        manifest.beginRun(currentNode: "MergePlanReviews")

        #expect(manifest.completionState == .running)
        #expect(manifest.currentNode == "MergePlanReviews")
        #expect(manifest.pid == ProcessInfo.processInfo.processIdentifier)
    }

    @Test
    func repairAfterUnexpectedExitUsesCheckpointAndClearsPID() {
        let checkpointTime = Date(timeIntervalSince1970: 1_700_000_000)
        let checkpoint = Checkpoint(
            timestamp: checkpointTime,
            currentNode: "Postmortem",
            completedNodes: ["Start", "Postmortem"],
            nodeRetries: [:],
            nodeOutcomes: ["Postmortem": OutcomeStatus.success.rawValue],
            contextValues: [:],
            logs: []
        )

        var manifest = RunManifest(
            dotPath: "/tmp/test.dot",
            backend: "agent",
            workingDirectory: "/tmp/workdir",
            logsRoot: "/tmp/logs",
            currentNode: "MergePlanReviews",
            pid: 12345,
            createdAt: Date(timeIntervalSince1970: 1_699_999_900),
            updatedAt: Date(timeIntervalSince1970: 1_699_999_950),
            completionState: .running
        )

        manifest.repairAfterUnexpectedExit(
            checkpoint: checkpoint,
            at: Date(timeIntervalSince1970: 1_700_000_100)
        )

        #expect(manifest.completionState == .failed)
        #expect(manifest.currentNode == "Postmortem")
        #expect(manifest.pid == nil)
        #expect(manifest.updatedAt == Date(timeIntervalSince1970: 1_700_000_100))
    }
}
