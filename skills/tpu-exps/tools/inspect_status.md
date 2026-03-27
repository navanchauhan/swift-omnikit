Inspect the TPU environment and current experiment state.

1. If you are not already on the TPU VM or control host, reconnect using the gcloud commands in the skill prompt.
2. Run:
   - `tmux ls`
   - `ps -eo pid=,etime=,stat=,%cpu=,%mem=,args= | grep train_teacher.py | grep -v grep`
   - `df -h /`
   - `cat artifacts/teacher_unified_train_public_full_attention_singing_priority/metrics.json`
   - `cat artifacts/teacher_unified_train_public_full_attention_singing_stream_weighted/metrics.json`
3. Summarize:
   - whether training is active
   - the best singing checkpoint and exact metric
   - the latest completed run and delta versus the best singing-priority run
   - any storage or environment issues
4. Prefer a compact JSON block plus a short prose summary.
