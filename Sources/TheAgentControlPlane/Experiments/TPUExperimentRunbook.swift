import Foundation
import OmniAgentMesh

public enum TPUExperimentOperation: String, CaseIterable, Sendable {
    case inspectStatus = "inspect_status"
    case compareBestRuns = "compare_best_runs"
    case evaluateBestCheckpoint = "evaluate_best_checkpoint"
    case exportBestValidationSamples = "export_best_validation_samples"
    case rerunBestKnownConfig = "rerun_best_known_config"
    case improveSingingResults = "improve_singing_results"
}

public struct TPUExperimentMissionTemplate: Sendable, Equatable {
    public var operation: TPUExperimentOperation
    public var skillIDs: [String]
    public var request: MissionStartRequest

    public init(
        operation: TPUExperimentOperation,
        skillIDs: [String],
        request: MissionStartRequest
    ) {
        self.operation = operation
        self.skillIDs = skillIDs
        self.request = request
    }
}

public enum TPUExperimentRunbook {
    public static let skillID = "tpu.exps"
    public static let bestKnownCheckpoint = "artifacts/teacher_unified_train_public_full_attention_singing_priority/benchmark_checkpoint.json"
    public static let bestKnownMetrics = "artifacts/teacher_unified_train_public_full_attention_singing_priority/metrics.json"
    public static let latestStreamWeightedMetrics = "artifacts/teacher_unified_train_public_full_attention_singing_stream_weighted/metrics.json"

    public static func template(
        for operation: TPUExperimentOperation,
        domain: String = "singing",
        notes: String? = nil,
        extraCapabilityRequirements: [String] = [],
        executionModeOverride: MissionRecord.ExecutionMode? = nil,
        requireApprovalOverride: Bool? = nil
    ) -> TPUExperimentMissionTemplate {
        let executionMode = resolvedExecutionMode(
            for: operation,
            override: executionModeOverride
        )
        let requireApproval = requireApprovalOverride ?? defaultRequireApproval(for: operation)
        let capabilityRequirements = Array(
            Set(defaultCapabilities(for: operation)).union(extraCapabilityRequirements)
        ).sorted()
        let expectedOutputs = defaultExpectedOutputs(for: operation)
        let constraints = defaultConstraints(for: operation, domain: domain)
        let brief = buildBrief(for: operation, domain: domain, notes: notes)
        let metadata = [
            "mission_kind": "tpu_experiment",
            "tpu_operation": operation.rawValue,
            "tpu_domain": domain,
            "tpu_best_known_checkpoint": bestKnownCheckpoint,
            "tpu_best_known_metrics": bestKnownMetrics,
            "tpu_latest_stream_weighted_metrics": latestStreamWeightedMetrics,
            "tpu_experiment_root": "~/tpu-exps",
            "tpu_preferred_skill": skillID,
        ].merging(operationMetadata(for: operation)) { _, new in new }

        let request = MissionStartRequest(
            title: title(for: operation),
            brief: brief,
            executionMode: executionMode,
            capabilityRequirements: capabilityRequirements,
            expectedOutputs: expectedOutputs,
            constraints: constraints,
            priority: defaultPriority(for: operation),
            budgetUnits: defaultBudgetUnits(for: operation),
            maxRecursionDepth: defaultRecursionDepth(for: operation),
            requireApproval: requireApproval,
            approvalPrompt: approvalPrompt(for: operation, domain: domain),
            metadata: metadata
        )

        return TPUExperimentMissionTemplate(
            operation: operation,
            skillIDs: [skillID],
            request: request
        )
    }
}

private extension TPUExperimentRunbook {
    static func resolvedExecutionMode(
        for operation: TPUExperimentOperation,
        override explicit: MissionRecord.ExecutionMode?
    ) -> MissionRecord.ExecutionMode {
        let fallback = defaultExecutionMode(for: operation)
        guard let explicit else {
            return fallback
        }
        switch (fallback, explicit) {
        case (.workerTask, .direct), (.attractorWorkflow, .direct):
            return fallback
        default:
            return explicit
        }
    }

