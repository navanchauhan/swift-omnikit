# Sprint 009 Intent: KitchenSink Attractor Run — Making OmniUI TUI Features Real

## Seed

Create an attractor run (using the existing AttractorTaskExecutor pattern) that systematically makes all KitchenSink TUI features work. Group features into logical implementation waves, each with clear validation criteria (new baselines, interaction scripts). Prioritize by impact and dependency order.

## Context

- OmniUI provides a 1:1 SwiftUI API surface with 99.3% symbol coverage (2994/3011), but many features are compile-only stubs or crude approximations.
- KitchenSink (`Sources/KitchenSink/main.swift`) is the exhaustive demo exercising every feature.
- The NotcursesRenderer (`Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift`) handles actual terminal rendering via the notcurses C library.
- A comprehensive TUI test infrastructure exists: smoke tests, Kitty pixel-baseline tests with odiff, Ghostty-lab interactive validation, VHS tape recordings, and interaction scripts.
- The Attractor framework (`Sources/TheAgentWorker/Attractor/`) provides plan→implement→validate structured workflows with human gates and artifact collection.

## Audit Results (from KitchenSink evaluation)

### Working well (no changes needed)
- Core layout: VStack, HStack, Spacer, ZStack, ScrollView
- Interactive controls: Button, Toggle, TextField, Picker (native notcurses widgets)
- Navigation: NavigationStack, NavigationLink, toolbar rendering (top + bottom)
- Reactivity: @State, bindings, .task modifier
- Text/styling: .foregroundStyle, .bold, .background with opacity
- Lists: Basic List, ForEach, row separators, selection
- Colors: Primary/secondary/tertiary styles

### Partially working (need fixes)
1. **Shapes** — tiny sprixel dots in Ghostty, Unicode outlines in debug; need proper filled rendering with cell-based fill
2. **TabView** — tab switching works but panels lack visual separation (no borders/clear content area)
3. **NavigationSplitView** — works but column width is coarse (`ideal/8` approximation)
4. **LazyVGrid** — not lazy, simplified column calculation
5. **List(children:)** — tree renders but expand/collapse is rudimentary
6. **EditButton/.onDelete** — terminal approximation, not clearly actionable
7. **ProgressView** — text-based bar only, no spinner character cycling
8. **Form(.grouped)** — renders as ScrollView>VStack, no inset group styling
9. **Label systemImage** — Unicode fallback text, not SF Symbol glyphs
10. **SecureField** — exists but ncreader may not mask input characters

### Not working / no-ops (need implementation)
1. **Animation/withAnimation** — executes body immediately, no frame interpolation
2. **.scaleEffect** — maps to bold if >1, else no-op
3. **.clipShape** — accepted but no visual clip in terminal
4. **@Observable/@Model macros** — compile-only (adds protocol conformance, no observation tracking)
5. **SwiftData** — in-memory shim only, no @Query runtime, no FetchDescriptor
6. **Gesture system** — compile surface only, no drag/gesture behavior
7. **Transitions** — none
8. **AsyncImage** — fires URL, shows image name text only
9. **Preference propagation** — missing entirely
10. **LazyHGrid, Grid/GridRow** — missing
11. **Table** — renders as list, not multi-column

## Relevant Codebase Areas

- **OmniUICore views/modifiers**:
  - `Sources/OmniUICore/Modifiers.swift` — environment-based modifiers (many pass-through)
  - `Sources/OmniUICore/Primitives.swift` — all view implementations
  - `Sources/OmniUICore/View.swift`, `ViewBuilder.swift` — core view protocol and result builder
  - `Sources/OmniUICore/State.swift` — @State, @Binding, @Environment
- **Renderer**:
  - `Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift` — notcurses render loop, event polling, widget mapping
- **SwiftUI compatibility layer**:
  - `Sources/SwiftUI/SwiftUI.swift` — re-exports and macro definitions
  - `Sources/SwiftUI/Animation.swift` — animation stubs
  - `Sources/SwiftUIMacros/` — macro implementations
