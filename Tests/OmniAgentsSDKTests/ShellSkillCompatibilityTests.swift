import Foundation
import Testing
import OmniSkills
@testable import OmniAgentsSDK

@Suite
struct ShellSkillCompatibilityTests {
    @Test
    func omniSkillShellProjectionCompilesIntoShellToolLocalSkills() throws {
        let root = try makeSkillDirectory()
        let shellDirectory = root.appending(path: "shell", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shellDirectory, withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho bootstrap\n".utf8).write(to: shellDirectory.appending(path: "bootstrap.sh"))
        try Data("#!/bin/sh\necho verify\n".utf8).write(to: shellDirectory.appending(path: "verify.sh"))

        let package = OmniSkillPackage(
            manifest: OmniSkillManifest(
                skillID: "shell.helper",
                version: "1.0.0",
                displayName: "Shell Helper",
                summary: "Bootstraps and verifies shell environments.",
                projectionSurfaces: [.shellEnv],
                shellPaths: ["shell/bootstrap.sh", "shell/verify.sh"]
            ),
            rootDirectory: root,
            sourceDescription: root.path()
        )

        let projection = try OmniSkillProjectionCompiler.compile(packages: [package])
        let shellSkills = [ShellToolLocalSkill](projections: projection.shellSkills)

        #expect(shellSkills.count == 2)
        #expect(Set(shellSkills.map(\.name)) == Set(["shell.helper"]))
        #expect(Set(shellSkills.map(\.path)) == Set([
            shellDirectory.appending(path: "bootstrap.sh").path(),
            shellDirectory.appending(path: "verify.sh").path(),
        ]))
        #expect(shellSkills.allSatisfy { $0.description == "Bootstraps and verifies shell environments." })
    }

    private func makeSkillDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-shell-skill-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
