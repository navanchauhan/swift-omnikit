Start a fresh TPU training rerun from the best-known singing-priority configuration.

Use this exact tmux command:
`tmux new-session -d -s teacher-unified-attention-singing-priority-rerun 'source ~/.venv/bin/activate && cd ~/tpu-exps && export PYTHONPATH=/home/navan.chauhan/tpu-exps/src && export HF_HUB_OFFLINE=1 && uv run --no-sync --active python scripts/train_teacher.py --config configs/train/teacher_unified_public_full_attention_singing_priority.yaml > artifacts/logs/teacher_unified_public_full_attention_singing_priority_rerun.log 2>&1'`

Then verify startup with:
- `tmux ls`
- `tail -n 80 ~/tpu-exps/artifacts/logs/teacher_unified_public_full_attention_singing_priority_rerun.log`

Important:
- there is no true mid-run resume support
- report the tmux session name and log path
- do not say the rerun succeeded until the startup checks pass
