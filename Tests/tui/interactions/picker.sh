# Picker test — Tab to picker, expand it, navigate options
# Focus order: [+], [-], Toggle, TextField, Picker
# = 5 Tabs from unfocused state

# Tab to Picker
xdotool key Tab; sleep 0.1  # [+]
xdotool key Tab; sleep 0.1  # [-]
xdotool key Tab; sleep 0.1  # Toggle
xdotool key Tab; sleep 0.1  # TextField
xdotool key Tab; sleep 0.3  # Picker

# Screenshot: Picker focused
import -window root "$OUTPUT_DIR/picker_focused.png" 2>/dev/null || true

# Press Enter/Space to expand the picker dropdown
xdotool key Return
sleep 1

# Screenshot: Picker expanded with options visible
import -window root "$OUTPUT_DIR/picker_expanded.png" 2>/dev/null || true

# Navigate down to select a different option
xdotool key Down; sleep 0.3
import -window root "$OUTPUT_DIR/picker_option_down.png" 2>/dev/null || true

# Select the option
xdotool key Return; sleep 0.5
import -window root "$OUTPUT_DIR/picker_selected.png" 2>/dev/null || true
