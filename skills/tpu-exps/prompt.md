# TPU Experiment Runbook

You are working against the TPU teacher-training environment in `~/tpu-exps`.

Current executive state:
- The TPU pipeline is working end to end on real public data.
- No training job is running right now.
- The best singing checkpoint is `artifacts/teacher_unified_train_public_full_attention_singing_priority/benchmark_checkpoint.json`.
- The best known singing metric is `sample_token_mae = 0.28073`.
- The latest stream-weighted run ended at `sample_token_mae = 0.28098`, so it was flat to slightly worse.
- Infra is not the blocker. The current blocker is model/objective quality.
- There is no true mid-run checkpoint resume support in `scripts/train_teacher.py`.

Environment bootstrap:
- If you are already on the TPU VM or control host with the checkout, stay local.
- Otherwise reconnect with:
  - `gcloud config set account navanchauhan@gmail.com`
  - `gcloud compute tpus tpu-vm ssh test-tpu-on-demand --project=emel2-486506 --zone=us-central1-a`
- Then run:
  - `source ~/.venv/bin/activate`
  - `cd ~/tpu-exps`
  - `export PYTHONPATH=/home/navan.chauhan/tpu-exps/src`
  - `export HF_HUB_OFFLINE=1`

Canonical inspection commands:
- `tmux ls`
- `ps -eo pid=,etime=,stat=,%cpu=,%mem=,args= | grep train_teacher.py | grep -v grep`
- `df -h /`
- `cat ~/tpu-exps/artifacts/teacher_unified_train_public_full_attention_singing_priority/metrics.json`
- `cat ~/tpu-exps/artifacts/teacher_unified_train_public_full_attention_singing_stream_weighted/metrics.json`

Canonical export and eval commands:
- Export validation samples:
  - `uv run --no-sync --active python scripts/export_teacher_validation_samples.py --checkpoint artifacts/teacher_unified_train_public_full_attention_singing_priority/benchmark_checkpoint.json --model-config configs/model/teacher_public_full.yaml --dataset-index artifacts/data_public_full/prepared_index.json --output-dir artifacts/validation_samples/boss_review_singing_priority --domain singing`
- Run eval:
  - `uv run --no-sync --active python scripts/eval_teacher.py --config configs/eval/teacher_unified_public_full_attention_singing_priority.yaml --checkpoint artifacts/teacher_unified_train_public_full_attention_singing_priority/benchmark_checkpoint.json`

Canonical rerun:
- `tmux new-session -d -s teacher-unified-attention-singing-priority-rerun 'source ~/.venv/bin/activate && cd ~/tpu-exps && export PYTHONPATH=/home/navan.chauhan/tpu-exps/src && export HF_HUB_OFFLINE=1 && uv run --no-sync --active python scripts/train_teacher.py --config configs/train/teacher_unified_public_full_attention_singing_priority.yaml > artifacts/logs/teacher_unified_public_full_attention_singing_priority_rerun.log 2>&1'`
- Then monitor with:
  - `tmux ls`
  - `tail -n 80 ~/tpu-exps/artifacts/logs/teacher_unified_public_full_attention_singing_priority_rerun.log`

Behavior rules:
- Prefer real measurements, concrete metric deltas, and exact file paths.
- Do not claim a new run is better unless the metrics prove it.
- Prefer objective/modeling changes for singing quality over blind hyperparameter churn.
- When you finish, return a concise written summary and, when asked to inspect or compare, include a structured JSON block with the key metric values and your recommendation.
