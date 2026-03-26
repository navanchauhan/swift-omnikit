#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${GHOSTTY_LAB_STATE_DIR:-/tmp/ghostty-lab}"
ARTIFACT_DIR="${GHOSTTY_LAB_ARTIFACT_DIR:-/workspace/Tests/tui/output/ghostty-lab}"
DISPLAY_VALUE="${DISPLAY:-$(cat "$STATE_DIR/display" 2>/dev/null || printf ':99')}"
TYPE_DELAY_MS="${GHOSTTY_LAB_TYPE_DELAY_MS:-20}"

mkdir -p "$ARTIFACT_DIR"
export DISPLAY="$DISPLAY_VALUE"

usage() {
    cat <<'EOF'
Usage: ghostty-lab-control <command> [args...]

Commands:
  wait-ready [timeout-seconds]
  status
  window-id
  focus
  type <text>
  key <xdotool-key...>
  move <x> <y>
  click <x> <y> [button]
  double-click <x> <y> [button]
  drag <x1> <y1> <x2> <y2> [button]
  screenshot [path]
  window-screenshot [path]
EOF
}

window_id() {
    cat "$STATE_DIR/window-id"
}

wait_ready() {
    local timeout="${1:-30}"
    local deadline=$((SECONDS + timeout))
    local wid=""
    local geometry=""
    local width=""
    local height=""

    while (( SECONDS < deadline )); do
        if [[ -s "$STATE_DIR/window-id" ]]; then
            wid="$(window_id)"
            geometry="$(xwininfo -id "$wid" 2>/dev/null || true)"
            width="$(printf '%s\n' "$geometry" | awk '/Width:/ { print $2; exit }')"
            height="$(printf '%s\n' "$geometry" | awk '/Height:/ { print $2; exit }')"
            if [[ -n "$width" && -n "$height" ]] && (( width * height >= 10000 )); then
                return 0
            fi
        fi
        sleep 0.25
    done

    printf 'Ghostty lab did not become ready within %ss\n' "$timeout" >&2
    return 1
}

focus_window() {
    local wid
    wid="$(window_id)"
    xdotool windowactivate --sync "$wid"
}

make_capture_path() {
    local prefix="$1"
    printf '%s/%s-%s.png\n' "$ARTIFACT_DIR" "$prefix" "$(date +%Y%m%d-%H%M%S)"
}

window_screenshot() {
    local target="${1:-$(make_capture_path window)}"
    local wid
    wid="$(window_id)"
    rm -f "$target"
    focus_window
    scrot -w "$wid" "$target"
    printf '%s\n' "$target"
}

screen_screenshot() {
    local target="${1:-$(make_capture_path screen)}"
    rm -f "$target"
    scrot "$target"
    printf '%s\n' "$target"
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

command_name="$1"
shift

case "$command_name" in
    wait-ready)
        wait_ready "${1:-30}"
        ;;
    status)
        wait_ready "${1:-30}"
        printf 'display=%s\n' "$DISPLAY"
        current_window_id="$(window_id)"
        printf 'window_id=%s\n' "$current_window_id"
        if [[ -f "$STATE_DIR/ghostty.pid" ]]; then
            printf 'ghostty_pid=%s\n' "$(cat "$STATE_DIR/ghostty.pid")"
        fi
        if [[ -f "$STATE_DIR/workdir" ]]; then
            printf 'workdir=%s\n' "$(cat "$STATE_DIR/workdir")"
        fi
        if [[ -f "$STATE_DIR/artifact-dir" ]]; then
            printf 'artifact_dir=%s\n' "$(cat "$STATE_DIR/artifact-dir")"
        fi
        if command -v xwininfo >/dev/null 2>&1; then
            xwininfo -id "$current_window_id" | sed -n '1,12p'
        fi
        ;;
    window-id)
        wait_ready
        window_id
        ;;
    focus)
        wait_ready
        focus_window
        ;;
    type)
        wait_ready
        focus_window
        xdotool type --delay "$TYPE_DELAY_MS" "$*"
        ;;
    key)
        wait_ready
        focus_window
        xdotool key "$@"
        ;;
    move)
        wait_ready
        xdotool mousemove --sync "$1" "$2"
        ;;
    click)
        wait_ready
        xdotool mousemove --sync "$1" "$2"
        xdotool click "${3:-1}"
        ;;
    double-click)
        wait_ready
        xdotool mousemove --sync "$1" "$2"
        xdotool click --repeat 2 --delay 100 "${3:-1}"
        ;;
    drag)
        wait_ready
        button="${5:-1}"
        xdotool mousemove --sync "$1" "$2"
        xdotool mousedown "$button"
        xdotool mousemove --sync "$3" "$4"
        xdotool mouseup "$button"
        ;;
    screenshot)
        wait_ready
        screen_screenshot "${1:-}"
        ;;
    window-screenshot)
        wait_ready
        window_screenshot "${1:-}"
        ;;
    *)
        usage
        exit 1
        ;;
esac
