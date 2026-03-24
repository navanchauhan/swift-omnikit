import Foundation
import OmniAgentMesh

public actor ACPExecutor {
    private nonisolated let session: ACPWorkerSession

    public init(session: ACPWorkerSession) {
        self.session = session
    }

    public func execute(
        task: TaskRecord,
        profiles: [ACPWorkerProfile],
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) async throws -> [ACPWorkerExecutionResult] {
        var results: [ACPWorkerExecutionResult] = []
        for profile in profiles {
            results.append(
                try await session.run(
                    task: task,
                    profile: profile,
                    workingDirectory: workingDirectory
                )
            )
        }
        return results
    }

    public nonisolated func makeLocalTaskExecutor(
        profile: ACPWorkerProfile,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> LocalTaskExecutor {
        let session = self.session
        return LocalTaskExecutor { task, reportProgress in
            try await reportProgress(
                "Launching \(profile.profileID) ACP session",
                ["provider": profile.provider, "profile": profile.profileID]
            )
            let result = try await session.run(
                task: task,
                profile: profile,
                workingDirectory: workingDirectory
            )
            let responsePreview = Self.responsePreview(for: result.response)
            let metadata = [
                "profile_id": result.profileID,
                "tool_servers": result.toolServerNames.joined(separator: ","),
                "response_preview": responsePreview,
            ].merging(result.contextUpdates) { current, _ in current }
            if !responsePreview.isEmpty {
                try await reportProgress(
                    "Received \(profile.profileID) ACP result preview",
                    [
                        "profile_id": result.profileID,
                        "response_preview": responsePreview,
                    ].merging(result.contextUpdates) { current, _ in current }
                )
            }
            let artifacts = [
                LocalTaskExecutionArtifact(
                    name: "\(result.profileID)-response.md",
                    contentType: "text/markdown",
                    data: Data(result.response.utf8)
                ),
                LocalTaskExecutionArtifact(
                    name: "\(result.profileID)-notes.txt",
                    contentType: "text/plain",
                    data: Data(result.notes.utf8)
                ),
            ]
            return LocalTaskExecutionResult(
                summary: Self.completionSummary(
                    profileID: profile.profileID,
                    responsePreview: responsePreview
                ),
                artifacts: artifacts,
                metadata: metadata
            )
        }
    }

    private nonisolated static func completionSummary(
        profileID: String,
        responsePreview: String
    ) -> String {
        guard !responsePreview.isEmpty else {
            return "\(profileID) ACP task completed"
        }
        return "\(profileID) ACP task completed: \(responsePreview)"
    }

    private nonisolated static func responsePreview(for response: String, limit: Int = 280) -> String {
        let collapsed = response
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else {
            return ""
        }

        guard collapsed.count > limit else {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
