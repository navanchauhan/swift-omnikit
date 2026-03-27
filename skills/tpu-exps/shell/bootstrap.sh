#!/bin/sh
set -eu

source "${HOME}/.venv/bin/activate"
cd "${HOME}/tpu-exps"
export PYTHONPATH="${HOME}/tpu-exps/src"
export HF_HUB_OFFLINE=1

printf '%s\n' "TPU experiment environment ready in ${HOME}/tpu-exps"
