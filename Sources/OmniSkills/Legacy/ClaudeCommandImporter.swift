import Foundation

public enum ClaudeCommandImporter {
    public static func importSkills(from workingDirectory: URL) throws -> [OmniSkillPackage] {
        let commandsDirectory = workingDirectory.appending(path: ".claude/commands", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: commandsDirectory.path()) else {
            return []
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: commandsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try files
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in
                let content = try String(contentsOf: url, encoding: .utf8)
                let skillID = url.deletingPathExtension().lastPathComponent
                let description = frontMatterValue(named: "description", in: content) ?? "Imported Claude command skill."
                let manifest = OmniSkillManifest(
                    skillID: skillID,
                    version: "legacy",
                    displayName: skillID,
                    summary: description,
                    supportedScopes: OmniSkillScope.allCases,
                    activationPolicy: .explicit,
                    projectionSurfaces: [.rootPrompt, .codergen, .acp, .attractor],
                    promptFile: "prompt.md",
                    codergenPromptFile: "prompt.md",
                    attractorPromptFile: "prompt.md"
                )
                return OmniSkillPackage(
                    manifest: manifest,
                    inlineAssets: ["prompt.md": stripFrontMatter(from: content)],
                    sourceDescription: url.path()
                )
            }
    }

    private static func frontMatterValue(named name: String, in content: String) -> String? {
        guard content.hasPrefix("---") else {
            return nil
        }
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else {
            return nil
        }
        return parts[1]
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let raw = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard raw.hasPrefix(name + ":") else {
                    return nil
                }
                return raw.dropFirst(name.count + 1).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first
    }

    private static func stripFrontMatter(from content: String) -> String {
        guard content.hasPrefix("---") else {
            return content
        }
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else {
            return content
        }
        return parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