    static func title(for operation: TPUExperimentOperation) -> String {
        switch operation {
        case .inspectStatus:
            return "Inspect TPU teacher experiment status"
        case .compareBestRuns:
            return "Compare the best and latest TPU singing runs"
        case .evaluateBestCheckpoint:
            return "Evaluate the best TPU singing checkpoint"
        case .exportBestValidationSamples:
            return "Export validation samples from the best TPU singing checkpoint"
        case .rerunBestKnownConfig:
            return "Launch the best-known TPU singing training rerun"
        case .improveSingingResults:
            return "Improve TPU singing teacher results"
        }
    }

    static func defaultExecutionMode(for operation: TPUExperimentOperation) -> MissionRecord.ExecutionMode {
        switch operation {
        case .improveSingingResults:
            return .attractorWorkflow
        case .inspectStatus, .compareBestRuns, .evaluateBestCheckpoint, .exportBestValidationSamples, .rerunBestKnownConfig:
            return .workerTask
        }
    }

    static func defaultRequireApproval(for operation: TPUExperimentOperation) -> Bool {
        switch operation {
        case .rerunBestKnownConfig, .improveSingingResults:
            return true
        case .inspectStatus, .compareBestRuns, .evaluateBestCheckpoint, .exportBestValidationSamples:
            return false
        }
    }

    static func defaultCapabilities(for operation: TPUExperimentOperation) -> [String] {
        switch operation {
        case .inspectStatus, .compareBestRuns:
            return ["teacher-training", "tpu"]
        case .evaluateBestCheckpoint, .exportBestValidationSamples:
            return ["jax", "teacher-training", "tpu"]
        case .rerunBestKnownConfig:
            return ["jax", "teacher-training", "tpu"]
        case .improveSingingResults:
            return ["execution:attractor", "jax", "teacher-training", "tpu", "workflow:plan-implement-validate"]
        }
    }

    static func defaultExpectedOutputs(for operation: TPUExperimentOperation) -> [String] {
        switch operation {
        case .inspectStatus:
            return ["tpu-status.md", "tpu-status.json"]
        case .compareBestRuns:
            return ["run-comparison.md", "run-comparison.json"]
        case .evaluateBestCheckpoint:
            return ["evaluation-log.txt", "evaluation-summary.md"]
        case .exportBestValidationSamples:
            return ["validation-sample-export-log.txt", "validation-sample-summary.md"]
        case .rerunBestKnownConfig:
            return ["training-session-receipt.md", "training-log-path.txt", "tmux-session-name.txt"]
        case .improveSingingResults:
            return ["improvement-plan.md", "experiment-decision.json", "benchmark-comparison.json", "next-action.md"]
        }
    }

    static func defaultConstraints(for operation: TPUExperimentOperation, domain: String) -> [String] {
        var constraints = [
            "Prefer the real public corpus and the existing TPU/JAX pipeline rather than synthetic smoke data.",
            "Use the best-known singing checkpoint \(bestKnownCheckpoint) as the reference baseline unless a better checkpoint is proven.",
            "The latest stream-weighted run did not beat the singing-priority baseline; do not assume the newest run is better.",
            "No true mid-run checkpoint resume support exists in scripts/train_teacher.py. Fresh reruns and evaluation/export of existing checkpoints are safe.",
            "Summarize metric deltas precisely and call out whether the result improved, regressed, or stayed flat.",
        ]

        switch operation {
        case .evaluateBestCheckpoint, .exportBestValidationSamples, .rerunBestKnownConfig, .improveSingingResults:
            constraints.append("Keep the focus on \(domain) quality unless the task explicitly asks for another domain.")
        case .inspectStatus, .compareBestRuns:
            break
        }

        if operation == .improveSingingResults {
            constraints.append("Prefer objective/modeling changes over blind hyperparameter sweeps.")
            constraints.append("Do not launch a long-running training job until the plan and proposed change are explicit.")
        }

        return constraints
    }

