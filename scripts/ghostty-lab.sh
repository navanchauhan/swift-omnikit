#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVICE_NAME="ghostty-lab"

compose() {
    GHOSTTY_LAB_HOST_WORKSPACE="$PROJECT_ROOT" docker compose -f "$PROJECT_ROOT/docker-compose.yml" "$@"
}

launch_in_terminal() {
    local command_text="$1"
    exec_lab ghostty-lab-control focus
    # Stop any currently running foreground TUI before typing a new command.
    exec_lab ghostty-lab-control key ctrl+c || true
    sleep 0.2
    exec_lab ghostty-lab-control key ctrl+l || true
    sleep 0.1
    exec_lab ghostty-lab-control type "$command_text"
    exec_lab ghostty-lab-control key Return
}

container_id() {
    compose ps -q "$SERVICE_NAME"
}

require_container() {
    local cid
    cid="$(container_id)"
    if [[ -z "$cid" ]]; then
        printf 'ghostty-lab is not running. Start it with: %s up\n' "$0" >&2
        exit 1
    fi
}

exec_lab() {
    require_container
    compose exec -T "$SERVICE_NAME" "$@"
}

copy_from_container() {
    local source_path="$1"
    local destination_path="$2"
    local cid
    cid="$(container_id)"
    mkdir -p "$(dirname "$destination_path")"
    docker cp "${cid}:${source_path}" "$destination_path"
}

usage() {
    cat <<'EOF'
Usage: scripts/ghostty-lab.sh <command> [args...]

Commands:
  up [--no-build]         Start the Alpine Ghostty GUI lab
  down                    Stop and remove the lab container
  logs                    Follow lab logs
  status                  Print compose and Ghostty status
  shell                   Open a shell inside the lab container
  wait-ready [seconds]    Wait until Ghostty is ready for control
  run-kitchensink         Build/run KitchenSink in Ghostty via sibling Docker runtime
  run-igopher             Run iGopherTUI in Ghostty via sibling Docker runtime
  type <text>             Type text into Ghostty
  key <key...>            Send xdotool key presses
  click <x> <y> [button]  Click inside the Ghostty window
  drag <x1> <y1> <x2> <y2> [button]
  screenshot [host-path]  Capture the full X display
  window-screenshot [host-path]
  record-gif [seconds] [host-path] [fps]
  smoke                   Run a quick end-to-end control proof
EOF
}

save_capture() {
    local mode="$1"
    local destination="${2:-$PROJECT_ROOT/Tests/tui/output/ghostty-lab/${mode}-$(date +%Y%m%d-%H%M%S).png}"
    local remote="/tmp/${mode}-capture.png"

    exec_lab ghostty-lab-control "$mode" "$remote" >/dev/null
    copy_from_container "$remote" "$destination"
    printf '%s\n' "$destination"
}

command_name="${1:-}"
if [[ -z "$command_name" ]]; then
    usage
    exit 1
fi
shift

case "$command_name" in
    up)
        build_flag="--build"
        if [[ "${1:-}" == "--no-build" ]]; then
            build_flag=""
        fi
        compose up -d ${build_flag:+$build_flag} "$SERVICE_NAME"
        ;;
    down)
        compose rm -sf "$SERVICE_NAME"
        ;;
    logs)
        compose logs -f "$SERVICE_NAME"
        ;;
    status)
        compose ps "$SERVICE_NAME"
        if [[ -n "$(container_id)" ]]; then
            exec_lab ghostty-lab-control status
        fi
        ;;
    shell)
        require_container
        compose exec "$SERVICE_NAME" /bin/bash
        ;;
    wait-ready)
        exec_lab ghostty-lab-control wait-ready "${1:-30}"
        ;;
    run-kitchensink)
        launch_in_terminal "bash scripts/ghostty-kitchensink-run.sh"
        ;;
    run-igopher)
        launch_in_terminal "bash scripts/ghostty-igopher-run.sh"
        ;;
    type)
        exec_lab ghostty-lab-control type "$*"
        ;;
    key)
        exec_lab ghostty-lab-control key "$@"
        ;;
    click)
        exec_lab ghostty-lab-control click "$@"
        ;;
    drag)
        exec_lab ghostty-lab-control drag "$@"
        ;;
    screenshot)
        save_capture screenshot "${1:-}"
        ;;
    window-screenshot)
        save_capture window-screenshot "${1:-}"
        ;;
    record-gif)
        require_container
        duration="${1:-8}"
        output_path="${2:-$PROJECT_ROOT/Tests/tui/output/ghostty-lab/kitchensink-$(date +%Y%m%d-%H%M%S).gif}"
        fps="${3:-4}"
        if [[ ! "$duration" =~ ^[0-9]+$ ]] || [[ ! "$fps" =~ ^[0-9]+$ ]] || (( duration < 1 )) || (( fps < 1 )); then
            printf 'record-gif requires positive integer duration and fps\n' >&2
            exit 1
        fi
        frame_count=$((duration * fps))
        delay=$((100 / fps))
        remote_frames_dir="/workspace/Tests/tui/output/ghostty-lab/.gif-frames"
        remote_gif="/workspace/Tests/tui/output/ghostty-lab/.recording.gif"
        exec_lab sh -lc "rm -rf '$remote_frames_dir' && mkdir -p '$remote_frames_dir' && rm -f '$remote_gif'"
        for i in $(seq 1 "$frame_count"); do
            frame_name="$(printf 'frame-%04d.png' "$i")"
            exec_lab ghostty-lab-control window-screenshot "$remote_frames_dir/$frame_name" >/dev/null
            sleep "$(awk "BEGIN { printf \"%.3f\", 1 / $fps }")"
        done
        exec_lab sh -lc "magick -delay $delay -loop 0 '$remote_frames_dir'/frame-*.png '$remote_gif'"
        copy_from_container "$remote_gif" "$output_path"
        printf '%s\n' "$output_path"
        ;;
    smoke)
        compose up -d --build "$SERVICE_NAME"
        exec_lab ghostty-lab-control wait-ready 60
        exec_lab ghostty-lab-control type "printf 'GHOSTTY_LAB_SMOKE\\n'"
        exec_lab ghostty-lab-control key Return
        sleep 1
        screenshot_path="$(save_capture window-screenshot "$PROJECT_ROOT/Tests/tui/output/ghostty-lab/smoke.png")"
        if curl -fsS "http://127.0.0.1:${GHOSTTY_LAB_HOST_NOVNC_PORT:-6080}/vnc.html" >/dev/null; then
            printf 'Smoke ok. Screenshot: %s\n' "$screenshot_path"
        else
            printf 'Smoke screenshot captured, but noVNC check failed.\n' >&2
            exit 1
        fi
        ;;
    *)
        usage
        exit 1
        ;;
esac
