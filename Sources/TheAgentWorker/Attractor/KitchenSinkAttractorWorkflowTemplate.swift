// KitchenSinkAttractorWorkflowTemplate.swift
// Part of TheAgentWorkerKit target

/// Generates per-wave DOT workflow graphs for KitchenSink attractor runs.
public struct KitchenSinkAttractorWorkflowTemplate: Sendable {
    public var provider: String
    public var model: String
    public var reasoningEffort: String

    public init(
        provider: String = "anthropic",
        model: String = "claude-opus-4-6",
        reasoningEffort: String = "high"
    ) {
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort
    }

    /// Generate a DOT workflow for the given wave.
    public func dot(for wave: KitchenSinkWave) -> String {
        let stylesheet = "provider=\(provider) model=\(model) reasoning_effort=\(reasoningEffort)"
        let escapedTitle = wave.title.replacingOccurrences(of: "\"", with: "\\\"")
        let filesCSV = wave.ownedFiles.joined(separator: ", ")
        let casesCSV = wave.targetedTestCases.joined(separator: ", ")
        let featuresCSV = wave.features.joined(separator: ", ")

        return """
        digraph kitchensink_\(wave.id.replacingOccurrences(of: "-", with: "_")) {
            graph [default_max_retry=1, retry_target="implement", model_stylesheet="\(stylesheet)"]

            start      [shape=Mdiamond]
            plan       [shape=box, prompt="Read the \(wave.id) scope for KitchenSink attractor run. Wave: \(escapedTitle). Features: \(featuresCSV). Owned files: \(filesCSV). Restate scope, owned files, features, and validation commands. Do not touch files outside the manifest."]
            critique   [shape=box, prompt="Review the plan for \(wave.id). Check for gaps, missing edge cases, risk, and correctness. Suggest corrections before implementation begins."]
            implement  [shape=box, prompt="Implement the \(wave.id) features in the owned files: \(filesCSV). Run swift build --product KitchenSink to verify compilation. Keep changes scoped to the manifest.", auto_status=true]
            validate   [shape=box, prompt="Run validation for \(wave.id): swift build --product KitchenSink && OMNIUI_SMOKE_SECONDS=5 .build/debug/KitchenSink --notcurses. If TUI test cases exist, run: TUI_TEST_MODE=kitty TUI_TEST_CASES=\(casesCSV) scripts/tui-test.sh. Report pass/fail with artifacts.", goal_gate=true, retry_target="implement"]
            postmortem [shape=box, prompt="Summarize what shipped in \(wave.id), what was deferred, and lessons learned. List artifacts produced."]
            done       [shape=Msquare]

            start -> plan -> critique -> implement -> validate -> postmortem -> done
            validate -> implement [condition="outcome=fail"]
        }
        """
    }
}
