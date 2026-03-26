#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${GHOSTTY_KITCHENSINK_IMAGE:-swift-omnikit-kitchensink-runtime}"
DOCKERFILE_PATH="${GHOSTTY_KITCHENSINK_DOCKERFILE:-Dockerfile.kitchensink-runtime}"
BUILD_IMAGE="${GHOSTTY_KITCHENSINK_BUILD_IMAGE:-1}"
SMOKE_SECONDS="${OMNIUI_SMOKE_SECONDS:-0}"
DEMO_ANIM="${OMNIUI_DEMO_ANIM:-0}"
HOST_WORKSPACE_DIR="${GHOSTTY_LAB_HOST_WORKSPACE:-${GHOSTTY_KITCHENSINK_HOST_WORKSPACE:-}}"
STDERR_LOG="${GHOSTTY_KITCHENSINK_STDERR_LOG:-$HOST_WORKSPACE_DIR/Tests/tui/output/ghostty-lab/kitchensink.stderr.log}"

if ! command -v docker >/dev/null 2>&1; then
    printf 'docker CLI is not available in this environment\n' >&2
    exit 1
fi

if [[ ! -S /var/run/docker.sock ]]; then
    printf 'docker socket is not mounted at /var/run/docker.sock\n' >&2
    exit 1
fi

if [[ -z "$HOST_WORKSPACE_DIR" ]]; then
    printf 'host workspace path is not set; expected GHOSTTY_LAB_HOST_WORKSPACE\n' >&2
    exit 1
fi

if [[ "$BUILD_IMAGE" == "1" ]]; then
    printf '[ghostty-kitchensink] building %s from %s\n' "$IMAGE_TAG" "$DOCKERFILE_PATH"
    docker build -t "$IMAGE_TAG" -f "$DOCKERFILE_PATH" .
fi

printf '[ghostty-kitchensink] launching KitchenSink in %s\n' "$IMAGE_TAG"
mkdir -p "$(dirname "$STDERR_LOG")"
rm -f "$STDERR_LOG"
docker run --rm -it \
    --entrypoint bash \
    -v "${HOST_WORKSPACE_DIR}:${HOST_WORKSPACE_DIR}" \
    -e TERM="${TERM:-xterm-256color}" \
    -e COLORTERM="${COLORTERM:-truecolor}" \
    -e OMNIUI_SMOKE_SECONDS="$SMOKE_SECONDS" \
    -e OMNIUI_DEMO_ANIM="$DEMO_ANIM" \
    -e NCLOGLEVEL="${NCLOGLEVEL:-}" \
    "$IMAGE_TAG" \
    -lc "exec /app/.build/aarch64-unknown-linux-gnu/debug/KitchenSink --notcurses 2>'$STDERR_LOG'"
