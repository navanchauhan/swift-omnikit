import Foundation

public enum ACPBackendPreset: Sendable {
    case generic
    case codex
    case claudeCode

    public func makeConfiguration(
        overrides: ACPBackendConfiguration = ACPBackendConfiguration(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ACPBackendConfiguration {
        switch self {
        case .generic:
            return overrides
        case .codex:
            return presetConfiguration(
                defaultAgentPath: "codex-acp",
                defaultAgentArguments: [],
                environmentPrefixes: ["ATTRACTOR_CODEX_ACP"],
                overrides: overrides,
                environment: environment
            )
        case .claudeCode:
            return presetConfiguration(
                defaultAgentPath: "npx",
                defaultAgentArguments: ["-y", "@zed-industries/claude-agent-acp"],
                environmentPrefixes: ["ATTRACTOR_CLAUDE_ACP", "ATTRACTOR_CLAUDE_CODE_ACP"],
                overrides: overrides,
                environment: environment
            )
        }
    }

    private func presetConfiguration(
        defaultAgentPath: String,
        defaultAgentArguments: [String],
        environmentPrefixes: [String],
        overrides: ACPBackendConfiguration,
        environment: [String: String]
    ) -> ACPBackendConfiguration {
        let pathKeys = environmentPrefixes.map { "\($0)_AGENT_BIN" }
        let argsKeys = environmentPrefixes.map { "\($0)_AGENT_ARGS" }
        let cwdKeys = environmentPrefixes.map { "\($0)_CWD" }
        let timeoutKeys = environmentPrefixes.map { "\($0)_TIMEOUT_SECONDS" }
        let modeKeys = environmentPrefixes.map { "\($0)_MODE" }
        let extraPathKeys = environmentPrefixes.map { "\($0)_EXTRA_PATH" }

        let agentPath = acpFirstNonEmpty(
            [overrides.agentPath ?? ""] + pathKeys.compactMap { environment[$0] } + [defaultAgentPath]
        )

        let agentArguments: [String]
        if !overrides.agentArguments.isEmpty {
            agentArguments = overrides.agentArguments
        } else if let rawArgs = acpFirstEnvironmentValue(keys: argsKeys, environment: environment) {
            agentArguments = acpParseStringList(rawArgs)
        } else {
            agentArguments = defaultAgentArguments
        }

        let workingDirectory = acpOptionalNonEmpty(
            [overrides.workingDirectory ?? ""] + cwdKeys.compactMap { environment[$0] }
        )
        let timeout = overrides.requestTimeout ?? acpTimeout(from: timeoutKeys, environment: environment)
        let modeID = acpOptionalNonEmpty(
            [overrides.modeID ?? ""] + modeKeys.compactMap { environment[$0] }
        )

        var mergedEnvironment = overrides.environment
        if let extraPath = acpFirstEnvironmentValue(keys: extraPathKeys, environment: environment) {
            let currentPath = mergedEnvironment["PATH"] ?? environment["PATH"] ?? ""
            mergedEnvironment["PATH"] = extraPath + (currentPath.isEmpty ? "" : ":" + currentPath)
        }

        return ACPBackendConfiguration(
            agentPath: agentPath,
            agentArguments: agentArguments,
            workingDirectory: workingDirectory,
            environment: mergedEnvironment,
            requestTimeout: timeout,
            modeID: modeID
        )
    }
}

private func acpParseStringList(_ raw: String) -> [String] {
    guard !raw.isEmpty else { return [] }
    if raw.hasPrefix("[") && raw.hasSuffix("]"),
       let data = raw.data(using: .utf8),
       let list = try? JSONSerialization.jsonObject(with: data) as? [String] {
        return list
    }
    return raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func acpTimeout(from keys: [String], environment: [String: String]) -> Duration? {
    guard let rawValue = acpFirstEnvironmentValue(keys: keys, environment: environment),
          let seconds = Double(rawValue),
          seconds > 0 else {
        return nil
    }
    return .milliseconds(Int64(seconds * 1_000))
}

private func acpFirstEnvironmentValue(keys: [String], environment: [String: String]) -> String? {
    acpOptionalNonEmpty(keys.compactMap { environment[$0] })
}

private func acpOptionalNonEmpty(_ values: [String]) -> String? {
    let value = acpFirstNonEmpty(values)
    return value.isEmpty ? nil : value
}

private func acpFirstNonEmpty(_ values: [String]) -> String {
    values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}
