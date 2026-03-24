import Foundation

public enum WorktreeIsolation: Sendable, Codable, Equatable {
    case inherited
    case dedicated(path: String)
    case ephemeral(parentPath: String)
}

public func createGitWorktreeEnvironment(
    from parentEnvironment: ExecutionEnvironment,
    agentID: String
) async throws -> ExecutionEnvironment {
    let workingDirectory = parentEnvironment.workingDirectory()
    let checkoutProbe = try await parentEnvironment.execCommand(
        command: "git rev-parse --show-toplevel",
        timeoutMs: 10_000,
        workingDir: workingDirectory,
        envVars: nil
    )

    guard checkoutProbe.exitCode == 0 else {
        let message = checkoutProbe.stderr.isEmpty ? checkoutProbe.stdout : checkoutProbe.stderr
        throw ToolError.validationError(
            "worktree isolation requires a git checkout: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        )
    }

    let repositoryRootPath = checkoutProbe.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let repositoryRoot = URL(fileURLWithPath: repositoryRootPath, isDirectory: true)
    let worktreeRoot = repositoryRoot
        .appending(path: ".ai", directoryHint: .isDirectory)
        .appending(path: "subagents", directoryHint: .isDirectory)
        .appending(path: "worktrees", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
    let worktreeURL = worktreeRoot.appending(path: agentID, directoryHint: .isDirectory)

    if FileManager.default.fileExists(atPath: worktreeURL.path()) {
        try? FileManager.default.removeItem(at: worktreeURL)
    }

    let addCommand = "git worktree add --detach \(shellQuoted(worktreeURL.path())) HEAD"
    let addResult = try await parentEnvironment.execCommand(
        command: addCommand,
        timeoutMs: 60_000,
        workingDir: workingDirectory,
        envVars: nil
    )
    guard addResult.exitCode == 0 else {
        let message = addResult.stderr.isEmpty ? addResult.stdout : addResult.stderr
        throw ToolError.validationError(
            "failed to create git worktree: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        )
    }

    return LocalExecutionEnvironment(
        workingDir: worktreeURL.path(),
        cleanupHandler: {
            let removeResult = try await parentEnvironment.execCommand(
                command: "git worktree remove --force \(shellQuoted(worktreeURL.path()))",
                timeoutMs: 60_000,
                workingDir: workingDirectory,
                envVars: nil
            )
            if removeResult.exitCode != 0 {
                let message = removeResult.stderr.isEmpty ? removeResult.stdout : removeResult.stderr
                throw ToolError.validationError(
                    "failed to remove git worktree: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
            }
        }
    )
}

private func shellQuoted(_ value: String) -> String {
    "'\(value.replacing("'", with: "'\\''"))'"
}
