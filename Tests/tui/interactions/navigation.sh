# Navigation test — Tab to "Open details", push, verify, go back
# $WID must be set to the kitty X11 window ID

# Tab through all focusable elements to reach "Open details"
# Order: [+], [-], toggle, textfield, picker, pick0, pick1, model+1, model-1,
#        model-name, observed+1, open-details
for i in $(seq 1 12); do
    xdotool key --window "$WID" Tab
    sleep 0.1
done
sleep 0.3

# Press Enter to navigate to detail screen
xdotool key --window "$WID" Return
sleep 1

# Take a mid-test screenshot (detail screen visible)
import -window "$WID" "$OUTPUT_DIR/navigation_detail.png" 2>/dev/null || true

# Press Escape to go back
xdotool key --window "$WID" Escape
sleep 0.5
