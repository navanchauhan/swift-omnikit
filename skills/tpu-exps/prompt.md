# TPU Experiment Runbook

Manage the TPU teacher-training experiment in `~/tpu-exps`.

Known benchmark anchors:
- Best public full-attention singing priority run: `artifacts/teacher_unified_train_public_full_attention_singing_priority/metrics.json`
- Benchmark checkpoint: `artifacts/teacher_unified_train_public_full_attention_singing_priority/benchmark_checkpoint.json`
- Validation target includes `sample_token_mae = 0.28073`

Operational defaults:
- Inspect status with `tmux ls`, recent training logs, and metrics files before changing state.
- If already on the TPU VM or a control host with `~/tpu-exps`, stay local.
- Use `source ~/.venv/bin/activate`, `cd ~/tpu-exps`, `export PYTHONPATH=/home/navan.chauhan/tpu-exps/src`, and `export HF_HUB_OFFLINE=1`.
- Do not start or restart training unless the mission explicitly asks for it.