- **KitchenSink demo**:
  - `Sources/KitchenSink/main.swift` — the test harness exercising all features
- **Test infrastructure**:
  - `scripts/tui-test.sh`, `scripts/tui-test-local.sh` — test runners
  - `Tests/tui/baselines/` — golden pixel baselines
  - `Tests/tui/interactions/` — xdotool interaction scripts
  - `Tests/tui/tapes/` — VHS tape recordings
  - `scripts/ghostty-lab.sh`, `scripts/ghostty-lab-control.sh` — Ghostty lab orchestration
- **Attractor framework**:
  - `Sources/TheAgentWorker/Attractor/AttractorTaskExecutor.swift`
  - `Sources/TheAgentWorker/Attractor/AttractorWorkflowTemplate.swift`
- **Parity docs**:
  - `docs/swiftui-non-renderer-parity.md`
  - `docs/swiftui-non-renderer-symbol-diff.md`

## Constraints

- Must follow project conventions: Swift 6.0+, strict concurrency, no third-party frameworks without approval.
- OmniUI modifiers and views must maintain SwiftUI API compatibility — signatures must match.
- NotcursesRenderer is the only real renderer; changes must work within notcurses capabilities (cell-based grid, optional Kitty graphics protocol for pixel content).
- Terminal is fundamentally cell-based — "animation" means tick-driven re-render, not 60fps interpolation. Acceptable TUI animation = spinner cycling, progress bar advancing, highlight pulsing.
- Shapes in terminal = cell fills with Unicode block/braille characters, not vector graphics.
- Test infrastructure must remain Docker-compatible for CI (Xvfb + Kitty for pixel tests).
- KitchenSink must remain a single main.swift file that exercises everything.
- Each wave must produce updated baselines and pass `scripts/tui-test.sh` smoke + kitty modes.

## Success Criteria

This sprint is successful if:
1. Every KitchenSink section renders meaningfully in the notcurses renderer (no blank/invisible sections).
2. All "partially working" items produce visually distinct, recognizable terminal output.
3. Core "not working" items have real behavior: animation tick loop drives visual changes, @Observable triggers re-renders, Table renders columns, Grid lays out items.
4. New pixel baselines are captured for each wave and pass odiff comparison.
5. New interaction scripts validate stateful features (tab switching, tree expand/collapse, form editing, table scrolling).
6. The attractor run DOT graph is executable and produces artifacts (screenshots, diffs, pass/fail) at each validation gate.

## Verification Strategy

- **Per-wave smoke test**: `OMNIUI_SMOKE_SECONDS=5 ./KitchenSink --notcurses` exits cleanly.
- **Per-wave pixel baselines**: `TUI_TEST_MODE=kitty scripts/tui-test.sh` with updated baselines.
- **Per-wave interaction scripts**: New scripts in `Tests/tui/interactions/` for each feature group.
- **Ghostty-lab visual proof**: `scripts/ghostty-lab.sh record-gif` captures before/after for each wave.
- **Attractor artifact collection**: Each pipeline stage produces screenshot artifacts, stderr logs, and diff reports.

## Uncertainty Assessment

- **Correctness uncertainty**: Low — SwiftUI behavior is well-documented; terminal approximations have clear "good enough" targets.
- **Scope uncertainty**: Medium — 21 features across partial/broken categories; some (SwiftData, Gestures) may be descoped to compile-only-with-documentation rather than full implementation.
- **Architecture uncertainty**: Low — extends existing OmniUICore/NotcursesRenderer patterns; no new modules needed.

## Open Questions

1. Should SwiftData/@Query get real in-memory query support, or is compile-only + documented limitation acceptable?
2. Should gestures map to terminal mouse events (click, drag, scroll), or remain compile-only stubs?
3. What is the acceptable terminal approximation for `.clipShape`? (Options: border style change, color inversion at boundary, or documented no-op)
4. Should the attractor run be a single DOT graph with all waves, or separate DOT graphs per wave with a meta-orchestrator?
5. For AsyncImage: should it fetch and render images via Kitty graphics protocol, or is placeholder text acceptable?
