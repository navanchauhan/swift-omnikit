import Foundation
import Testing
import OmniAIAttractor
import OmniAgentMesh
@testable import TheAgentWorkerKit

@Suite
struct AttractorTaskExecutorTests {
    @Test
    func executorRunsWorkflowAndRoutesQuestionGateThroughRootBridge() async throws {
        let workingDirectory = try makeTemporaryDirectory(prefix: "attractor-worker")
        let logsRoot = workingDirectory.appending(path: ".ai/attractor-runs", directoryHint: .isDirectory)
        let backend = SequentialCodergenBackend(
            results: [
                CodergenResult(response: "Plan contract drafted.", status: .success),
                CodergenResult(response: "Implementation completed.", status: .success),
                CodergenResult(response: "Review passed.", status: .success),
                CodergenResult(response: "Scenario validation passed.", status: .success),
                CodergenResult(response: "Workflow approved for completion.", status: .success),
            ]
        )
        let bridge = RecordingWorkerInteractionBridge(
            questionResolution: WorkerInteractionResolution(
                requestID: "question-1",
                status: .answered,
                responseText: "Continue",
                responderActorID: ActorID(rawValue: "chief")
            )
        )
        let executor = AttractorTaskExecutor(
            workflowTemplate: AttractorWorkflowTemplate(
                provider: "openai",
                model: "gpt-test",
                reasoningEffort: "high"
            ),
            backend: backend,
            workingDirectory: workingDirectory.path(),
            logsRoot: logsRoot,
            interactionBridge: bridge,
            defaultHumanTimeoutSeconds: 30
        )
        let task = TaskRecord(
            rootSessionID: SessionScope(
                actorID: ActorID(rawValue: "chief"),
                workspaceID: WorkspaceID(rawValue: "workspace-a"),
                channelID: ChannelID(rawValue: "dm-a")
            ).sessionID,
            missionID: "mission-1",
            historyProjection: HistoryProjection(
                taskBrief: "Implement a validated workflow.",
                constraints: [
                    "question_gate=true",
                    "question_prompt=Need confirmation before implementation?",
                ],
                expectedOutputs: ["workflow summary"]
            )
        )

        let progressRecorder = ProgressRecorder()
        let result = try await executor.execute(task: task) { summary, _ in
            await progressRecorder.record(summary)
        }

        let recordedQuestions = await bridge.questionPrompts()
        let progressSummaries = await progressRecorder.summaries()

        #expect(result.summary.localizedStandardContains("Attractor workflow success"))
        #expect(result.metadata["execution_mode"] == "attractor")
        #expect(result.artifacts.contains { $0.name.hasSuffix("workflow.dot") })
        #expect(result.artifacts.contains { $0.name.hasSuffix("pipeline-result.json") })
        #expect(result.artifacts.contains { $0.name.hasSuffix("plan/response.md") })
        #expect(result.artifacts.contains { $0.name.hasSuffix("judge/response.md") })
        #expect(recordedQuestions.count == 1)
        #expect(recordedQuestions.first?.missionID == "mission-1")
        #expect(recordedQuestions.first?.taskID == task.taskID)
        #expect(recordedQuestions.first?.prompt == "Need confirmation before implementation?")
        #expect(progressSummaries.contains("Launching Attractor workflow"))
        #expect(progressSummaries.contains("Attractor workflow completed"))
    }

    @Test
    func executorThrowsWhenEvaluatorRejectsWorkflow() async throws {
        let workingDirectory = try makeTemporaryDirectory(prefix: "attractor-worker-fail")
        let logsRoot = workingDirectory.appending(path: ".ai/attractor-runs", directoryHint: .isDirectory)
        let backend = SequentialCodergenBackend(
            results: [
                CodergenResult(response: "Plan contract drafted.", status: .success),
                CodergenResult(response: "Implementation completed.", status: .success),
                CodergenResult(response: "Review passed.", status: .success),
                CodergenResult(response: "Scenario validation passed.", status: .success),
                CodergenResult(response: "Judge requested a retry.", status: .retry),
            ]
        )
        let executor = AttractorTaskExecutor(
            workflowTemplate: AttractorWorkflowTemplate(
                provider: "openai",
                model: "gpt-test",
                reasoningEffort: "high"
            ),
            backend: backend,
            workingDirectory: workingDirectory.path(),
            logsRoot: logsRoot
        )
        let task = TaskRecord(
            rootSessionID: SessionScope(
                actorID: ActorID(rawValue: "chief"),
                workspaceID: WorkspaceID(rawValue: "workspace-b"),
                channelID: ChannelID(rawValue: "dm-b")
            ).sessionID,
            missionID: "mission-2",
            historyProjection: HistoryProjection(taskBrief: "Fail during review.")
        )

        await #expect(throws: AttractorTaskExecutorError.self) {
            try await executor.execute(task: task) { _, _ in }
        }
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "omnikit-\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor SequentialCodergenBackendState {
    private var results: [CodergenResult]
    private var index = 0

    init(results: [CodergenResult]) {
        self.results = results
    }

    func nextResult() -> CodergenResult {
        let currentIndex = index
        index += 1
        if currentIndex < results.count {
            return results[currentIndex]
        }
        return results.last ?? CodergenResult(response: "", status: .success)
    }
}

private final class SequentialCodergenBackend: CodergenBackend, @unchecked Sendable {
    private let state: SequentialCodergenBackendState

    init(results: [CodergenResult]) {
        self.state = SequentialCodergenBackendState(results: results)
    }

    func run(
        prompt: String,
        model: String,
        provider: String,
        reasoningEffort: String,
        context: PipelineContext
    ) async throws -> CodergenResult {
        await state.nextResult()
    }
}

private actor RecordingWorkerInteractionState {
    private(set) var approvals: [WorkerApprovalPrompt] = []
    private(set) var questions: [WorkerQuestionPrompt] = []

    func recordApproval(_ prompt: WorkerApprovalPrompt) {
        approvals.append(prompt)
    }

    func recordQuestion(_ prompt: WorkerQuestionPrompt) {
        questions.append(prompt)
    }

    func questionPrompts() -> [WorkerQuestionPrompt] {
        questions
    }
}

private final class RecordingWorkerInteractionBridge: WorkerInteractionBridge, @unchecked Sendable {
    private let state = RecordingWorkerInteractionState()
    private let approvalResolution: WorkerInteractionResolution
    private let questionResolution: WorkerInteractionResolution

    init(
        approvalResolution: WorkerInteractionResolution = WorkerInteractionResolution(
            requestID: "approval-1",
            status: .approved,
            responseText: "Approved"
        ),
        questionResolution: WorkerInteractionResolution
    ) {
        self.approvalResolution = approvalResolution
        self.questionResolution = questionResolution
    }

    func requestApproval(_ prompt: WorkerApprovalPrompt) async throws -> WorkerInteractionResolution {
        await state.recordApproval(prompt)
        return approvalResolution
    }

    func requestQuestion(_ prompt: WorkerQuestionPrompt) async throws -> WorkerInteractionResolution {
        await state.recordQuestion(prompt)
        return questionResolution
    }

    func questionPrompts() async -> [WorkerQuestionPrompt] {
        await state.questionPrompts()
    }
}

private actor ProgressRecorder {
    private var entries: [String] = []

    func record(_ summary: String) {
        entries.append(summary)
    }

    func summaries() -> [String] {
        entries
    }
}
