#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_DIR="${TMPDIR:-/tmp}/omniui-adwaita-huge-smoke"

rm -rf "$SMOKE_DIR"
mkdir -p "$SMOKE_DIR/Sources/HugeSmoke"

cat > "$SMOKE_DIR/Package.swift" <<PACKAGE
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OmniUIAdwaitaHugeSmoke",
    products: [
        .executable(name: "HugeSmoke", targets: ["HugeSmoke"])
    ],
    dependencies: [
        .package(name: "OmniKit", path: "$ROOT_DIR")
    ],
    targets: [
        .executableTarget(
            name: "HugeSmoke",
            dependencies: [
                .product(name: "OmniUIAdwaita", package: "OmniKit")
            ]
        )
    ]
)
PACKAGE

cat > "$SMOKE_DIR/Sources/HugeSmoke/main.swift" <<'SWIFT'
import Foundation
import OmniUIAdwaita

@main
struct HugeSmokeApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Text("Huge gopher renderer smoke")
                    .font(.headline)
                Text(String(repeating: "Gopher text payload. ", count: 8_000))
                    .frame(minHeight: 180)
                List(0..<5_000, id: \.self) { index in
                    Button("gopher://example/\(index)") {}
                }
            }
            .padding(16)
            .frame(width: 960, height: 720)
        }
    }
}
SWIFT

cd "$SMOKE_DIR"
swift build --product HugeSmoke >/tmp/omniui-adwaita-huge-smoke-build.log

if command -v xvfb-run >/dev/null 2>&1; then
    start="$(date +%s)"
    timeout 8s xvfb-run -a -s "-screen 0 1280x900x24" sh -c '
        OMNIUI_ADWAITA_DUMP_SEMANTIC=1 \
        OMNIUI_COLOR_SCHEME=dark \
        GTK_A11Y=none \
        GDK_BACKEND=x11 \
        .build/debug/HugeSmoke >/tmp/omniui-adwaita-huge-smoke.log 2>&1 &
        pid=$!
        sleep 3
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    '
    status="$?"
    end="$(date +%s)"
    echo "HUGE_SMOKE_STATUS=$status"
    echo "HUGE_SMOKE_SECONDS=$((end - start))"
    wc -l /tmp/omniui-adwaita-huge-smoke.log
    grep -n "Huge gopher renderer smoke" /tmp/omniui-adwaita-huge-smoke.log | head -3
    grep -n "container(OmniUICore.SemanticContainerRole.list)" /tmp/omniui-adwaita-huge-smoke.log | head -3
    grep -n "gopher://example/4999" /tmp/omniui-adwaita-huge-smoke.log | head -3
else
    echo "xvfb-run is required for the native Adwaita runtime smoke." >&2
    exit 1
fi
