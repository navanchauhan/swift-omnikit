#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/OmniUIAdwaitaSmoke.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
EXECUTABLE="$ROOT_DIR/.build/debug/OmniUIAdwaitaSmoke"

cd "$ROOT_DIR"
xcrun swift build --product OmniUIAdwaitaSmoke

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>OmniUIAdwaitaSmoke</string>
  <key>CFBundleExecutable</key>
  <string>OmniUIAdwaitaSmoke</string>
  <key>CFBundleIdentifier</key>
  <string>dev.omnikit.OmniUIAdwaitaSmokeApp</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>OmniUIAdwaitaSmoke</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cat > "$MACOS_DIR/OmniUIAdwaitaSmoke" <<LAUNCHER
#!/usr/bin/env bash
cd "$ROOT_DIR"
exec "$EXECUTABLE"
LAUNCHER
chmod +x "$MACOS_DIR/OmniUIAdwaitaSmoke"

open "$APP_DIR"
