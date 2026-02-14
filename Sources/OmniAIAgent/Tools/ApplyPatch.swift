import Foundation

// MARK: - apply_patch (OpenAI v4a format)

public func applyPatchTool() -> RegisteredTool {
    RegisteredTool(
        definition: AgentToolDefinition(
            name: "apply_patch",
            description: "Apply code changes using the patch format. Supports creating, deleting, and modifying files in a single operation.",
            parameters: [
                "type": "object",
                "properties": [
                    "patch": ["type": "string", "description": "The patch content in v4a format"],
                ] as [String: Any],
                "required": ["patch"],
            ] as [String: Any]
        ),
        executor: { args, env in
            guard let patch = args["patch"] as? String else {
                throw ToolError.validationError("patch is required")
            }
            return try await applyV4aPatch(patch, env: env)
        }
    )
}

// MARK: - V4a Patch Parser and Applicator

enum PatchOperation {
    case addFile(path: String, lines: [String])
    case deleteFile(path: String)
    case updateFile(path: String, moveTo: String?, hunks: [Hunk])
}

struct Hunk {
    var contextHint: String
    var lines: [HunkLine]
}

enum HunkLine {
    case context(String)
    case delete(String)
    case add(String)
}

func parseV4aPatch(_ patch: String) throws -> [PatchOperation] {
    let lines = patch.components(separatedBy: "\n")
    var idx = 0
    var operations: [PatchOperation] = []

    // Skip to "*** Begin Patch"
    while idx < lines.count && !lines[idx].hasPrefix("*** Begin Patch") {
        idx += 1
    }
    guard idx < lines.count else {
        throw ToolError.patchError("Missing '*** Begin Patch' header")
    }
    idx += 1

    while idx < lines.count {
        let line = lines[idx]

        if line.hasPrefix("*** End Patch") {
            break
        }

        if line.hasPrefix("*** Add File: ") {
            let path = String(line.dropFirst("*** Add File: ".count))
            idx += 1
            var addedLines: [String] = []
            while idx < lines.count && !lines[idx].hasPrefix("***") {
                if lines[idx].hasPrefix("+") {
                    addedLines.append(String(lines[idx].dropFirst()))
                }
                idx += 1
            }
            operations.append(.addFile(path: path, lines: addedLines))
            continue
        }

        if line.hasPrefix("*** Delete File: ") {
            let path = String(line.dropFirst("*** Delete File: ".count))
            idx += 1
            operations.append(.deleteFile(path: path))
            continue
        }

        if line.hasPrefix("*** Update File: ") {
            let path = String(line.dropFirst("*** Update File: ".count))
            idx += 1

            var moveTo: String? = nil
            if idx < lines.count && lines[idx].hasPrefix("*** Move to: ") {
                moveTo = String(lines[idx].dropFirst("*** Move to: ".count))
                idx += 1
            }

            var hunks: [Hunk] = []
            while idx < lines.count && lines[idx].hasPrefix("@@ ") {
                let contextHint = String(lines[idx].dropFirst(3))
                idx += 1
                var hunkLines: [HunkLine] = []
                while idx < lines.count {
                    let hLine = lines[idx]
                    if hLine.hasPrefix("@@ ") || hLine.hasPrefix("***") {
                        break
                    }
                    if hLine.hasPrefix(" ") {
                        hunkLines.append(.context(String(hLine.dropFirst())))
                    } else if hLine.hasPrefix("-") {
                        hunkLines.append(.delete(String(hLine.dropFirst())))
                    } else if hLine.hasPrefix("+") {
                        hunkLines.append(.add(String(hLine.dropFirst())))
                    } else if hLine.isEmpty {
                        // Empty line treated as empty context line
                        hunkLines.append(.context(""))
                    }
                    idx += 1
                }
                hunks.append(Hunk(contextHint: contextHint, lines: hunkLines))
            }

            operations.append(.updateFile(path: path, moveTo: moveTo, hunks: hunks))
            continue
        }

        idx += 1
    }

    return operations
}

