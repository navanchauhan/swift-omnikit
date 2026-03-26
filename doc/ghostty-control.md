# Ghostty KitchenSink Control Guide

This document explains how to start the Alpine Ghostty lab, launch the real Linux `KitchenSink` runtime, drive it with keyboard and mouse input, and capture screenshots or GIFs.

Use this as the operator handoff for any agent that needs to validate SwiftTUI behavior against a real terminal emulator instead of only static render output.

## What this setup is

This harness is split into two containers on purpose:

- `Dockerfile.ghostty` provides the visible GUI terminal lab: Alpine Linux, Ghostty, Xvfb, Openbox, VNC/noVNC, `xdotool`, and screenshot tooling.
- `Dockerfile.kitchensink-runtime` provides the actual Linux Swift runtime: Swift nightly on Jammy plus notcurses built from source, with `KitchenSink` compiled and run using `--notcurses`.

The Ghostty lab container talks to the host Docker daemon through `/var/run/docker.sock` and launches the runtime container from inside the terminal session. That is what makes the terminal view real Ghostty while still keeping the Swift/notcurses runtime on a cleaner Linux base.

## Files involved

- `Dockerfile.ghostty`
- `Dockerfile.kitchensink-runtime`
- `docker-compose.yml`
- `scripts/ghostty-lab-entrypoint.sh`
- `scripts/ghostty-lab-control.sh`
- `scripts/ghostty-lab.sh`
- `scripts/ghostty-kitchensink-run.sh`

## Quick start

From the repo root:

```sh
scripts/ghostty-lab.sh up
scripts/ghostty-lab.sh wait-ready
scripts/ghostty-lab.sh run-kitchensink
```

At that point Ghostty will be open fullscreen inside the Xvfb desktop and `KitchenSink` will be running inside it through the sibling runtime container.

To inspect the current state:

```sh
scripts/ghostty-lab.sh status
```

To stop the lab:

```sh
scripts/ghostty-lab.sh down
```

## How the runtime launch works

`scripts/ghostty-lab.sh run-kitchensink` does two things:

1. Focuses the Ghostty window.
2. Types and executes:

```sh
clear && bash scripts/ghostty-kitchensink-run.sh
```

`scripts/ghostty-kitchensink-run.sh` then:

- optionally builds `swift-omnikit-kitchensink-runtime` from `Dockerfile.kitchensink-runtime`
- mounts the host repo path into the runtime container
- launches:

```sh
/app/.build/aarch64-unknown-linux-gnu/debug/KitchenSink --notcurses
```

stderr is redirected to:

```sh
Tests/tui/output/ghostty-lab/kitchensink.stderr.log
```

An empty stderr log is expected for the known-good notcurses run.

## Control surface

All host-side control goes through:

```sh
scripts/ghostty-lab.sh <command> ...
```

Available commands:

- `up [--no-build]`
- `down`
- `logs`
- `status`
- `shell`
- `wait-ready [seconds]`
- `run-kitchensink`
- `type <text>`
- `key <key...>`
- `click <x> <y> [button]`
- `drag <x1> <y1> <x2> <y2> [button]`
- `screenshot [host-path]`
- `window-screenshot [host-path]`
- `record-gif [seconds] [host-path] [fps]`
- `smoke`

Inside the running lab container, the lower-level control command is:

```sh
ghostty-lab-control <command> ...
```

That exposes:

- `wait-ready`
- `status`
- `window-id`
- `focus`
- `type`
- `key`
- `move`
- `click`
- `double-click`
- `drag`
- `screenshot`
- `window-screenshot`

## Keyboard input

Examples:

```sh
scripts/ghostty-lab.sh type "swift test"
scripts/ghostty-lab.sh key Return
scripts/ghostty-lab.sh key Tab
scripts/ghostty-lab.sh key Tab Return
```

Notes:

- `type` sends literal text through `xdotool type`.
- `key` sends key names through `xdotool key`.
- The wrapper focuses Ghostty before sending input.

## Mouse input

Examples:

```sh
scripts/ghostty-lab.sh click 200 200
scripts/ghostty-lab.sh click 300 400 3
scripts/ghostty-lab.sh drag 300 300 900 300
```

Notes:

- Coordinates are relative to the fullscreen Ghostty window.
- Default window size is `1440x900`.
- Button defaults to `1` if omitted.

## Screenshots

Capture the full display:

```sh
scripts/ghostty-lab.sh screenshot
```

Capture just the Ghostty window:

```sh
scripts/ghostty-lab.sh window-screenshot
```

To write to a specific host path:

```sh
scripts/ghostty-lab.sh window-screenshot /tmp/ghostty-proof.png
```

