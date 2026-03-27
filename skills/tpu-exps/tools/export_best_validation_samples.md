Export validation samples from the best-known singing checkpoint.

Command:
`uv run --no-sync --active python scripts/export_teacher_validation_samples.py --checkpoint artifacts/teacher_unified_train_public_full_attention_singing_priority/benchmark_checkpoint.json --model-config configs/model/teacher_public_full.yaml --dataset-index artifacts/data_public_full/prepared_index.json --output-dir artifacts/validation_samples/boss_review_singing_priority --domain singing`

After the command:
- report the output directory
- mention the checkpoint and domain used
- summarize anything noteworthy from the export log
