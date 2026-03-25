import Foundation
import OmniAIAttractor

struct RecordedCodergenCall: Sendable, Equatable {
    var prompt: String
    var model: String
    var provider: String
    var reasoningEffort: String
    var contextSnapshot: [String: String]
}

actor RecordingCodergenBackendState {
    private var results: [CodergenResult]
    private var index = 0
    private var recordedCalls: [RecordedCodergenCall] = []

    init(results: [CodergenResult]) {
        self.results = results
    }

    func appendCall(_ call: RecordedCodergenCall) {
        recordedCalls.append(call)
    }

    func nextResult() -> CodergenResult {
        let currentIndex = index
        index += 1
        if currentIndex < results.count {
            return results[currentIndex]
        }
        return results.last ?? CodergenResult(response: "", status: .success)
    }

    func calls() -> [RecordedCodergenCall] {
        recordedCalls
    }
}

final class RecordingCodergenBackend: CodergenBackend, @unchecked Sendable {
    private let state: RecordingCodergenBackendState

    init(results: [CodergenResult]) {
        self.state = RecordingCodergenBackendState(results: results)
    }

    func run(
        prompt: String,
        model: String,
        provider: String,
        reasoningEffort: String,
        context: PipelineContext
    ) async throws -> CodergenResult {
        await state.appendCall(
            RecordedCodergenCall(
                prompt: prompt,
                model: model,
                provider: provider,
                reasoningEffort: reasoningEffort,
                contextSnapshot: context.serializableSnapshot()
            )
        )
        return await state.nextResult()
    }

    func calls() async -> [RecordedCodergenCall] {
        await state.calls()
    }
}
