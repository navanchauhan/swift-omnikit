Run the canonical evaluation for the best-known singing checkpoint.

Command:
`uv run --no-sync --active python scripts/eval_teacher.py --config configs/eval/teacher_unified_public_full_attention_singing_priority.yaml --checkpoint artifacts/teacher_unified_train_public_full_attention_singing_priority/benchmark_checkpoint.json`

After the command:
- capture the important metrics
- report whether they match or diverge from the saved benchmark
- keep the output focused on the singing result and any obvious regressions
