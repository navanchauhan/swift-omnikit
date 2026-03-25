import Foundation
import Testing
@testable import OmniSkills

@Suite
struct OmniSkillProjectionTests {
    @Test
    func projectionCompilerAggregatesPromptAndWorkerTools() throws {
        let manifest = OmniSkillManifest(
            skillID: "reviewer",
            version: "1.0.0",
            displayName: "Reviewer",
            summary: "Review focused skill.",
            projectionSurfaces: [.rootPrompt, .codergen, .attractor, .toolRegistry],
            requiredCapabilities: ["filesystem"],
            allowedDomains: ["github.com"],
            budgetHints: OmniSkillBudgetHints(preferredModelTier: "reviewer"),
            promptFile: "prompt.md",
            codergenPromptFile: "codergen.md",
            attractorPromptFile: "attractor.md",
            workerTools: [
                OmniSkillToolDefinition(
                    name: "review_findings",
                    description: "Return the review rubric.",
                    inlineInstruction: "Produce a strict review rubric."
                )
            ]
        )
        let package = OmniSkillPackage(
            manifest: manifest,
            inlineAssets: [
                "prompt.md": "Use a skeptical review posture.",
                "codergen.md": "Focus on review-specific coding guidance.",
                "attractor.md": "Validate review outputs before completion.",
            ],
            sourceDescription: "inline"
        )

        let projection = try OmniSkillProjectionCompiler.compile(packages: [package])

        #expect(projection.activeSkillIDs == ["reviewer"])
        #expect(projection.promptOverlay.localizedStandardContains("skeptical review posture"))
        #expect(projection.codergenOverlay.localizedStandardContains("review-specific"))
        #expect(projection.attractorOverlay.localizedStandardContains("Validate review outputs"))
        #expect(projection.workerTools.count == 1)
        #expect(projection.workerTools.first?.name == "review_findings")
        #expect(projection.requiredCapabilities == ["filesystem"])
        #expect(projection.preferredModelTier == "reviewer")
    }
}
