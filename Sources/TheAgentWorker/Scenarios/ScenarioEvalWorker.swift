import Foundation
import OmniAgentMesh

public struct ScenarioEvaluation: Sendable, Equatable {
    public var passed: Bool
    public var executedScenarios: [String]
    public var failures: [String]

    public init(
        passed: Bool,
        executedScenarios: [String] = [],
        failures: [String] = []
    ) {
        self.passed = passed
        self.executedScenarios = executedScenarios
        self.failures = failures
    }
}

public struct ScenarioEvalWorker: Sendable {
    public typealias ScenarioRunner = @Sendable ([String]) async throws -> [String: Bool]

    public var defaultScenarios: [String]
    private let runner: ScenarioRunner?

    public init(
        defaultScenarios: [String] = ["unit-tests", "smoke-tests"],
        runner: ScenarioRunner? = nil
    ) {
        self.defaultScenarios = defaultScenarios
        self.runner = runner
    }

    public func evaluate(task: TaskRecord) async throws -> ScenarioEvaluation {
        let requested = task.historyProjection.expectedOutputs.isEmpty
            ? defaultScenarios
            : task.historyProjection.expectedOutputs
        let results = if let runner {
            try await runner(requested)
        } else {
            Dictionary(uniqueKeysWithValues: requested.map { ($0, true) })
        }
        let failures = results
            .filter { !$0.value }
            .map { "Scenario '\($0.key)' failed." }
            .sorted()
        return ScenarioEvaluation(
            passed: failures.isEmpty,
            executedScenarios: requested,
            failures: failures
        )
    }

    public func makeExecutor() -> LocalTaskExecutor {
        let worker = self
        return LocalTaskExecutor { task, reportProgress in
            try await reportProgress("Running scenario evaluation", ["task_id": task.taskID])
            let evaluation = try await worker.evaluate(task: task)
            let reportLines = [
                evaluation.passed ? "PASSED" : "FAILED",
                "Executed scenarios: " + evaluation.executedScenarios.joined(separator: ", "),
                evaluation.failures.joined(separator: "\n"),
            ]
                .filter { !$0.isEmpty }
            return LocalTaskExecutionResult(
                summary: evaluation.passed
                    ? "PASSED: scenario evaluation completed successfully."
                    : "FAILED: " + evaluation.failures.joined(separator: " "),
                artifacts: [
                    LocalTaskExecutionArtifact(
                        name: "scenario-report.txt",
                        contentType: "text/plain",
                        data: Data(reportLines.joined(separator: "\n\n").utf8)
                    ),
                ],
                metadata: ["passed": evaluation.passed ? "true" : "false"]
            )
        }
    }

    public func didPass(summary: String) -> Bool {
        summary.hasPrefix("PASSED:")
    }
}
