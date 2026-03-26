import Foundation
import Testing
@testable import OmniSkills

@Suite
struct BuiltinTPUSkillTests {
    @Test
    func builtinTPUSkillResolvesFromRepositorySkillsDirectory() throws {
        let registry = OmniSkillRegistry()
        let packages = try registry.availablePackages(in: repositoryRoot())
        let package = try #require(packages.first(where: { $0.manifest.skillID == "tpu.exps" }))
        let projection = try OmniSkillProjectionCompiler.compile(packages: [package])

        #expect(package.manifest.displayName == "TPU Experiments")
        #expect(package.manifest.activationPolicy == .suggested)
        #expect(projection.activeSkillIDs == ["tpu.exps"])
        #expect(projection.workerTools.count == 5)
        #expect(projection.workerTools.map(\.name).contains("inspect_status"))
        #expect(projection.promptOverlay.localizedStandardContains("sample_token_mae = 0.28073"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
