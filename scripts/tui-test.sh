#!/usr/bin/env bash
# TUI Validation Harness
# Runs notcurses renderer tests inside Docker (Kitty + Xvfb) or locally.
#
# Environment variables:
#   TUI_TEST_MODE            all|smoke|kitty|vhs (default: all)
#   TUI_TEST_UPDATE_BASELINES  1 to capture new baselines (default: 0)
#   OMNIUI_SMOKE_SECONDS     Smoke timeout in seconds (default: 5)
#   DISPLAY                  X display for Xvfb (default: :99)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

MODE="${TUI_TEST_MODE:-all}"
UPDATE_BASELINES="${TUI_TEST_UPDATE_BASELINES:-0}"
BASELINE_DIR="Tests/tui/baselines"
OUTPUT_DIR="Tests/tui/output"
DISPLAY="${DISPLAY:-:99}"
SMOKE_SECONDS="${OMNIUI_SMOKE_SECONDS:-5}"
FAILURES=0
PASSES=0
SKIPS=0

mkdir -p "$OUTPUT_DIR" "$BASELINE_DIR"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

log()  { echo -e "${CYAN}[tui-test]${RESET} $*"; }
pass() { echo -e "  ${GREEN}PASS${RESET}: $*"; PASSES=$((PASSES + 1)); }
fail() { echo -e "  ${RED}FAIL${RESET}: $*"; FAILURES=$((FAILURES + 1)); }
skip() { echo -e "  ${YELLOW}SKIP${RESET}: $*"; SKIPS=$((SKIPS + 1)); }

# ── Build ─────────────────────────────────────────────────────────────────────
BIN_PATH="$(swift build --show-bin-path 2>/dev/null)"
KITCHEN_SINK="${BIN_PATH}/KitchenSink"

if [ ! -f "$KITCHEN_SINK" ]; then
    log "KitchenSink not found at $KITCHEN_SINK, building..."
    swift build --product KitchenSink 2>&1 | tail -5
    KITCHEN_SINK="$(swift build --show-bin-path)/KitchenSink"
fi

if [ ! -f "$KITCHEN_SINK" ]; then
    log "FATAL: KitchenSink binary not found"
    exit 1
fi
log "Binary: $KITCHEN_SINK"

# ── Xvfb management ──────────────────────────────────────────────────────────
XVFB_PID=""

start_xvfb() {
    if ! command -v Xvfb &>/dev/null; then
        log "Xvfb not found, skipping X11 setup"
        return 1
    fi
    Xvfb "$DISPLAY" -screen 0 1280x720x24 -ac +extension GLX &
    XVFB_PID=$!
    export DISPLAY
    # Wait for Xvfb to be ready
    for i in $(seq 1 20); do
        xdpyinfo -display "$DISPLAY" &>/dev/null && break
        sleep 0.25
    done
    log "Xvfb started on $DISPLAY (pid $XVFB_PID)"
}

stop_xvfb() {
    if [ -n "$XVFB_PID" ]; then
        kill "$XVFB_PID" 2>/dev/null || true
        wait "$XVFB_PID" 2>/dev/null || true
        XVFB_PID=""
    fi
}

# ── Screenshot comparison ─────────────────────────────────────────────────────
compare_screenshot() {
    local name="$1"
    local phase="$2"
    local baseline="$BASELINE_DIR/${name}_${phase}.png"
    local actual="$OUTPUT_DIR/${name}_${phase}.png"

    if [ ! -f "$actual" ]; then
        fail "${name}_${phase} — no screenshot captured"
        return
    fi

    if [ "$UPDATE_BASELINES" = "1" ]; then
        cp "$actual" "$baseline"
        log "  Baseline updated: ${name}_${phase}"
        return
    fi

    if [ ! -f "$baseline" ]; then
        skip "${name}_${phase} — no baseline (run with TUI_TEST_UPDATE_BASELINES=1)"
        return
    fi

    # Use odiff if available, fall back to ImageMagick compare
    if command -v odiff &>/dev/null; then
        if odiff --threshold 0.1 "$baseline" "$actual" "$OUTPUT_DIR/${name}_${phase}_diff.png" 2>/dev/null; then
            pass "${name}_${phase}"
        else
            fail "${name}_${phase} — differs from baseline (diff: $OUTPUT_DIR/${name}_${phase}_diff.png)"
        fi
    elif command -v compare &>/dev/null; then
        local metric
        metric=$(compare -metric AE "$baseline" "$actual" "$OUTPUT_DIR/${name}_${phase}_diff.png" 2>&1 || true)
        if [ "${metric:-99999}" -lt 100 ]; then
            pass "${name}_${phase}"
        else
            fail "${name}_${phase} — $metric pixels differ"
        fi
    else
        skip "${name}_${phase} — no comparison tool (install odiff or imagemagick)"
    fi
}

