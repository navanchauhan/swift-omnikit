import Foundation

public enum GeminiSkillImporter {
    public static func importSkills(from workingDirectory: URL) throws -> [OmniSkillPackage] {
        let candidateURLs = try legacySkillURLs(from: workingDirectory)
        return try candidateURLs.map { url in
            let content = try String(contentsOf: url, encoding: .utf8)
            let skillID = url.deletingPathExtension().lastPathComponent == "SKILL"
                ? url.deletingLastPathComponent().lastPathComponent
                : url.deletingPathExtension().lastPathComponent
            let manifest = OmniSkillManifest(
                skillID: skillID,
                version: "legacy",
                displayName: skillID,
                summary: "Imported Gemini-compatible skill.",
                supportedScopes: OmniSkillScope.allCases,
                activationPolicy: .explicit,
                projectionSurfaces: [.rootPrompt, .codergen, .acp, .attractor],
                promptFile: "prompt.md",
                codergenPromptFile: "prompt.md",
                attractorPromptFile: "prompt.md"
            )
            return OmniSkillPackage(
                manifest: manifest,
                inlineAssets: ["prompt.md": content.trimmingCharacters(in: .whitespacesAndNewlines)],
                sourceDescription: url.path()
            )
        }
    }

    private static func legacySkillURLs(from workingDirectory: URL) throws -> [URL] {
        let candidateDirectories = [
            workingDirectory.appending(path: ".gemini/skills", directoryHint: .isDirectory),
            workingDirectory.appending(path: "skills", directoryHint: .isDirectory),
        ]
        var urls: [URL] = []
        for directory in candidateDirectories where FileManager.default.fileExists(atPath: directory.path()) {
            let entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for entry in entries {
                if entry.pathExtension.lowercased() == "md" {
                    urls.append(entry)
                    continue
                }
                let skillURL = entry.appending(path: "SKILL.md")
                if FileManager.default.fileExists(atPath: skillURL.path()) {
                    urls.append(skillURL)
                }
            }
        }
        return urls
    }
}
