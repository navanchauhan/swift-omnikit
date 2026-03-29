#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${GHOSTTY_KITCHENSINK_IMAGE:-swift-omnikit-kitchensink-runtime}"
DOCKERFILE_PATH="${GHOSTTY_KITCHENSINK_DOCKERFILE:-Dockerfile.kitchensink-runtime}"
BUILD_IMAGE="${GHOSTTY_KITCHENSINK_BUILD_IMAGE:-0}"
HOST_WORKSPACE_DIR="${GHOSTTY_LAB_HOST_WORKSPACE:-${GHOSTTY_KITCHENSINK_HOST_WORKSPACE:-}}"

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
    printf '[ghostty-igopher] building %s from %s\n' "$IMAGE_TAG" "$DOCKERFILE_PATH"
    docker build -t "$IMAGE_TAG" -f "$DOCKERFILE_PATH" .
fi

printf '[ghostty-igopher] launching iGopherTUI in %s\n' "$IMAGE_TAG"
docker run --rm -it \
    --entrypoint bash \
    -v "${HOST_WORKSPACE_DIR}:${HOST_WORKSPACE_DIR}" \
    -e TERM="xterm-256color" \
    -e COLORTERM="${COLORTERM:-truecolor}" \
    "$IMAGE_TAG" \
    -lc "exec /app/.build/aarch64-unknown-linux-gnu/debug/iGopherTUI"