# ── Kitty test runner ─────────────────────────────────────────────────────────
run_kitty_test() {
    local test_name="$1"
    local interaction_script="${2:-}"
    local render_delay="${3:-3}"

    log "Kitty test: $test_name"

    # Launch kitty running KitchenSink
    OMNIUI_SMOKE_SECONDS=30 kitty \
        --config NONE \
        -o font_family="DejaVu Sans Mono" \
        -o font_size=12 \
        -o initial_window_width=120c \
        -o initial_window_height=40c \
        -o confirm_os_window_close=0 \
        -o background="#0B1020" \
        -o foreground="#D8DBE2" \
        -e "$KITCHEN_SINK" --notcurses &
    local kitty_pid=$!

    # Wait for the kitty X11 window to appear
    local wid=""
    for i in $(seq 1 40); do
        wid=$(xdotool search --name "kitty" 2>/dev/null | head -1) && [ -n "$wid" ] && break
        sleep 0.25
    done

    if [ -z "$wid" ]; then
        fail "$test_name — kitty window never appeared"
        kill "$kitty_pid" 2>/dev/null || true
        return
    fi

    # Wait for initial render
    sleep "$render_delay"

    # Capture initial screenshot
    import -window "$wid" "$OUTPUT_DIR/${test_name}_initial.png" 2>/dev/null \
        || scrot -w "$wid" "$OUTPUT_DIR/${test_name}_initial.png" 2>/dev/null \
        || true

    # Run interaction script if provided
    if [ -n "$interaction_script" ] && [ -f "$interaction_script" ]; then
        WID="$wid" source "$interaction_script"
    fi

    # Capture final screenshot
    sleep 1
    import -window "$wid" "$OUTPUT_DIR/${test_name}_final.png" 2>/dev/null \
        || scrot -w "$wid" "$OUTPUT_DIR/${test_name}_final.png" 2>/dev/null \
        || true

    # Clean up
    kill "$kitty_pid" 2>/dev/null || true
    wait "$kitty_pid" 2>/dev/null || true

    # Compare
    compare_screenshot "$test_name" "initial"
    compare_screenshot "$test_name" "final"
}

# ── Smoke test ────────────────────────────────────────────────────────────────
run_smoke_test() {
    log "Smoke test (OMNIUI_SMOKE_SECONDS=$SMOKE_SECONDS)"

    if command -v kitty &>/dev/null && command -v Xvfb &>/dev/null; then
        # Full smoke: run in kitty via Xvfb
        OMNIUI_SMOKE_SECONDS="$SMOKE_SECONDS" timeout 30 kitty \
            --config NONE \
            -o confirm_os_window_close=0 \
            -e "$KITCHEN_SINK" --notcurses 2>/dev/null
        local rc=$?
    else
        # Fallback: headless smoke (may hang if notcurses_init blocks without a terminal)
        OMNIUI_SMOKE_SECONDS="$SMOKE_SECONDS" timeout 30 "$KITCHEN_SINK" --notcurses </dev/null 2>/dev/null
        local rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        pass "smoke test (rc=0, exited cleanly)"
    else
        fail "smoke test (rc=$rc)"
    fi
}

# ── VHS tests ─────────────────────────────────────────────────────────────────
run_vhs_tests() {
    log "VHS tape tests"

    if ! command -v vhs &>/dev/null; then
        skip "VHS not installed"
        return
    fi

    local found=0
    for tape in Tests/tui/tapes/*.tape; do
        [ -f "$tape" ] || continue
        found=1
        local name
        name="$(basename "$tape" .tape)"
        log "  Running tape: $name"
        if vhs "$tape" 2>&1 | tail -3; then
            pass "vhs/$name"
        else
            fail "vhs/$name"
        fi
    done

    if [ "$found" -eq 0 ]; then
        skip "no .tape files found in Tests/tui/tapes/"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
log "Mode: $MODE"
echo ""

# Start Xvfb if needed for kitty/smoke tests
if [[ "$MODE" == "all" || "$MODE" == "smoke" || "$MODE" == "kitty" ]]; then
    start_xvfb || true
fi

trap stop_xvfb EXIT

case "$MODE" in
    smoke)
        run_smoke_test
        ;;
    kitty)
        run_smoke_test
        run_kitty_test "home_screen" "" 3
        run_kitty_test "counter_increment" "Tests/tui/interactions/counter_increment.sh" 2
        run_kitty_test "navigation" "Tests/tui/interactions/navigation.sh" 2
        run_kitty_test "text_input" "Tests/tui/interactions/text_input.sh" 2
        ;;
    vhs)
        run_vhs_tests
        ;;
    all)
        run_smoke_test
        echo ""
        if [ -n "$XVFB_PID" ]; then
            run_kitty_test "home_screen" "" 3
            run_kitty_test "counter_increment" "Tests/tui/interactions/counter_increment.sh" 2
            run_kitty_test "navigation" "Tests/tui/interactions/navigation.sh" 2
            run_kitty_test "text_input" "Tests/tui/interactions/text_input.sh" 2
        else
            skip "Kitty tests — Xvfb not available"
        fi
        echo ""
        run_vhs_tests
        ;;
    *)
        echo "Unknown mode: $MODE"
        echo "Usage: TUI_TEST_MODE=all|smoke|kitty|vhs $0"
        exit 1
        ;;
esac

echo ""
log "Results: ${GREEN}$PASSES passed${RESET}, ${RED}$FAILURES failed${RESET}, ${YELLOW}$SKIPS skipped${RESET}"
exit "$FAILURES"
