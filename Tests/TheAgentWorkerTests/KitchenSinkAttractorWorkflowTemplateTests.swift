import Foundation
import Testing
@testable import TheAgentWorkerKit

@Suite("KitchenSinkAttractorWorkflowTemplate")
struct KitchenSinkAttractorWorkflowTemplateTests {

    @Test func generatesValidDOTForEachWave() {
        let template = KitchenSinkAttractorWorkflowTemplate()
        for wave in KitchenSinkWave.allWaves {
            let dot = template.dot(for: wave)
            #expect(dot.contains("digraph kitchensink_"))
            #expect(dot.contains("start"))
            #expect(dot.contains("plan"))
            #expect(dot.contains("critique"))
            #expect(dot.contains("implement"))
            #expect(dot.contains("validate"))
            #expect(dot.contains("postmortem"))
            #expect(dot.contains("done"))
            #expect(dot.contains("start -> plan -> critique -> implement -> validate -> postmortem -> done"))
            #expect(dot.contains("validate -> implement"))
        }
    }

    @Test func dotIncludesWaveSpecificContent() {
        let template = KitchenSinkAttractorWorkflowTemplate()
        let dot = template.dot(for: .wave01)
        #expect(dot.contains("wave_01"))
        #expect(dot.contains("Shapes"))
        #expect(dot.contains("Primitives.swift"))
        #expect(dot.contains("wave01_shapes"))
    }

    @Test func allWavesManifestIsComplete() {
        let waves = KitchenSinkWave.allWaves
        #expect(waves.count == 6)
        #expect(waves[0].id == "wave-00")
        #expect(waves[5].id == "wave-05")
        for wave in waves {
            #expect(!wave.features.isEmpty)
            #expect(!wave.ownedFiles.isEmpty)
            #expect(!wave.targetedTestCases.isEmpty)
            #expect(!wave.expectedArtifacts.isEmpty)
        }
    }
}
