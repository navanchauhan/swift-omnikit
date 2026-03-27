Inspect the current singing bottleneck and propose a stronger next experiment.

Use the current evidence:
- best singing checkpoint: `artifacts/teacher_unified_train_public_full_attention_singing_priority/benchmark_checkpoint.json`
- best known singing metric: `sample_token_mae = 0.28073`
- latest stream-weighted run: `sample_token_mae = 0.28098`
- current blocker: model/objective quality rather than infra

When proposing the next step:
- prefer objective/modeling changes over pure hyperparameter sweeps
- explicitly explain why the latest stream-weighted run failed to improve
- if you recommend a new run, specify the smallest focused change that should be tested next
- include a pass/fail criterion tied to the singing metric
