# Counter increment test — Tab to [+] button, press Enter 3x
# $WID must be set to the kitty X11 window ID

# Tab to the first focusable element ([+] button)
xdotool key --window "$WID" Tab
sleep 0.2

# Press Enter 3 times to increment counter to 3
xdotool key --window "$WID" Return
sleep 0.2
xdotool key --window "$WID" Return
sleep 0.2
xdotool key --window "$WID" Return
sleep 0.5