    static func defaultPriority(for operation: TPUExperimentOperation) -> Int {
        switch operation {
        case .inspectStatus, .compareBestRuns:
            return 1
        case .evaluateBestCheckpoint, .exportBestValidationSamples:
            return 2
        case .rerunBestKnownConfig:
            return 3
        case .improveSingingResults:
            return 4
        }
    }

    static func defaultBudgetUnits(for operation: TPUExperimentOperation) -> Int {
        switch operation {
        case .inspectStatus, .compareBestRuns:
            return 1
        case .evaluateBestCheckpoint, .exportBestValidationSamples:
            return 2
        case .rerunBestKnownConfig:
            return 3
        case .improveSingingResults:
            return 5
        }
    }

    static func defaultRecursionDepth(for operation: TPUExperimentOperation) -> Int {
        switch operation {
        case .improveSingingResults:
            return 2
        case .inspectStatus, .compareBestRuns, .evaluateBestCheckpoint, .exportBestValidationSamples, .rerunBestKnownConfig:
            return 1
        }
    }

    static func approvalPrompt(for operation: TPUExperimentOperation, domain: String) -> String? {
        switch operation {
        case .rerunBestKnownConfig:
            return "Approve starting a fresh TPU training rerun using the best-known \(domain) priority config?"
        case .improveSingingResults:
            return "Approve an end-to-end improvement mission for the TPU \(domain) teacher experiment, including proposing changes and launching a targeted run if justified?"
        case .inspectStatus, .compareBestRuns, .evaluateBestCheckpoint, .exportBestValidationSamples:
            return nil
        }
    }

    static func operationMetadata(for operation: TPUExperimentOperation) -> [String: String] {
        switch operation {
        case .inspectStatus:
            return [
                "tpu_command_focus": "status",
                "tpu_expected_metric": "singing sample_token_mae",
            ]
        case .compareBestRuns:
            return [
                "tpu_command_focus": "compare",
                "tpu_compare_against": latestStreamWeightedMetrics,
            ]
        case .evaluateBestCheckpoint:
            return [
                "tpu_command_focus": "eval",
                "tpu_checkpoint": bestKnownCheckpoint,
            ]
        case .exportBestValidationSamples:
            return [
                "tpu_command_focus": "export",
                "tpu_checkpoint": bestKnownCheckpoint,
            ]
        case .rerunBestKnownConfig:
            return [
                "tpu_command_focus": "train",
                "tpu_train_config": "configs/train/teacher_unified_public_full_attention_singing_priority.yaml",
            ]
        case .improveSingingResults:
            return [
                "workflow": "attractor",
                "tpu_command_focus": "improve",
                "tpu_train_config": "configs/train/teacher_unified_public_full_attention_singing_priority.yaml",
            ]
        }
    }

    static func buildBrief(
        for operation: TPUExperimentOperation,
        domain: String,
        notes: String?
    ) -> String {
        var sections = [
            """
            Manage the TPU teacher-training experiment in `~/tpu-exps`.

            Current state:
            - The TPU pipeline is working end to end on real public data.
            - No training job is running right now.
            - The best singing checkpoint is `\(bestKnownCheckpoint)` with `singing sample_token_mae = 0.28073`.
            - The latest stream-weighted run ended at `singing sample_token_mae = 0.28098`, so it was flat to slightly worse.
            - The blocker is model/objective quality rather than TPU infrastructure.
            """,
            """
            Environment setup:
            - If you are already on the TPU VM or the control host with `~/tpu-exps`, stay local.
            - Otherwise reconnect with `gcloud config set account navanchauhan@gmail.com` and `gcloud compute tpus tpu-vm ssh test-tpu-on-demand --project=emel2-486506 --zone=us-central1-a`.
            - Then run `source ~/.venv/bin/activate`, `cd ~/tpu-exps`, `export PYTHONPATH=/home/navan.chauhan/tpu-exps/src`, and `export HF_HUB_OFFLINE=1`.
            """,
            operationInstructions(for: operation, domain: domain),
        ]

        if let notes,
           !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Extra operator notes:\n\(notes)")
        }

