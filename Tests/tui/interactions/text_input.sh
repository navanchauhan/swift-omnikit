# Text input test
# Focus order: [+], [-], Toggle, TextField, Picker, ...
# Tab 4 times from unfocused to reach TextField

# Tab to text field: [+] → [-] → Toggle → TextField
xdotool key Tab; sleep 0.1  # [+]
xdotool key Tab; sleep 0.1  # [-]
xdotool key Tab; sleep 0.1  # Toggle
xdotool key Tab; sleep 0.3  # TextField

# Type text (avoid 'q' which quits the app when not in text editing mode)
xdotool type --delay 40 "OmniUI"
sleep 0.5

# Take a mid-screenshot showing text + greeting binding
import -window root "$OUTPUT_DIR/text_input_typed.png" 2>/dev/null || true

# Test backspace (delete last char)
xdotool key BackSpace; sleep 0.2
xdotool key BackSpace; sleep 0.5
