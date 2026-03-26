#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[ghostty-lab] %s\n' "$*"
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf '[ghostty-lab] missing required command: %s\n' "$1" >&2
        exit 1
    fi
}

pick_window_id() {
    local pid="$1"
    local best_wid=""
    local best_area=0
    local candidate=""
    local geometry=""
    local width=""
    local height=""
    local area=0

    while read -r candidate; do
        [[ -n "$candidate" ]] || continue
        geometry="$(xwininfo -id "$candidate" 2>/dev/null || true)"
        width="$(printf '%s\n' "$geometry" | awk '/Width:/ { print $2; exit }')"
        height="$(printf '%s\n' "$geometry" | awk '/Height:/ { print $2; exit }')"
        [[ -n "$width" && -n "$height" ]] || continue
        area=$((width * height))
        if (( area > best_area )); then
            best_area="$area"
            best_wid="$candidate"
        fi
    done < <(xdotool search --pid "$pid" 2>/dev/null || true)

    printf '%s\n' "$best_wid"
}

window_area() {
    local wid="$1"
    local geometry=""
    local width=""
    local height=""

    geometry="$(xwininfo -id "$wid" 2>/dev/null || true)"
    width="$(printf '%s\n' "$geometry" | awk '/Width:/ { print $2; exit }')"
    height="$(printf '%s\n' "$geometry" | awk '/Height:/ { print $2; exit }')"
    if [[ -z "$width" || -z "$height" ]]; then
        printf '0\n'
        return
    fi
    printf '%s\n' "$((width * height))"
}

DISPLAY_VALUE="${DISPLAY:-:99}"
SCREEN="${GHOSTTY_LAB_SCREEN:-1440x900x24}"
STATE_DIR="${GHOSTTY_LAB_STATE_DIR:-/tmp/ghostty-lab}"
ARTIFACT_DIR="${GHOSTTY_LAB_ARTIFACT_DIR:-/workspace/Tests/tui/output/ghostty-lab}"
WORKDIR="${GHOSTTY_LAB_WORKDIR:-/workspace}"
COMMAND_TEXT="${GHOSTTY_LAB_COMMAND:-exec bash -li}"
WAIT_SECONDS="${GHOSTTY_LAB_WINDOW_WAIT_SECONDS:-30}"
FULLSCREEN="${GHOSTTY_LAB_FULLSCREEN:-1}"
ENABLE_VNC="${GHOSTTY_LAB_ENABLE_VNC:-1}"
VNC_PORT="${GHOSTTY_LAB_VNC_PORT:-5900}"
NOVNC_PORT="${GHOSTTY_LAB_NOVNC_PORT:-6080}"

mkdir -p "$STATE_DIR" "$ARTIFACT_DIR" "$STATE_DIR/logs"

for tool in Xvfb xdpyinfo dbus-daemon openbox ghostty xdotool wmctrl; do
    require_cmd "$tool"
done

cleanup() {
    set +e
    for pid_file in \
        "$STATE_DIR/ghostty.pid" \
        "$STATE_DIR/openbox.pid" \
        "$STATE_DIR/xvfb.pid" \
        "$STATE_DIR/x11vnc.pid" \
        "$STATE_DIR/novnc.pid"; do
        if [[ -f "$pid_file" ]]; then
            pid="$(cat "$pid_file" 2>/dev/null || true)"
            if [[ -n "${pid:-}" ]]; then
                kill "$pid" 2>/dev/null || true
                wait "$pid" 2>/dev/null || true
            fi
            rm -f "$pid_file"
        fi
    done
}

trap cleanup EXIT INT TERM

export DISPLAY="$DISPLAY_VALUE"
cd "$WORKDIR"

log "starting Xvfb on $DISPLAY ($SCREEN)"
Xvfb "$DISPLAY" -screen 0 "$SCREEN" -ac +extension GLX +render -noreset \
    >"$STATE_DIR/logs/xvfb.log" 2>&1 &
echo "$!" >"$STATE_DIR/xvfb.pid"

for _ in $(seq 1 80); do
    if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done

if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    log "Xvfb never became ready"
    exit 1
fi

DBUS_SESSION_BUS_ADDRESS="$(dbus-daemon --session --fork --print-address)"
export DBUS_SESSION_BUS_ADDRESS
printf '%s\n' "$DBUS_SESSION_BUS_ADDRESS" >"$STATE_DIR/dbus-address"

log "starting Openbox"
openbox >"$STATE_DIR/logs/openbox.log" 2>&1 &
echo "$!" >"$STATE_DIR/openbox.pid"

if [[ "$ENABLE_VNC" == "1" ]]; then
    require_cmd x11vnc
    require_cmd novnc_server

    log "starting x11vnc on port $VNC_PORT"
    x11vnc \
        -display "$DISPLAY" \
        -forever \
        -shared \
        -nopw \
        -rfbport "$VNC_PORT" \
        >"$STATE_DIR/logs/x11vnc.log" 2>&1 &
    echo "$!" >"$STATE_DIR/x11vnc.pid"

    log "starting noVNC on port $NOVNC_PORT"
    novnc_server \
        --listen "$NOVNC_PORT" \
        --vnc "127.0.0.1:${VNC_PORT}" \
        >"$STATE_DIR/logs/novnc.log" 2>&1 &
    echo "$!" >"$STATE_DIR/novnc.pid"
fi

log "launching Ghostty with command: $COMMAND_TEXT"
ghostty \
    --gtk-single-instance=false \
    -e /bin/bash -lc "$COMMAND_TEXT" \
    >"$STATE_DIR/logs/ghostty.log" 2>&1 &
GHOSTTY_PID="$!"
echo "$GHOSTTY_PID" >"$STATE_DIR/ghostty.pid"

WINDOW_ID=""
for _ in $(seq 1 $((WAIT_SECONDS * 4))); do
    WINDOW_ID="$(pick_window_id "$GHOSTTY_PID")"
    if [[ -n "$WINDOW_ID" ]] && [[ "$(window_area "$WINDOW_ID")" -ge 10000 ]]; then
        break
    fi
    sleep 0.25
done

if [[ -z "$WINDOW_ID" ]]; then
    log "Ghostty window never appeared"
    cat "$STATE_DIR/logs/ghostty.log" >&2 || true
    exit 1
fi

printf '%s\n' "$WINDOW_ID" >"$STATE_DIR/window-id"
printf '%s\n' "$DISPLAY" >"$STATE_DIR/display"
printf '%s\n' "$WORKDIR" >"$STATE_DIR/workdir"
printf '%s\n' "$ARTIFACT_DIR" >"$STATE_DIR/artifact-dir"

xdotool windowactivate --sync "$WINDOW_ID" >/dev/null 2>&1 || true

if [[ "$FULLSCREEN" == "1" ]]; then
    wmctrl -ir "$WINDOW_ID" -b add,fullscreen >/dev/null 2>&1 || true
fi

log "ready: pid=$GHOSTTY_PID window=$WINDOW_ID display=$DISPLAY"
if [[ "$ENABLE_VNC" == "1" ]]; then
    log "noVNC: http://localhost:${NOVNC_PORT}/vnc.html"
    log "VNC:   localhost:${VNC_PORT}"
fi

wait "$GHOSTTY_PID"