        sections.append(
            """
            Always return a concise written summary plus structured text artifacts matching the expected outputs. When reporting metrics, include absolute values and whether the result improved or regressed versus the best singing-priority baseline.
            """
        )

        return sections.joined(separator: "\n\n")
    }

    static func operationInstructions(for operation: TPUExperimentOperation, domain: String) -> String {
        switch operation {
        case .inspectStatus:
            return """
            Task:
            - Run `tmux ls`, `ps -eo pid=,etime=,stat=,%cpu=,%mem=,args= | grep train_teacher.py | grep -v grep`, and `df -h /`.
            - Inspect `\(bestKnownMetrics)` and `\(latestStreamWeightedMetrics)`.
            - Summarize whether any training is active, which run is currently the best for \(domain), and what the latest run changed.
            """
        case .compareBestRuns:
            return """
            Task:
            - Compare `\(bestKnownMetrics)` against `\(latestStreamWeightedMetrics)`.
            - Call out the exact delta for the key \(domain) quality metrics and whether the newest run is actually better.
            - If useful, inspect the paired `benchmark_checkpoint.json` files before writing the comparison summary.
            """
        case .evaluateBestCheckpoint:
            return """
            Task:
            - Evaluate the best-known singing checkpoint with:
              `uv run --no-sync --active python scripts/eval_teacher.py --config configs/eval/teacher_unified_public_full_attention_singing_priority.yaml --checkpoint \(bestKnownCheckpoint)`
            - Capture the evaluation log and summarize the important metrics.
            """
        case .exportBestValidationSamples:
            return """
            Task:
            - Export validation samples from the best-known singing checkpoint with:
              `uv run --no-sync --active python scripts/export_teacher_validation_samples.py --checkpoint \(bestKnownCheckpoint) --model-config configs/model/teacher_public_full.yaml --dataset-index artifacts/data_public_full/prepared_index.json --output-dir artifacts/validation_samples/boss_review_singing_priority --domain \(domain)`
            - Record where the samples were written and summarize what was exported.
            """
        case .rerunBestKnownConfig:
            return """
            Task:
            - Start a fresh rerun of the best-known config in tmux:
              `tmux new-session -d -s teacher-unified-attention-singing-priority-rerun 'source ~/.venv/bin/activate && cd ~/tpu-exps && export PYTHONPATH=/home/navan.chauhan/tpu-exps/src && export HF_HUB_OFFLINE=1 && uv run --no-sync --active python scripts/train_teacher.py --config configs/train/teacher_unified_public_full_attention_singing_priority.yaml > artifacts/logs/teacher_unified_public_full_attention_singing_priority_rerun.log 2>&1'`
            - Then verify it started with `tmux ls` and `tail -n 80 ~/tpu-exps/artifacts/logs/teacher_unified_public_full_attention_singing_priority_rerun.log`.
            - Report the tmux session name, log path, and any immediate startup issues.
            """
        case .improveSingingResults:
            return """
            Task:
            - Inspect the current best singing checkpoint, the latest stream-weighted regression, and the training/eval scripts that produced them.
            - Propose a concrete improvement aimed at beating the current `singing sample_token_mae` baseline.
            - Prefer model/objective changes for \(domain) quality over blind hyperparameter tuning.
            - If a clear improvement plan is justified and approved, implement the smallest focused experiment needed and launch it with explicit logging and evaluation steps.
            """
        }
    }
}