Default artifact directory:

```sh
Tests/tui/output/ghostty-lab
```

## GIF recording

Record a GIF from the Ghostty window:

```sh
scripts/ghostty-lab.sh record-gif 8 Tests/tui/output/ghostty-lab/my-run.gif 4
```

Arguments:

- duration in seconds
- output path on the host
- fps

Important:

- `record-gif` captures repeated window screenshots and assembles them with ImageMagick.
- It does not inject input by itself.
- For a useful GIF, start recording in one terminal and send input from another terminal while it is recording.

Example:

Terminal 1:

```sh
scripts/ghostty-lab.sh record-gif 8 Tests/tui/output/ghostty-lab/kitchensink-demo.gif 4
```

Terminal 2:

```sh
scripts/ghostty-lab.sh key Return
scripts/ghostty-lab.sh key Tab Tab Return
scripts/ghostty-lab.sh key Tab
scripts/ghostty-lab.sh type "Navan"
```

## Known-good KitchenSink interaction sequence

This sequence was live-proved against the real notcurses path:

```sh
scripts/ghostty-lab.sh up
scripts/ghostty-lab.sh wait-ready
scripts/ghostty-lab.sh run-kitchensink
```

Wait for `KitchenSink` to finish launching, then:

```sh
scripts/ghostty-lab.sh key Return
scripts/ghostty-lab.sh key Tab Tab Return
scripts/ghostty-lab.sh key Tab
scripts/ghostty-lab.sh type "Navan"
scripts/ghostty-lab.sh window-screenshot /tmp/kitchensink-proof.png
```

Expected visible results:

- counter increments from `0` to `1`
- `CRT` toggles from `OFF` to `ON`
- text field contains `Navan`
- greeting updates to `Hello, Navan`

## Known-good artifacts

These are the important artifacts already generated in this repo:

- `Tests/tui/output/ghostty-lab/kitchensink-live.gif`
- `Tests/tui/output/ghostty-lab/kitchensink.stderr.log`
- `Tests/tui/output/ghostty-lab/smoke.png`

Use `kitchensink-live.gif` as the real proof artifact.

Do not use `kitchensink.gif` as the reference artifact. That is the earlier bad capture from the fallback renderer path.

## noVNC / remote viewing

The lab exposes:

- VNC on `localhost:5900`
- noVNC on `http://127.0.0.1:6080/vnc.html`

That is useful if an operator wants to watch the Ghostty session live while another process drives it.

## Environment knobs

Useful environment variables:

- `GHOSTTY_LAB_HOST_VNC_PORT`
- `GHOSTTY_LAB_HOST_NOVNC_PORT`
- `GHOSTTY_LAB_COMMAND`
- `GHOSTTY_KITCHENSINK_IMAGE`
- `GHOSTTY_KITCHENSINK_DOCKERFILE`
- `GHOSTTY_KITCHENSINK_BUILD_IMAGE`
- `GHOSTTY_KITCHENSINK_STDERR_LOG`
- `OMNIUI_SMOKE_SECONDS`
- `OMNIUI_DEMO_ANIM`
- `NCLOGLEVEL`

Examples:

Skip rebuilding the runtime image on every launch:

```sh
GHOSTTY_KITCHENSINK_BUILD_IMAGE=0 scripts/ghostty-lab.sh run-kitchensink
```

Change the noVNC host port:

```sh
GHOSTTY_LAB_HOST_NOVNC_PORT=6081 scripts/ghostty-lab.sh up
```

## Troubleshooting

If Ghostty never becomes ready:

```sh
scripts/ghostty-lab.sh logs
scripts/ghostty-lab.sh status
```

If `KitchenSink` does not launch:

- confirm the lab is up
- confirm `/var/run/docker.sock` is mounted
- confirm the runtime image builds successfully
- inspect `Tests/tui/output/ghostty-lab/kitchensink.stderr.log`

If the UI shows the footer:

```text
Click simulation: type x y and press enter
```

that is the fallback renderer, not the good notcurses path. The known-good setup should not show that footer.

If you want to debug inside the lab container:

```sh
scripts/ghostty-lab.sh shell
ghostty-lab-control status
```

## Recommended operator flow for another agent

1. Start the lab with `scripts/ghostty-lab.sh up`.
2. Wait for readiness with `scripts/ghostty-lab.sh wait-ready`.
3. Launch the app with `scripts/ghostty-lab.sh run-kitchensink`.
4. Interact with `key`, `type`, `click`, and `drag`.
5. Capture `window-screenshot` after meaningful state changes.
6. When a full proof is needed, record a GIF in one terminal and drive input from another.
7. Treat `kitchensink-live.gif` as the reference for a good run.
