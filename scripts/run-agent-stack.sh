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
        local message
        code="$(jq -r '.error.code // empty' "$response_file" 2>/dev/null || true)"
        message="$(jq -r '.error.message // .error_description // .message // empty' "$response_file" 2>/dev/null || true)"
        rm -f "$response_file"
        if [[ "$code" == "invalid_id_token" || "$code" == "token_expired" ]]; then
            printf 'OAuth exchange failed (%s). Attempting refresh flow.\n' "$code" >&2
        elif [[ -n "$code" ]]; then
            printf 'OAuth exchange failed (%s): %s\n' "$code" "${message:-n/a}" >&2
        else
            printf 'OAuth exchange failed with status %s while contacting %s\n' "$status" "$endpoint" >&2
        fi
        return 1
    fi

    jq -r '.access_token // empty' "$response_file"
    rm -f "$response_file"
}

exchange_codex_refresh_token() {
    local refresh_token="$1"
    local response_file status
    local endpoint="${OPENAI_OAUTH_ISSUER%/}/oauth/token"
    local body

    body="$(cat <<EOF
{"client_id":"${OPENAI_OAUTH_CLIENT_ID}","grant_type":"refresh_token","refresh_token":"${refresh_token}"}
EOF
)"

    response_file="$(mktemp)"
    status=$(curl -sS -X POST "$endpoint" \
        -H 'content-type: application/json' \
        --data "$body" \
        -o "$response_file" \
        -w '%{http_code}')

    if [[ "${status}" != 2* ]]; then
        local code
        local message
        code="$(jq -r '.error.code // empty' "$response_file" 2>/dev/null || true)"
        message="$(jq -r '.error.message // .error_description // .message // empty' "$response_file" 2>/dev/null || true)"
        rm -f "$response_file"
        if [[ -n "$code" ]]; then
            if [[ "$code" == "refresh_token_reused" || "$code" == "invalid_grant" ]]; then
                printf 'OAuth refresh failed (%s): %s\n' "$code" "${message:-n/a}" >&2
                printf 'Run: codex login\n' >&2
            else
                printf 'OAuth refresh failed (%s): %s\n' "$code" "${message:-n/a}" >&2
            fi
        else
            printf 'OAuth refresh failed with status %s while contacting %s\n' "$status" "$endpoint" >&2
        fi
        return 1
    fi

    if ! jq -e . "$response_file" >/dev/null 2>&1; then
        rm -f "$response_file"
        return 1
    fi
    cat "$response_file"
    rm -f "$response_file"
}

refresh_codex_tokens() {
    local refresh_token="$1"
    local auth_json="$2"
    local response
    local new_id_token new_access_token new_refresh_token

    response="$(exchange_codex_refresh_token "$refresh_token")"
    if [[ -z "$response" ]]; then
        return 1
    fi

    new_id_token="$(jq -r '.id_token // empty' <<<"$response")"
    new_access_token="$(jq -r '.access_token // empty' <<<"$response")"
    new_refresh_token="$(jq -r '.refresh_token // empty' <<<"$response")"

    if [[ -z "$new_id_token" && -z "$new_access_token" && -z "$new_refresh_token" ]]; then
        return 1
    fi

    if [[ -z "$new_id_token" ]]; then
        if [[ -n "$new_access_token" ]]; then
            new_id_token="$new_access_token"
        fi
    fi

    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local temp_file
    temp_file="$(mktemp)"

    local update_expr='.'
    if [[ -n "$new_id_token" ]]; then
        update_expr="$update_expr | .tokens.id_token = \"$new_id_token\""
    fi
    if [[ -n "$new_access_token" ]]; then
        update_expr="$update_expr | .tokens.access_token = \"$new_access_token\""
    fi
    if [[ -n "$new_refresh_token" ]]; then
        update_expr="$update_expr | .tokens.refresh_token = \"$new_refresh_token\""
    fi
    update_expr="$update_expr | .last_refresh = \"$now\""

    if ! jq "$update_expr" "$auth_json" > "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi
    mv "$temp_file" "$auth_json"
}

resolve_openai_api_key_from_auth_json() {
    local auth_json="$1"
    local api_key id_token refresh_token payload

    api_key="$(jq -r '.OPENAI_API_KEY // empty' "$auth_json" 2>/dev/null || true)"
    if [[ -n "$api_key" && "$api_key" != "null" ]]; then
        printf '%s' "$api_key"
        return 0
    fi

    id_token="${OPENAI_OAUTH_ID_TOKEN:-}"
    if [[ -z "$id_token" ]]; then
        id_token="$(jq -r '.tokens.id_token // empty' "$auth_json" 2>/dev/null || true)"
    fi
    if [[ -z "$id_token" && -z "${OPENAI_OAUTH_REFRESH_TOKEN:-}" ]]; then
        refresh_token="$(jq -r '.tokens.refresh_token // empty' "$auth_json" 2>/dev/null || true)"
    else
        refresh_token="${OPENAI_OAUTH_REFRESH_TOKEN:-$(jq -r '.tokens.refresh_token // empty' "$auth_json" 2>/dev/null || true)}"
    fi

    if [[ -n "$id_token" ]]; then
        if payload="$(exchange_codex_id_token "$id_token")"; then
            printf '%s' "$payload"
            return 0
        fi
    fi

    if [[ -n "$refresh_token" ]]; then
        if refresh_codex_tokens "$refresh_token" "$auth_json"; then
            local refreshed_id_token
            refreshed_id_token="$(jq -r '.tokens.id_token // empty' "$auth_json" 2>/dev/null || true)"
            if [[ -n "$refreshed_id_token" ]]; then
                if payload="$(exchange_codex_id_token "$refreshed_id_token")"; then
                    printf '%s' "$payload"
                    return 0
                fi
            fi
        fi
    fi

    return 1
}

resolve_openai_api_key() {
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        printf '%s' "$OPENAI_API_KEY"
        return 0
    fi

    if [[ -f "$CODEX_AUTH_JSON" ]]; then
        local resolved
        resolved="$(resolve_openai_api_key_from_auth_json "$CODEX_AUTH_JSON")"
        if [[ -n "$resolved" ]]; then
            printf '%s' "$resolved"
            return 0
        fi
    fi

    return 1
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        return 0
    fi

    require_commands

    export CODEX_AUTH_JSON

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
