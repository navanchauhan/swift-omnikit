#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CODEX_AUTH_JSON="${CODEX_AUTH_JSON:-$HOME/.codex/auth.json}"
OPENAI_OAUTH_ISSUER="${OPENAI_OAUTH_ISSUER:-https://auth.openai.com}"
OPENAI_OAUTH_CLIENT_ID="${OPENAI_OAUTH_CLIENT_ID:-app_EMoamEEZ73f0CkXaXp7hrann}"
COMPOSE_FILE="${COMPOSE_FILE:-$PROJECT_ROOT/docker-compose.agent.yml}"

usage() {
    cat <<'EOF'
Usage: scripts/run-agent-stack.sh [compose-args]

This script refreshes an OpenAI API key from local Codex auth state when needed,
exporting OPENAI_API_KEY for docker compose, then runs docker compose with the
provided arguments.

When called with no arguments, it defaults to `up -d`.

Examples:
  scripts/run-agent-stack.sh up -d
  scripts/run-agent-stack.sh logs -f
EOF
}

require_commands() {
    local missing=()
    for cmd in curl jq docker; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        printf 'Missing required commands: %s\n' "${missing[*]}" >&2
        exit 1
    fi
}

url_encode() {
    printf '%s' "$1" | jq -sR @uri
}

exchange_codex_id_token() {
    local id_token="$1"
    local response_file status
    local endpoint="${OPENAI_OAUTH_ISSUER%/}/oauth/token"
    local body

    body="grant_type=$(url_encode 'urn:ietf:params:oauth:grant-type:token-exchange')"
    body+="&client_id=$(url_encode "$OPENAI_OAUTH_CLIENT_ID")"
    body+="&requested_token=$(url_encode openai-api-key)"
    body+="&subject_token=$(url_encode "$id_token")"
    body+="&subject_token_type=$(url_encode 'urn:ietf:params:oauth:token-type:id_token')"

    response_file="$(mktemp)"
    status=$(curl -sS -X POST "$endpoint" \
        -H 'content-type: application/x-www-form-urlencoded' \
        --data "$body" \
        -o "$response_file" \
        -w '%{http_code}')

    if [[ "${status}" != 2* ]]; then
        local code
        code="$(jq -r '.error.code // empty' "$response_file" 2>/dev/null || true)"
        rm -f "$response_file"
        if [[ "$code" == "invalid_id_token" || "$code" == "token_expired" ]]; then
            printf 'OAuth exchange failed (%s). Re-run `codex login` on the host and retry.\n' "$code" >&2
        else
            printf 'OAuth exchange failed with status %s while contacting %s\n' "$status" "$endpoint" >&2
        fi
        return 1
    fi

    jq -r '.access_token // empty' "$response_file"
    rm -f "$response_file"
}

resolve_openai_api_key() {
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        printf '%s' "$OPENAI_API_KEY"
        return 0
    fi

    if [[ -f "$CODEX_AUTH_JSON" ]]; then
        local api_key
        api_key="$(jq -r '.OPENAI_API_KEY // empty' "$CODEX_AUTH_JSON")"
        if [[ -n "$api_key" ]]; then
            printf '%s' "$api_key"
            return 0
        fi

        local id_token
        if [[ -n "${OPENAI_OAUTH_ID_TOKEN:-}" ]]; then
            id_token="$OPENAI_OAUTH_ID_TOKEN"
        else
            id_token="$(jq -r '.tokens.id_token // empty' "$CODEX_AUTH_JSON")"
        fi
        if [[ -z "$id_token" ]]; then
            return 1
        fi

        exchange_codex_id_token "$id_token"
        return $?
    fi

    return 1
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        return 0
    fi

    require_commands

    local api_key
    api_key="$(resolve_openai_api_key)"
    if [[ -z "$api_key" ]]; then
        printf 'Could not resolve OPENAI_API_KEY from environment or Codex auth cache (%s).\n' "$CODEX_AUTH_JSON" >&2
        printf 'Run: codex login\n' >&2
        return 1
    fi

    export OPENAI_API_KEY="$api_key"

    local -a compose_args=("$@")
    if [[ ${#compose_args[@]} -eq 0 ]]; then
        compose_args=(up -d)
    fi

    (cd "$PROJECT_ROOT" && docker compose -f "$COMPOSE_FILE" "${compose_args[@]}")
}

main "$@"
