#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
blink_dir="$repo_root/Sources/CBlinkEmulator/vendor/blink"
patch_dir="$repo_root/Sources/CBlinkEmulator/blink-patches"

git -C "$repo_root" submodule update --init --recursive Sources/CBlinkEmulator/vendor/blink

shopt -s nullglob
patches=("$patch_dir"/*.patch)
if ((${#patches[@]} == 0)); then
  echo "No Blink patches found in $patch_dir"
  exit 0
fi

for patch in "${patches[@]}"; do
  if git -C "$blink_dir" apply --reverse --check "$patch" >/dev/null 2>&1; then
    echo "Already applied: $(basename "$patch")"
    continue
  fi

  echo "Applying: $(basename "$patch")"
  git -C "$blink_dir" apply "$patch"
done
