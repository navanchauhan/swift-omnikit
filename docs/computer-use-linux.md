# Computer Use On Linux

This document describes the practical setup for validating OmniKit GUI apps on Linux with CLI-driven accessibility and app-window screenshots.

## Recommended WSL Setup

Install the tools used by the validation loop:

```bash
sudo apt update
sudo apt install at-spi2-core dbus-x11 x11-utils libxtst6 imagemagick scrot gnome-screenshot grim slurp
```

The essential pieces are:

- `at-spi2-core`: Linux accessibility bus.
- `gdbus` / `busctl`: D-Bus inspection and action invocation.
- `xwininfo`: X11 window discovery.
- `libxtst6`: scripted X11 pointer/key events for focus and scroll validation.
- `import`: targeted screenshots from ImageMagick.

`gnome-screenshot`, `grim`, and `scrot` are useful on some desktops, but in WSL they may capture a black root window or fail against Wayland surfaces. For reliable app-window screenshots, launch the app on GTK's X11 backend and use `import -window`.

## Launch Apps For Validation

For WSL, prefer this launch shape:

```bash
GDK_BACKEND=x11 GSK_RENDERER=cairo DISPLAY=:0 \
  .build/x86_64-pc-linux-gnu/debug/ExampleAdwaitaApp
```

For a validation run that should survive after the launching shell exits, detach it explicitly:

```bash
setsid env GDK_BACKEND=x11 GSK_RENDERER=cairo DISPLAY=:0 \
  .build/x86_64-pc-linux-gnu/debug/ExampleAdwaitaApp \
  > /tmp/example-adwaita.log 2>&1 < /dev/null &
```

Why:

- `GDK_BACKEND=x11` makes the GTK window visible to X11 screenshot tools.
- `GSK_RENDERER=cairo` avoids the heavy Mesa/Vulkan software renderer path seen under WSL.
- `DISPLAY=:0` targets WSLg's X server.
- `setsid` avoids accidentally tying the GUI app lifetime to a short-lived validation shell.

For a normal Linux Wayland desktop, omit `GDK_BACKEND=x11` unless screenshot tooling cannot target the window. AT-SPI works with either backend.

## Accessibility Bus

GTK/libadwaita exposes UI through AT-SPI over D-Bus. This is the Linux equivalent of using macOS Accessibility/AX for Computer Use.

Get the AT-SPI bus address:

```bash
A11Y_ADDR=$(
  gdbus call --session \
    --dest org.a11y.Bus \
    --object-path /org/a11y/bus \
    --method org.a11y.Bus.GetAddress |
  sed -E "s/^\('([^']+)'.*/\1/"
)
```

Find the app on the accessibility bus:

```bash
busctl --address="$A11Y_ADDR" list | rg 'ExampleAdwaitaApp|KitchenSinkAdwaita|Omni'
```

Inspect the app tree:

```bash
APP_BUS=:1.456
busctl --address="$A11Y_ADDR" tree "$APP_BUS"
busctl --address="$A11Y_ADDR" introspect "$APP_BUS" /org/a11y/atspi/accessible/root
```

Read root metadata:

```bash
busctl --address="$A11Y_ADDR" get-property \
  "$APP_BUS" /org/a11y/atspi/accessible/root \
  org.a11y.atspi.Accessible Name
```

## Dump The Accessibility Tree

This helper walks the AT-SPI tree using only `busctl`; it does not require `pyatspi`.

```bash
APP_MATCH=ExampleAdwaitaApp python3 - <<'PY'
import os, re, subprocess, sys

def sh(cmd):
    return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()

addr = sh("""gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus --method org.a11y.Bus.GetAddress | sed -E "s/^\\('([^']+)'.*/\\1/" """)
match = os.environ.get("APP_MATCH", "")
dest = None
for line in sh(f"busctl --address='{addr}' list").splitlines():
    if match in line:
        dest = line.split()[0]
        break
if not dest:
    print(f"app not found: {match}", file=sys.stderr)
    sys.exit(1)

def call(path, iface, member, sig="", *args):
    argstr = "" if not sig else " " + sig + "".join(" " + str(a) for a in args)
    return sh(f"busctl --address='{addr}' call {dest} {path} {iface} {member}{argstr}")

def prop(path, iface, name):
    out = sh(f"busctl --address='{addr}' get-property {dest} {path} {iface} {name}")
    if out.startswith("s "):
        return out[2:].strip().strip('"')
    if out.startswith("i "):
        return out.split()[1]
    return out

def children(path):
    try:
        out = call(path, "org.a11y.atspi.Accessible", "GetChildren")
    except Exception:
        return []
    return re.findall(r'"(/(?:dev|org)/[^"]+)"', out)

def role(path):
    try:
        out = call(path, "org.a11y.atspi.Accessible", "GetRoleName")
        return out[2:].strip().strip('"') if out.startswith("s ") else out
    except Exception:
        return "?"

def actions(path):
    try:
        n = prop(path, "org.a11y.atspi.Action", "NActions")
        if not str(n).isdigit() or int(n) == 0:
            return []
        out = call(path, "org.a11y.atspi.Action", "GetActions")
        values = re.findall(r'"([^"]*)"', out)
        return values[0::3]
    except Exception:
        return []

seen = set()
queue = [("/org/a11y/atspi/accessible/root", 0)]
while queue and len(seen) < 400:
    path, depth = queue.pop(0)
    if path in seen:
        continue
    seen.add(path)
    try:
        name = prop(path, "org.a11y.atspi.Accessible", "Name")
        description = prop(path, "org.a11y.atspi.Accessible", "Description")
    except Exception:
        name, description = "", ""
    print(f"{'  ' * depth}{role(path):18} name={(name or description)!r} actions={actions(path)} path={path}")
    for child in children(path):
        queue.append((child, depth + 1))
PY
```