func applyV4aPatch(_ patch: String, env: ExecutionEnvironment) async throws -> String {
    let operations = try parseV4aPatch(patch)
    var results: [String] = []

    for op in operations {
        switch op {
        case .addFile(let path, let addedLines):
            let content = addedLines.joined(separator: "\n")
            try await env.writeFile(path: path, content: content)
            results.append("Created: \(path)")

        case .deleteFile(let path):
            // Delete by writing empty and then using shell to remove
            let result = try await env.execCommand(
                command: "rm -f '\(path)'",
                timeoutMs: 5000,
                workingDir: nil,
                envVars: nil
            )
            if result.exitCode == 0 {
                results.append("Deleted: \(path)")
            } else {
                results.append("Failed to delete: \(path) - \(result.stderr)")
            }

        case .updateFile(let path, let moveTo, let hunks):
            // Read existing file
            let rawContent = try await env.readFile(path: path, offset: nil, limit: nil)
            let content = stripPatchLineNumbers(rawContent)
            var fileLines = content.components(separatedBy: "\n")

            // Apply hunks in reverse order to preserve line numbers
            for hunk in hunks.reversed() {
                fileLines = try applyHunk(fileLines, hunk: hunk)
            }

            let newContent = fileLines.joined(separator: "\n")
            let targetPath = moveTo ?? path

            if let moveTo = moveTo, moveTo != path {
                // Write to new location, delete old
                try await env.writeFile(path: moveTo, content: newContent)
                _ = try await env.execCommand(
                    command: "rm -f '\(path)'",
                    timeoutMs: 5000,
                    workingDir: nil,
                    envVars: nil
                )
                results.append("Updated and moved: \(path) -> \(moveTo)")
            } else {
                try await env.writeFile(path: targetPath, content: newContent)
                results.append("Updated: \(targetPath)")
            }
        }
    }

    return results.joined(separator: "\n")
}

private func applyHunk(_ lines: [String], hunk: Hunk) throws -> [String] {
    // Find the position to apply the hunk using context lines
    let contextLines = hunk.lines.compactMap { line -> String? in
        switch line {
        case .context(let s): return s
        case .delete(let s): return s
        case .add: return nil
        }
    }

    guard !contextLines.isEmpty else {
        // No context, just append additions at end
        var result = lines
        for line in hunk.lines {
            if case .add(let s) = line {
                result.append(s)
            }
        }
        return result
    }

    // Find matching position
    var matchStart = -1
    let firstContext = contextLines[0]

    for i in 0..<lines.count {
        if lines[i].trimmingCharacters(in: .whitespaces) == firstContext.trimmingCharacters(in: .whitespaces) {
            // Verify remaining context
            var matches = true
            var lineIdx = i
            for hunkLine in hunk.lines {
                switch hunkLine {
                case .context(let s), .delete(let s):
                    if lineIdx >= lines.count ||
                       lines[lineIdx].trimmingCharacters(in: .whitespaces) != s.trimmingCharacters(in: .whitespaces) {
                        matches = false
                    }
                    lineIdx += 1
                case .add:
                    break  // additions don't consume file lines
                }
                if !matches { break }
            }
            if matches {
                matchStart = i
                break
            }
        }
    }

    // Also try matching with the context hint
    if matchStart == -1 && !hunk.contextHint.isEmpty {
        for i in 0..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces).contains(hunk.contextHint.trimmingCharacters(in: .whitespaces)) {
                matchStart = i
                break
            }
        }
    }

    guard matchStart >= 0 else {
        throw ToolError.patchError("Could not find matching context for hunk: \(hunk.contextHint)")
    }

    // Apply the hunk
    var result = Array(lines[0..<matchStart])
    var fileIdx = matchStart

    for hunkLine in hunk.lines {
        switch hunkLine {
        case .context:
            if fileIdx < lines.count {
                result.append(lines[fileIdx])
                fileIdx += 1
            }
        case .delete:
            fileIdx += 1  // Skip this line
        case .add(let s):
            result.append(s)
        }
    }

    // Append remaining lines
    result.append(contentsOf: lines[fileIdx...])

    return result
}

private func stripPatchLineNumbers(_ input: String) -> String {
    let lines = input.components(separatedBy: "\n")
    return lines.map { line in
        if let pipeIdx = line.firstIndex(of: "|") {
            let prefix = line[line.startIndex..<pipeIdx]
            if prefix.trimmingCharacters(in: .whitespaces).allSatisfy({ $0.isNumber }) {
                let afterPipe = line.index(after: pipeIdx)
                if afterPipe < line.endIndex && line[afterPipe] == " " {
                    return String(line[line.index(after: afterPipe)...])
                }
                return String(line[afterPipe...])
            }
        }
        return line
    }.joined(separator: "\n")
}
