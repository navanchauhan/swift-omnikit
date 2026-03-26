#!/usr/bin/env bash
set -euo pipefail

WAVE_ID="${1:?Usage: tui-test-wave.sh <wave-id>}"
PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Map wave to test cases
case "$WAVE_ID" in
    wave-00) export TUI_TEST_CASES="wave00_home" ;;
    wave-01) export TUI_TEST_CASES="wave01_shapes,wave01_progress" ;;
    wave-02) export TUI_TEST_CASES="wave02_tabview,wave02_form,wave02_table,wave02_grid" ;;
    wave-03) export TUI_TEST_CASES="wave03_tree,wave03_editing,wave03_secure" ;;
    wave-04) export TUI_TEST_CASES="wave04_observable,wave04_swiftdata" ;;
    wave-05) export TUI_TEST_CASES="wave05_animation,wave05_full_demo" ;;
    all) unset TUI_TEST_CASES ;;
    *) echo "Unknown wave: $WAVE_ID"; exit 1 ;;
esac

export TUI_TEST_MODE="${TUI_TEST_MODE:-kitty}"
exec "$PROJ_ROOT/scripts/tui-test.sh"