Expected useful entries include toolbar buttons, segmented controls, list rows, settings controls, and modal controls. For a web-heavy app, the app chrome should expose controls such as `Back`, `Forward`, `Refresh`, `Home`, `Settings`, and `Login` when those controls exist.

## Click A Control By Accessible Name

Use AT-SPI `Action.DoAction(0)` for buttons and other actionable controls:

```bash
APP_MATCH=ExampleAdwaitaApp TARGET_NAME=Settings TARGET_ROLE=button python3 - <<'PY'
import os, re, subprocess, sys

def sh(cmd):
    return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()

addr = sh("""gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus --method org.a11y.Bus.GetAddress | sed -E "s/^\\('([^']+)'.*/\\1/" """)
app_match = os.environ["APP_MATCH"]
target_name = os.environ["TARGET_NAME"]
target_role = os.environ.get("TARGET_ROLE")
dest = next((line.split()[0] for line in sh(f"busctl --address='{addr}' list").splitlines() if app_match in line), None)
if not dest:
    print(f"app not found: {app_match}", file=sys.stderr)
    sys.exit(1)

def call(path, iface, member, sig="", *args):
    argstr = "" if not sig else " " + sig + "".join(" " + str(a) for a in args)
    return sh(f"busctl --address='{addr}' call {dest} {path} {iface} {member}{argstr}")

def prop(path, iface, name):
    out = sh(f"busctl --address='{addr}' get-property {dest} {path} {iface} {name}")
    if out.startswith("s "):
        return out[2:].strip().strip('"')
    if out.startswith("i "):
        return int(out.split()[1])
    return out

def children(path):
    try:
        return re.findall(r'"(/(?:dev|org)/[^"]+)"', call(path, "org.a11y.atspi.Accessible", "GetChildren"))
    except Exception:
        return []

def role(path):
    try:
        out = call(path, "org.a11y.atspi.Accessible", "GetRoleName")
        return out[2:].strip().strip('"') if out.startswith("s ") else out
    except Exception:
        return "?"

def action_count(path):
    try:
        return prop(path, "org.a11y.atspi.Action", "NActions")
    except Exception:
        return 0

queue = ["/org/a11y/atspi/accessible/root"]
seen = set()
while queue:
    path = queue.pop(0)
    if path in seen:
        continue
    seen.add(path)
    try:
        name = prop(path, "org.a11y.atspi.Accessible", "Name")
    except Exception:
        name = ""
    if name == target_name and (target_role is None or role(path) == target_role) and action_count(path) > 0:
        print(f"click {target_role or role(path)} {name}: {path}")
        print(call(path, "org.a11y.atspi.Action", "DoAction", "i", 0))
        sys.exit(0)
    queue.extend(children(path))

print(f"target not found: role={target_role!r} name={target_name!r}", file=sys.stderr)
sys.exit(1)
PY
```

Examples:

```bash
APP_MATCH=ExampleAdwaitaApp TARGET_ROLE=button TARGET_NAME=Settings python3 click-helper.py
APP_MATCH=ExampleAdwaitaApp TARGET_ROLE=button TARGET_NAME=Dark python3 click-helper.py
APP_MATCH=ExampleAdwaitaApp TARGET_ROLE=button TARGET_NAME=Light python3 click-helper.py
APP_MATCH=ExampleAdwaitaApp TARGET_ROLE=button TARGET_NAME=Close python3 click-helper.py
```

`click-helper.py` refers to the Python body in the preceding block if you choose to save it as a file. If not, rerun the heredoc block with the desired `TARGET_NAME` and `TARGET_ROLE` environment variables.

## System Appearance

For GTK/libadwaita apps, prefer the desktop setting path when validating app response to system appearance:

```bash
gsettings get org.gnome.desktop.interface color-scheme
gsettings range org.gnome.desktop.interface color-scheme
gsettings set org.gnome.desktop.interface color-scheme prefer-dark
gsettings set org.gnome.desktop.interface color-scheme default
```

Some environments also support `prefer-light`; check `gsettings range` first before using it.

For app-level settings exposed by the application, use AT-SPI instead. A typical appearance validation path is:

```text
Settings -> Appearance -> Light/Dark -> Close
```

The corresponding AT-SPI controls are visible as:

```text
button "Settings" actions=["Click"]
label "Appearance"
button "Light" actions=["Click"]
button "Dark" actions=["Click"]
button "Close" actions=["Click"]
```

## Targeted Window Screenshots In WSL

When the app is launched with `GDK_BACKEND=x11`, find the app window:

```bash
DISPLAY=:0 xwininfo -root -tree | rg -i 'Example|Adwaita'
```

Typical output:

```text
0x200032 (has no name): () 1264x846+162+-18
   0x800005 "Example": ("ExampleAdwaitaApp" "ExampleAdwaitaApp") 1200x800+32+32
```

Capture the decorated frame:

```bash
DISPLAY=:0 import -window 0x200032 /tmp/example-frame.png
```

Capture only the app content:

```bash
DISPLAY=:0 import -window 0x800005 /tmp/example-content.png
```

Alternative using `xwd`:

```bash
DISPLAY=:0 xwd -silent -id 0x800005 -out /tmp/example.xwd
convert /tmp/example.xwd /tmp/example-content.png
```

Expected result:

```text
/tmp/example-frame.png: PNG image data, 1264 x 846, 8-bit/color RGB
/tmp/example-content.png: PNG image data, 1200 x 800, 8-bit/color RGB
```

## What Not To Use In WSL

These may be useful on a full desktop, but were not reliable for WSL validation in this environment:

- `grim`: failed because the compositor did not expose `wlr-screencopy-unstable-v1`.
- `gnome-screenshot`: fell back to X11 and failed.
- `scrot` full desktop: captured a black root window.
- `scrot -u`: failed without an active X drawable in this setup.

If a screenshot is black, the app is probably running as a Wayland surface while the screenshot tool is reading the X11 root. Relaunch with `GDK_BACKEND=x11`.

## Scripted WebView Focus And Scroll

WebKitGTK content may not receive keyboard scroll events until the app window and the web pane have focus. For WSL/X11 validation, set focus to the app window, click inside the web content area, then send `Page_Down`.

Use `xwininfo` to get the app window ID and position:

```bash
DISPLAY=:0 xwininfo -root -tree | rg -i 'Example|Adwaita'
```

Then send focus and page scroll events:

```bash
WINDOW_ID=0x800005 python3 - <<'PY'
import ctypes, os, time

x11 = ctypes.CDLL("libX11.so.6")
xtst = ctypes.CDLL("libXtst.so.6")

x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XSetInputFocus.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
x11.XStringToKeysym.argtypes = [ctypes.c_char_p]
x11.XStringToKeysym.restype = ctypes.c_ulong
x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x11.XKeysymToKeycode.restype = ctypes.c_uint
x11.XFlush.argtypes = [ctypes.c_void_p]
xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]

display = x11.XOpenDisplay(b":0")
window = int(os.environ["WINDOW_ID"], 16)
x11.XSetInputFocus(display, window, 2, 0)

# Root coordinates inside the web pane. Adjust for the window position from xwininfo.
xtst.XTestFakeMotionEvent(display, -1, 900, 620, 0)
x11.XFlush(display)
time.sleep(0.1)
xtst.XTestFakeButtonEvent(display, 1, 1, 0)
xtst.XTestFakeButtonEvent(display, 1, 0, 0)
x11.XFlush(display)
time.sleep(0.2)

page_down = x11.XKeysymToKeycode(display, x11.XStringToKeysym(b"Page_Down"))
for _ in range(4):
    xtst.XTestFakeKeyEvent(display, page_down, 1, 0)
    xtst.XTestFakeKeyEvent(display, page_down, 0, 0)
    x11.XFlush(display)
    time.sleep(0.2)
PY
```

This is the reliable path used to validate WebKitGTK post/document and comments-style scrolling under WSL. Plain wheel events may be ignored if WebKit has not accepted focus yet.

## Validation Checklist

For a clean app validation run:

1. Build the app.
2. Kill any old process for the app.
3. Launch with:

   ```bash
   GDK_BACKEND=x11 GSK_RENDERER=cairo DISPLAY=:0 .build/x86_64-pc-linux-gnu/debug/ExampleAdwaitaApp
   ```

4. Confirm it appears on AT-SPI:

   ```bash
   busctl --address="$A11Y_ADDR" list | rg ExampleAdwaitaApp
   ```

5. Dump the accessibility tree and confirm expected controls.
6. Use AT-SPI to click `Settings`, `Dark`, `Light`, and `Close`.
7. Use AT-SPI to click a story row.
8. Confirm article/comment controls expose actions such as `Back`, `Forward`, `Refresh`, `Home`, `Reader Mode`, `Share`, and `Open in browser`.
9. Capture the app window:

   ```bash
   DISPLAY=:0 import -window "$WINDOW_ID" /tmp/example-validation.png
   ```

10. Check process sanity:

    ```bash
    ps -eo pid,ppid,comm,rss,args | rg 'ExampleAdwaitaApp|WebKitWebProcess|WebKitNetworkProcess'
    ```

For WebKit-heavy flows, a small number of WebKit helper processes is normal after opening pages. Hundreds of `WebKitWebProcess` children indicates a lifecycle leak.
