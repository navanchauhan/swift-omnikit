# Counter increment test
# Focus order: [+], [-], Toggle, TextField, Picker, ...
# First Tab from unfocused state lands on [+]
# $WID is set by the test runner but xdotool works with focused window

# Focus [+] button (first focusable element)
xdotool key Tab
sleep 0.3

# Press Enter 3 times to increment counter to 3
xdotool key Return; sleep 0.2
xdotool key Return; sleep 0.2
xdotool key Return; sleep 0.5

# Take a mid-screenshot showing counter at 3
import -window root "$OUTPUT_DIR/counter_increment_mid.png" 2>/dev/null || true

# Tab to [-] and decrement once (counter should show 2)
xdotool key Tab; sleep 0.2
xdotool key Return; sleep 0.5
