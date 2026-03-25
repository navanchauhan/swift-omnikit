import Foundation
import Testing
@testable import OmniSkills

@Suite
struct OmniSkillManifestTests {
    @Test
    func manifestDecodesCanonicalFields() throws {
        let manifest = OmniSkillManifest(
            skillID: "repo.review",
            version: "1.2.3",
            displayName: "Repo Review",
            summary: "Reviews the repository for issues.",
            supportedScopes: [.workspace, .mission],
            activationPolicy: .suggested,
            projectionSurfaces: [.rootPrompt, .codergen, .acp],
            requiredCapabilities: ["filesystem", "network"],
            allowedDomains: ["github.com"],
            budgetHints: OmniSkillBudgetHints(preferredModelTier: "reviewer"),
            promptFile: "prompt.md",
            codergenPromptFile: "codergen.md"
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(OmniSkillManifest.self, from: data)

        #expect(decoded.skillID == "repo.review")
        #expect(decoded.activationPolicy == .suggested)
        #expect(decoded.supportedScopes == [.workspace, .mission])
        #expect(decoded.requiredCapabilities == ["filesystem", "network"])
        #expect(decoded.budgetHints.preferredModelTier == "reviewer")
    }
}
