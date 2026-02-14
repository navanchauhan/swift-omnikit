import Foundation

// MARK: - Default Limits

public let defaultToolOutputLimits: [String: Int] = [
    "read_file": 50_000,
    "shell": 30_000,
    "grep": 20_000,
    "glob": 20_000,
    "edit_file": 10_000,
    "apply_patch": 10_000,
    "write_file": 1_000,
    "spawn_agent": 20_000,
]

public let defaultToolLineLimits: [String: Int] = [
    "shell": 256,
    "grep": 200,
    "glob": 500,
]

public let defaultTruncationModes: [String: String] = [
    "read_file": "head_tail",
    "shell": "head_tail",
    "grep": "tail",
    "glob": "tail",
    "edit_file": "tail",
    "apply_patch": "tail",
    "write_file": "tail",
    "spawn_agent": "head_tail",
]

// MARK: - Character-Based Truncation

public func truncateOutput(_ output: String, maxChars: Int, mode: String) -> String {
    guard output.count > maxChars else { return output }

    if mode == "head_tail" {
        let half = maxChars / 2
        let removed = output.count - maxChars
        let headEnd = output.index(output.startIndex, offsetBy: half)
        let tailStart = output.index(output.endIndex, offsetBy: -half)
        return String(output[output.startIndex..<headEnd])
            + "\n\n[WARNING: Tool output was truncated. "
            + "\(removed) characters were removed from the middle. "
            + "The full output is available in the event stream. "
            + "If you need to see specific parts, re-run the tool with more targeted parameters.]\n\n"
            + String(output[tailStart..<output.endIndex])
    }

    if mode == "tail" {
        let removed = output.count - maxChars
        let tailStart = output.index(output.endIndex, offsetBy: -maxChars)
        return "[WARNING: Tool output was truncated. First "
            + "\(removed) characters were removed. "
            + "The full output is available in the event stream.]\n\n"
            + String(output[tailStart..<output.endIndex])
    }

    // Default: head truncation
    let headEnd = output.index(output.startIndex, offsetBy: maxChars)
    return String(output[output.startIndex..<headEnd])
}

// MARK: - Line-Based Truncation

public func truncateLines(_ output: String, maxLines: Int) -> String {
    let lines = output.components(separatedBy: "\n")
    guard lines.count > maxLines else { return output }

    let headCount = maxLines / 2
    let tailCount = maxLines - headCount
    let omitted = lines.count - headCount - tailCount

    let head = lines[0..<headCount].joined(separator: "\n")
    let tail = lines[(lines.count - tailCount)...].joined(separator: "\n")

    return head + "\n[... \(omitted) lines omitted ...]\n" + tail
}

// MARK: - Combined Truncation Pipeline

public func truncateToolOutput(_ output: String, toolName: String, config: SessionConfig) -> String {
    let maxChars = config.toolOutputLimits[toolName] ?? defaultToolOutputLimits[toolName] ?? 50_000
    let mode = defaultTruncationModes[toolName] ?? "head_tail"

    // Step 1: Character-based truncation (always runs first)
    var result = truncateOutput(output, maxChars: maxChars, mode: mode)

    // Step 2: Line-based truncation (secondary, for readability)
    let maxLines = config.toolLineLimits[toolName] ?? defaultToolLineLimits[toolName]
    if let maxLines = maxLines {
        result = truncateLines(result, maxLines: maxLines)
    }

    return result
}
