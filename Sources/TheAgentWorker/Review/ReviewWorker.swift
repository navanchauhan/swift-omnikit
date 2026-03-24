import Foundation
import OmniAgentMesh

public struct ReviewVerdict: Sendable, Equatable {
    public var approved: Bool
    public var findings: [String]

    public init(approved: Bool, findings: [String] = []) {
        self.approved = approved
        self.findings = findings
    }
}

public struct ReviewWorker: Sendable {
    public var blockedPatterns: [String]

    public init(blockedPatterns: [String] = ["TODO", "FIXME", "fatalError(", "try!"]) {
        self.blockedPatterns = blockedPatterns
    }

    public func evaluate(
        task: TaskRecord,
        artifactStore: any ArtifactStore
    ) async throws -> ReviewVerdict {
        let artifactRefs = Array(Set(task.artifactRefs + task.historyProjection.artifactRefs)).sorted()
        guard !artifactRefs.isEmpty else {
            return ReviewVerdict(approved: true, findings: ["No implementation artifacts supplied for review."])
        }

        var findings: [String] = []
        for artifactRef in artifactRefs {
            guard let data = try await artifactStore.data(for: artifactRef),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            for pattern in blockedPatterns where text.localizedStandardContains(pattern) {
                findings.append("Artifact \(artifactRef) contains blocked pattern '\(pattern)'.")
            }
        }
        return ReviewVerdict(approved: findings.isEmpty, findings: findings)
    }

    public func makeExecutor(artifactStore: any ArtifactStore) -> LocalTaskExecutor {
        let worker = self
        return LocalTaskExecutor { task, reportProgress in
            try await reportProgress("Reviewing implementation artifacts", ["task_id": task.taskID])
            let verdict = try await worker.evaluate(task: task, artifactStore: artifactStore)
            let report = [
                verdict.approved ? "APPROVED" : "REJECTED",
                verdict.findings.joined(separator: "\n"),
            ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return LocalTaskExecutionResult(
                summary: verdict.approved
                    ? "APPROVED: automated review found no blocking issues."
                    : "REJECTED: " + verdict.findings.joined(separator: " "),
                artifacts: [
                    LocalTaskExecutionArtifact(
                        name: "review-report.txt",
                        contentType: "text/plain",
                        data: Data(report.utf8)
                    ),
                ],
                metadata: ["approved": verdict.approved ? "true" : "false"]
            )
        }
    }

    public func isApproved(summary: String) -> Bool {
        summary.hasPrefix("APPROVED:")
    }
}
