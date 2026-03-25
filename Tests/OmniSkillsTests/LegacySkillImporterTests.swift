import Foundation
import Testing
@testable import OmniSkills

@Suite
struct LegacySkillImporterTests {
    @Test
    func registryImportsLegacyClaudeAndGeminiSkills() throws {
        let workingDirectory = try makeDirectory(prefix: "legacy-skills")

        let claudeCommands = workingDirectory
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "commands", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: claudeCommands, withIntermediateDirectories: true)
        try Data(
            """
            ---
            description: Review pull requests with a strict rubric.
            ---

            Review the change and enumerate blocking findings first.
            """.utf8
        ).write(to: claudeCommands.appending(path: "review-pr.md"))

        let geminiSkillDirectory = workingDirectory
            .appending(path: ".gemini", directoryHint: .isDirectory)
            .appending(path: "skills", directoryHint: .isDirectory)
            .appending(path: "deploy-helper", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: geminiSkillDirectory, withIntermediateDirectories: true)
        try Data("Deploy safely and confirm staging health.\n".utf8)
            .write(to: geminiSkillDirectory.appending(path: "SKILL.md"))

        let packages = try OmniSkillRegistry().availablePackages(in: workingDirectory)
        let skillIDs = packages.map(\.manifest.skillID).sorted()
        let reviewPrompt = try packages
            .first(where: { $0.manifest.skillID == "review-pr" })?
            .textAsset(at: "prompt.md")
        let deployPrompt = try packages
            .first(where: { $0.manifest.skillID == "deploy-helper" })?
            .textAsset(at: "prompt.md")

        #expect(skillIDs == ["deploy-helper", "review-pr"])
        #expect(reviewPrompt?.localizedStandardContains("blocking findings first") == true)
        #expect(deployPrompt == "Deploy safely and confirm staging health.")
    }

    private func makeDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
