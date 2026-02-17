# Navigation test — Tab to "Open details", push, interact, go back
# Focus order: [+], [-], Toggle, TextField, Picker, Pick(0), Pick(1),
#   Model+1, Model-1, [Model name], Observed+1, Open details
# = 12 Tabs from unfocused state

# Tab through all focusable elements to reach "Open details"
for i in $(seq 1 12); do
    xdotool key Tab
    sleep 0.1
done
sleep 0.3

# Press Enter to navigate to detail screen
xdotool key Return
sleep 1

# Take a screenshot of the detail screen
import -window root "$OUTPUT_DIR/navigation_detail.png" 2>/dev/null || true

# Tab to "Local +1" and increment
xdotool key Tab; sleep 0.1  # Back
xdotool key Tab; sleep 0.2  # Local +1
xdotool key Return; sleep 0.2
xdotool key Return; sleep 0.5

# Screenshot: Local: 2
import -window root "$OUTPUT_DIR/navigation_local_inc.png" 2>/dev/null || true

# Tab to "Push next" and go to level 2
xdotool key Tab; sleep 0.2  # Push next
xdotool key Return; sleep 1

# Screenshot: level 2
import -window root "$OUTPUT_DIR/navigation_level2.png" 2>/dev/null || true

# Escape back to level 1
xdotool key Escape; sleep 0.5

# Escape back to main
xdotool key Escape; sleep 0.5
