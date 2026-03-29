import Foundation
import Testing
import OmniAgentMesh
@testable import OmniSkills

@Suite
struct OmniSkillInstallerTests {
    @Test
    func installerCopiesLocalDirectoryAndPinsDigest() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appending(path: "omniskill-installer-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = root.appending(path: "source", directoryHint: .isDirectory)
        let installs = root.appending(path: "installs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installs, withIntermediateDirectories: true)

        let manifest = OmniSkillManifest(
            skillID: "deploy.helper",
            version: "0.1.0",
            displayName: "Deploy Helper",
            summary: "Assists with deploys.",
            projectionSurfaces: [.rootPrompt, .shellEnv],
            shellPaths: ["shell/bootstrap.sh"]
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: source.appending(path: "omniskill.json"))
        let shellDirectory = source.appending(path: "shell", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shellDirectory, withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho hello\n".utf8).write(to: shellDirectory.appending(path: "bootstrap.sh"))

        let installer = OmniSkillInstaller(installsRootDirectory: installs)
        let record = try await installer.install(from: source, scope: .workspace, workspaceID: "ws-demo")

        #expect(record.skillID == "deploy.helper")
        #expect(record.scope == .workspace)
        #expect(record.workspaceID == "ws-demo")
        #expect(!record.digest.isEmpty)
        #expect(FileManager.default.fileExists(atPath: record.installedPath))
    }
}
