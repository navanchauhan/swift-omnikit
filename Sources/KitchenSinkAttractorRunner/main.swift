import Foundation
import TheAgentWorkerKit

@main
enum KitchenSinkAttractorRunnerMain {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            print("Usage: KitchenSinkAttractorRunner <wave-id> [--list]")
            print("  wave-id: wave-00, wave-01, ..., wave-05, or 'all'")
            print("  --list:  list available waves")
            Foundation.exit(1)
        }

        if args[1] == "--list" {
            for wave in KitchenSinkWave.allWaves {
                print("\(wave.id): \(wave.title)")
                print("  Features: \(wave.features.joined(separator: ", "))")
                print("  Files: \(wave.ownedFiles.joined(separator: ", "))")
                print("  Tests: \(wave.targetedTestCases.joined(separator: ", "))")
                print()
            }
            return
        }

        let waveID = args[1]
        let waves: [KitchenSinkWave]

        if waveID == "all" {
            waves = KitchenSinkWave.allWaves
        } else if let wave = KitchenSinkWave.allWaves.first(where: { $0.id == waveID }) {
            waves = [wave]
        } else {
            print("Unknown wave: \(waveID)")
            print("Available: \(KitchenSinkWave.allWaves.map(\.id).joined(separator: ", "))")
            Foundation.exit(1)
        }

        let template = KitchenSinkAttractorWorkflowTemplate()

        for wave in waves {
            print("=== \(wave.id): \(wave.title) ===")
            let dot = template.dot(for: wave)
            print(dot)
            print()
            // In a full execution context, this would create a TaskRecord
            // and run through AttractorTaskExecutor. For now, emit the DOT
            // for external execution.
        }
    }
}
