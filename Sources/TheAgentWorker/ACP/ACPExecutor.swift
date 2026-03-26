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
            let taskOutputDirectory = try Self.prepareTaskOutputDirectory(
                baseWorkingDirectory: workingDirectory,
                taskID: task.taskID
            )
            let executionWorkingDirectory = task.metadata["mission_kind"] == "tpu_experiment"
                ? taskOutputDirectory.path()
                : workingDirectory
            try await reportProgress(
                "Launching \(profile.profileID) ACP session",
                [
                    "provider": profile.provider,
                    "profile": profile.profileID,
                    "heartbeat_source": "acp",
                    "heartbeat_phase": "launch",
                ]
            )
            let result = try await session.run(
                task: task,
                profile: profile,
                workingDirectory: executionWorkingDirectory,
                artifactOutputDirectory: taskOutputDirectory.path(),
                repositoryWorkingDirectory: workingDirectory
            )
            let responsePreview = Self.responsePreview(for: result.response)
            let metadata = [
                "profile_id": result.profileID,
                "tool_servers": result.toolServerNames.joined(separator: ","),
                "response_preview": responsePreview,
                "task_output_directory": taskOutputDirectory.path(),
            ].merging(result.contextUpdates) { current, _ in current }
            if !responsePreview.isEmpty {
                try await reportProgress(
                    "Received \(profile.profileID) ACP result preview",
                    [
                        "profile_id": result.profileID,
                        "response_preview": responsePreview,
                        "heartbeat_source": "acp",
                        "heartbeat_phase": "result_preview",
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
            ] + (try Self.collectTaskOutputArtifacts(from: taskOutputDirectory))
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

    private nonisolated static func prepareTaskOutputDirectory(
        baseWorkingDirectory: String,
        taskID: String
    ) throws -> URL {
        let stateRootDirectory: URL
        if let configuredRoot = ProcessInfo.processInfo.environment["THE_AGENT_STATE_ROOT"],
           !configuredRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stateRootDirectory = URL(fileURLWithPath: configuredRoot, isDirectory: true)
                .appending(path: "runtime", directoryHint: .isDirectory)
                .appending(path: "acp-tasks", directoryHint: .isDirectory)
        } else {
            stateRootDirectory = URL(fileURLWithPath: baseWorkingDirectory, isDirectory: true)
                .appending(path: ".ai/the-agent/acp-tasks", directoryHint: .isDirectory)
        }
        let outputDirectory = stateRootDirectory
            .appending(path: taskID, directoryHint: .isDirectory)
            .appending(path: "outputs", directoryHint: .isDirectory)

        if FileManager.default.fileExists(atPath: outputDirectory.path()) {
            try FileManager.default.removeItem(at: outputDirectory)
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        return outputDirectory
    }

    private nonisolated static func collectTaskOutputArtifacts(from directory: URL) throws -> [LocalTaskExecutionArtifact] {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let normalizedRoot = directory.standardizedFileURL.resolvingSymlinksInPath().path

        var artifacts: [LocalTaskExecutionArtifact] = []
        while let nextURL = enumerator?.nextObject() as? URL {
            let values = try nextURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                continue
            }
            if let size = values.fileSize, size > 512 * 1_024 {
                continue
            }
            let normalizedPath = nextURL.standardizedFileURL.resolvingSymlinksInPath().path
            let rootPrefix = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
            let relativePath = if normalizedPath.hasPrefix(rootPrefix) {
                String(normalizedPath.dropFirst(rootPrefix.count))
            } else {
                nextURL.lastPathComponent
            }
            let data = try Data(contentsOf: nextURL)
            artifacts.append(
                LocalTaskExecutionArtifact(
                    name: relativePath,
                    contentType: contentType(for: nextURL.pathExtension.lowercased()),
                    data: data
                )
            )
        }

        return artifacts.sorted { $0.name < $1.name }
    }

    private nonisolated static func contentType(for pathExtension: String) -> String {
        switch pathExtension {
        case "json":
            return "application/json"
        case "md":
            return "text/markdown"
        case "txt", "log":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }
}
