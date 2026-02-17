# Text input test — Tab to text field, type text, verify binding
# $WID must be set to the kitty X11 window ID

# Tab to text field: [+], [-], toggle, textfield
xdotool key --window "$WID" Tab
sleep 0.1
xdotool key --window "$WID" Tab
sleep 0.1
xdotool key --window "$WID" Tab
sleep 0.1
xdotool key --window "$WID" Tab
sleep 0.3

# Type "hello" (avoid 'q' which quits the app)
xdotool type --window "$WID" --delay 50 "hello"
sleep 0.5
