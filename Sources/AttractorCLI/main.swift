import Foundation
import OmniAIAttractor
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct AttractorCLI {
    static func main() async {
        do {
            let command = try CLICommand(arguments: Array(CommandLine.arguments.dropFirst()))
            try await command.run()
        } catch let error as ExitError {
            if !error.message.isEmpty {
                fputs("Error: \(error.message)\n", stderr)
            }
            Foundation.exit(error.code)
        } catch {
            fputs("Error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private struct CLICommand {
    enum Mode {
        case run
        case validate
    }

    let mode: Mode
    let dotPath: String
    let backend: String
    let logsRoot: String?
    let workdir: String?
    let printContext: Bool
    let interactive: Bool
    let resume: Bool

    init(arguments: [String]) throws {
        guard let first = arguments.first else {
            throw ExitError(code: 2, message: usageText)
        }

        switch first {
        case "run":
            mode = .run
        case "validate":
            mode = .validate
        case "-h", "--help", "help":
            throw ExitError(code: 0, message: usageText)
        default:
            throw ExitError(code: 2, message: "Unknown command '\(first)'.\n\n\(usageText)")
        }

        var idx = 1
        var foundDotPath: String?
        var foundBackend = "agent"
        var foundLogsRoot: String?
        var foundWorkdir: String?
        var foundPrintContext = false
        var foundInteractive = false
        var foundResume = false

        while idx < arguments.count {
            let arg = arguments[idx]
            switch arg {
            case "--backend":
                idx += 1
                guard idx < arguments.count else {
                    throw ExitError(code: 2, message: "--backend requires a value")
                }
                foundBackend = arguments[idx]
            case "--logs-root":
                idx += 1
                guard idx < arguments.count else {
                    throw ExitError(code: 2, message: "--logs-root requires a value")
                }
                foundLogsRoot = arguments[idx]
            case "--workdir":
                idx += 1
                guard idx < arguments.count else {
                    throw ExitError(code: 2, message: "--workdir requires a value")
                }
                foundWorkdir = arguments[idx]
            case "--print-context":
                foundPrintContext = true
            case "--interactive":
                foundInteractive = true
            case "--resume":
                foundResume = true
            case "-h", "--help":
                throw ExitError(code: 0, message: usageText)
            default:
                if arg.hasPrefix("-") {
                    throw ExitError(code: 2, message: "Unknown option '\(arg)'")
                }
                if foundDotPath == nil {
                    foundDotPath = arg
                } else {
                    throw ExitError(code: 2, message: "Unexpected extra argument '\(arg)'")
                }
            }
            idx += 1
        }

        guard let dotPath = foundDotPath else {
            throw ExitError(code: 2, message: "Missing DOT file path.\n\n\(usageText)")
        }

        self.dotPath = dotPath
        self.backend = foundBackend
        self.logsRoot = foundLogsRoot
        self.workdir = foundWorkdir
        self.printContext = foundPrintContext
        self.interactive = foundInteractive
        self.resume = foundResume
    }

    func run() async throws {
        switch mode {
        case .validate:
            try runValidate()
        case .run:
            try await runPipeline()
        }
    }

    private func runValidate() throws {
        let dot = try String(contentsOfFile: dotPath, encoding: .utf8)
        let graph = try DOTParser.parse(dot)
        let diagnostics = PipelineValidator.validate(graph)
        if diagnostics.isEmpty {
            print("OK: \(dotPath) passed validation.")
            return
        }

        var errorCount = 0
        for diag in diagnostics {
            let level = diag.severity == .error ? "ERROR" : "WARN"
            if diag.severity == .error { errorCount += 1 }
            print("[\(level)] \(diag.rule): \(diag.message)")
            if let fix = diag.fix, !fix.isEmpty {
                print("  fix: \(fix)")
            }
        }
        if errorCount > 0 {
            throw ExitError(code: 1, message: "Validation failed with \(errorCount) error(s).")
        }
    }

    private func runPipeline() async throws {
        let dot = try String(contentsOfFile: dotPath, encoding: .utf8)

        if let workdir {
            guard FileManager.default.changeCurrentDirectoryPath(workdir) else {
                throw ExitError(code: 2, message: "Failed to set working directory to \(workdir)")
            }
        }

        let backendInstance = try makeBackend()
        let interviewer: Interviewer = interactive ? ConsoleInterviewer() : AutoApproveInterviewer()
        let logs = try resolveLogsRoot()

        let config = PipelineConfig(
            logsRoot: logs,
            backend: backendInstance,
            interviewer: interviewer
        )
        let engine = PipelineEngine(config: config)

        let result: PipelineResult
        if resume, let checkpoint = try findLatestCheckpoint() {
            fputs("[AttractorCLI] Resuming from checkpoint: \(checkpoint.currentNode ?? "?")\n", stderr)
            fputs("[AttractorCLI] Completed nodes: \(checkpoint.completedNodes.joined(separator: ", "))\n", stderr)
            result = try await engine.resume(dot: dot, checkpoint: checkpoint)
        } else {
            result = try await engine.run(dot: dot)
        }

        print("status=\(result.status.rawValue)")
        print("logs=\(result.logsRoot.path)")
        if !result.completedNodes.isEmpty {
            print("completed=\(result.completedNodes.joined(separator: ","))")
        }
        if printContext {
            let pairs = result.context.sorted { $0.key < $1.key }
            for (key, value) in pairs {
                print("context.\(key)=\(value)")
            }
        }

        if result.status == .fail {
            throw ExitError(code: 1, message: "Pipeline completed with fail status.")
        }
    }

    private func makeBackend() throws -> CodergenBackend {
        switch backend.lowercased() {
        case "mock":
            return MockCodergenBackend()
        case "cli":
            return ProviderCLICodergenBackend()
        case "codex", "codex-cli", "codex_cli":
            return CodexCLICodergenBackend()
        case "claude", "claude-code", "claude_code", "claudecode":
            return ClaudeCodeCLICodergenBackend()
        case "gemini", "gemini-cli", "gemini_cli":
            return GeminiCLICodergenBackend()
        case "llmkit":
            return LLMKitBackend()
        case "agent", "coding-agent", "coding_agent":
            return CodingAgentBackend(workingDirectory: FileManager.default.currentDirectoryPath)
        default:
            throw ExitError(
                code: 2,
                message: "Unknown backend '\(backend)'. Use one of: agent, cli, llmkit, mock"
            )
        }
    }

    private func findLatestCheckpoint() throws -> Checkpoint? {
        let baseName = URL(fileURLWithPath: dotPath).deletingPathExtension().lastPathComponent
        let runsDir = URL(fileURLWithPath: ".ai/attractor-runs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: runsDir.path) else { return nil }

        let contents = try FileManager.default.contentsOfDirectory(
            at: runsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        // Find the most recent run directory matching our dotfile name
        let matching = contents
            .filter { $0.lastPathComponent.hasPrefix(baseName) }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return aDate > bDate
            }

        for runDir in matching {
            let checkpointURL = runDir.appendingPathComponent("checkpoint.json")
            if FileManager.default.fileExists(atPath: checkpointURL.path) {
                return try Checkpoint.load(from: checkpointURL)
            }
        }
        return nil
    }

    private func resolveLogsRoot() throws -> URL {
        if let logsRoot {
            return URL(fileURLWithPath: logsRoot, isDirectory: true)
        }
        let baseName = URL(fileURLWithPath: dotPath).deletingPathExtension().lastPathComponent
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let defaultPath = ".ai/attractor-runs/\(baseName)-\(stamp)"
        return URL(fileURLWithPath: defaultPath, isDirectory: true)
    }
}

private final class MockCodergenBackend: CodergenBackend, @unchecked Sendable {
    func run(
        prompt: String,
        model: String,
        provider: String,
        reasoningEffort: String,
        context: PipelineContext
    ) async throws -> CodergenResult {
        let stage = context.getString("current_node")
        let response = """
        [mock-backend]
        stage=\(stage)
        provider=\(provider)
        model=\(model)
        reasoning=\(reasoningEffort)
        prompt_chars=\(prompt.count)
        """
        return CodergenResult(
            response: response,
            status: .success,
            notes: "mock backend success"
        )
    }
}

private final class ProviderCLICodergenBackend: CodergenBackend, @unchecked Sendable {
    private let codex = CodexCLICodergenBackend()
    private let claude = ClaudeCodeCLICodergenBackend()
    private let gemini = GeminiCLICodergenBackend()

    func run(
        prompt: String,
        model: String,
        provider: String,
        reasoningEffort: String,
        context: PipelineContext
    ) async throws -> CodergenResult {
        switch provider.lowercased() {
        case "openai":
            return try await codex.run(
                prompt: prompt,
                model: model,
                provider: provider,
                reasoningEffort: reasoningEffort,
                context: context
            )
        case "anthropic":
            return try await claude.run(
                prompt: prompt,
                model: model,
                provider: provider,
                reasoningEffort: reasoningEffort,
                context: context
            )
        case "gemini":
            return try await gemini.run(
                prompt: prompt,
                model: model,
                provider: provider,
                reasoningEffort: reasoningEffort,
                context: context
            )
        default:
            throw ExitError(
                code: 2,
                message: "CLI backend does not support provider '\(provider)'. Supported providers: openai, anthropic, gemini."
            )
        }
    }
}

private final class CodexCLICodergenBackend: CodergenBackend, @unchecked Sendable {
    func run(
        prompt: String,
        model: String,
        provider: String,
        reasoningEffort: String,
        context: PipelineContext
    ) async throws -> CodergenResult {
        let effectiveModel = resolveCodexModel(requestedModel: model, provider: provider)
        let stage = context.getString("current_node")

        let statusInstruction = stageStatusInstruction(stage: stage)

        let finalPrompt = prompt + statusInstruction
        let timeoutSeconds = resolveTimeoutSeconds(from: context)
        let response = try runCodexExec(
            prompt: finalPrompt,
            model: effectiveModel,
            timeoutSeconds: timeoutSeconds
        )
        return parseCodergenResponse(response)
    }

    private func runCodexExec(prompt: String, model: String, timeoutSeconds: Int) throws -> String {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("attractor-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "codex",
            "exec",
            "--model", model,
            "--skip-git-repo-check",
            "--yolo",
            "--output-last-message", tmpFile.path,
            "-",
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        if let data = prompt.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
            process.terminate()
            usleep(250_000)
            if process.isRunning {
                #if canImport(Darwin) || canImport(Glibc)
                _ = kill(process.processIdentifier, SIGKILL)
                #endif
            }
            throw ExitError(
                code: 1,
                message: "codex exec timed out after \(timeoutSeconds)s (model=\(model))"
            )
        }

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            throw ExitError(
                code: 1,
                message: "codex exec failed with exit \(process.terminationStatus)\n\(stdout)\n\(stderr)"
            )
        }

        if let message = try? String(contentsOf: tmpFile, encoding: .utf8),
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return message
        }

        // Fallback: return stdout if output file is unavailable.
        return stdout
    }

    private func resolveCodexModel(requestedModel: String, provider: String) -> String {
        let lower = requestedModel.lowercased()
        if lower.hasPrefix("gpt-") { return requestedModel }
        if provider.lowercased() == "openai", !requestedModel.isEmpty { return requestedModel }
        return "gpt-5.2"
    }

    private func resolveTimeoutSeconds(from context: PipelineContext) -> Int {
        if let raw = Int(context.getString("_current_node_timeout")), raw > 0 {
            return raw
        }
        if let rawEnv = ProcessInfo.processInfo.environment["ATTRACTOR_CODEX_TIMEOUT_SECONDS"],
           let envVal = Int(rawEnv), envVal > 0
        {
            return envVal
        }
        return 180
    }

    private func parseCodergenResponse(_ response: String) -> CodergenResult {
        parseCodergenResponseText(response)
    }
}

private final class ClaudeCodeCLICodergenBackend: CodergenBackend, @unchecked Sendable {
    func run(
        prompt: String,
        model: String,
        provider: String,
        reasoningEffort: String,
        context: PipelineContext
    ) async throws -> CodergenResult {
        let stage = context.getString("current_node")
        let statusInstruction = stageStatusInstruction(stage: stage)
        let finalPrompt = prompt + statusInstruction
        let timeoutSeconds = resolveTimeoutSeconds(from: context)
        let effectiveModel = resolveModel(requestedModel: model, provider: provider)
        let response = try runClaudeExec(prompt: finalPrompt, model: effectiveModel, timeoutSeconds: timeoutSeconds)
        return parseCodergenResponseText(response)
    }

    private func runClaudeExec(prompt: String, model: String, timeoutSeconds: Int) throws -> String {
        let command = ProcessInfo.processInfo.environment["ATTRACTOR_CLAUDE_CLI_BIN"] ?? "claude"
        return try runCommand(
            [
                command,
                "--print",
                "--dangerously-skip-permissions",
                "--model", model,
                prompt,
            ],
            timeoutSeconds: timeoutSeconds
        )
    }

    private func resolveModel(requestedModel: String, provider: String) -> String {
        if requestedModel.isEmpty { return "claude-opus-4-6" }
        return requestedModel
    }

    private func resolveTimeoutSeconds(from context: PipelineContext) -> Int {
        if let raw = Int(context.getString("_current_node_timeout")), raw > 0 {
            return raw
        }
        if let rawEnv = ProcessInfo.processInfo.environment["ATTRACTOR_CLAUDE_TIMEOUT_SECONDS"],
           let envVal = Int(rawEnv), envVal > 0
        {
            return envVal
        }
        return 180
    }
}

private final class GeminiCLICodergenBackend: CodergenBackend, @unchecked Sendable {
    func run(
        prompt: String,
        model: String,
        provider: String,
        reasoningEffort: String,
        context: PipelineContext
    ) async throws -> CodergenResult {
        let stage = context.getString("current_node")
        let statusInstruction = stageStatusInstruction(stage: stage)
        let finalPrompt = prompt + statusInstruction
        let timeoutSeconds = resolveTimeoutSeconds(from: context)
        let effectiveModel = resolveModel(requestedModel: model, provider: provider)
        let response = try runGeminiExec(prompt: finalPrompt, model: effectiveModel, timeoutSeconds: timeoutSeconds)
        return parseCodergenResponseText(response)
    }

    private func runGeminiExec(prompt: String, model: String, timeoutSeconds: Int) throws -> String {
        let command = ProcessInfo.processInfo.environment["ATTRACTOR_GEMINI_CLI_BIN"] ?? "gemini"
        return try runCommand(
            [
                command,
                "--prompt", prompt,
                "--model", model,
                "--yolo",
            ],
            timeoutSeconds: timeoutSeconds
        )
    }

    private func resolveModel(requestedModel: String, provider: String) -> String {
        if requestedModel.isEmpty { return "gemini-3-flash-preview" }
        return requestedModel
    }

    private func resolveTimeoutSeconds(from context: PipelineContext) -> Int {
        if let raw = Int(context.getString("_current_node_timeout")), raw > 0 {
            return raw
        }
        if let rawEnv = ProcessInfo.processInfo.environment["ATTRACTOR_GEMINI_TIMEOUT_SECONDS"],
           let envVal = Int(rawEnv), envVal > 0
        {
            return envVal
        }
        return 180
    }
}

private func stageStatusInstruction(stage: String) -> String {
    """

    ---
    Pipeline stage: \(stage)
    Execute this stage in non-interactive mode. Use shell commands and repository inspection when needed to complete real work.

    Return your normal output, but END with this exact JSON code block shape:

    ```json
    {
      "outcome": "success",
      "preferred_next_label": "",
      "context_updates": {},
      "notes": ""
    }
    ```

    Allowed outcomes: success, partial_success, retry, fail.
    """
}

private func runCommand(_ argv: [String], timeoutSeconds: Int) throws -> String {
    guard !argv.isEmpty else {
        throw ExitError(code: 1, message: "No command provided")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = argv
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
        try process.run()
    } catch {
        throw ExitError(code: 1, message: "Failed to start command '\(argv.joined(separator: " "))': \(error)")
    }

    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        process.waitUntilExit()
        group.leave()
    }
    if group.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
        process.terminate()
        usleep(250_000)
        if process.isRunning {
            #if canImport(Darwin) || canImport(Glibc)
            _ = kill(process.processIdentifier, SIGKILL)
            #endif
        }
        throw ExitError(
            code: 1,
            message: "Command timed out after \(timeoutSeconds)s: \(argv.joined(separator: " "))"
        )
    }

    let stdout = String(
        data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""
    let stderr = String(
        data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""

    guard process.terminationStatus == 0 else {
        throw ExitError(
            code: 1,
            message: "Command failed (\(process.terminationStatus)): \(argv.joined(separator: " "))\n\(stdout)\n\(stderr)"
        )
    }

    let output = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if !output.isEmpty {
        return output
    }
    let stderrOutput = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if !stderrOutput.isEmpty {
        return stderrOutput
    }
    return ""
}

private func parseCodergenResponseText(_ response: String) -> CodergenResult {
    if let jsonBlock = extractJSONStatusBlock(from: response),
       let data = jsonBlock.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
        let outcomeStr = (json["outcome"] as? String) ?? "success"
        let status = OutcomeStatus(rawValue: outcomeStr) ?? .success
        let preferredLabel = (json["preferred_next_label"] as? String) ?? ""
        let notes = (json["notes"] as? String) ?? ""

        var updates: [String: String] = [:]
        if let rawUpdates = json["context_updates"] as? [String: Any] {
            for (k, v) in rawUpdates {
                updates[k] = String(describing: v)
            }
        }

        var suggested: [String] = []
        if let rawSuggested = json["suggested_next_ids"] as? [String] {
            suggested = rawSuggested
        }

        return CodergenResult(
            response: response,
            status: status,
            contextUpdates: updates,
            preferredLabel: preferredLabel,
            suggestedNextIds: suggested,
            notes: notes
        )
    }

    // If the model omitted the status block, keep the run moving as SUCCESS but annotate it.
    return CodergenResult(
        response: response,
        status: .success,
        notes: "No JSON status block found; assumed success."
    )
}

private func extractJSONStatusBlock(from text: String) -> String? {
    let pattern = "```json\\s*\\n([\\s\\S]*?)\\n\\s*```"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }
    let nsText = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    guard let last = matches.last, last.numberOfRanges >= 2 else {
        return nil
    }
    return nsText.substring(with: last.range(at: 1))
}

private struct ExitError: Error {
    let code: Int32
    let message: String
}

private let usageText = """
AttractorCLI

Usage:
  swift run AttractorCLI validate <dotfile>
  swift run AttractorCLI run <dotfile> [--backend agent|cli|llmkit|mock] [--logs-root <path>] [--workdir <path>] [--interactive] [--print-context]
"""
