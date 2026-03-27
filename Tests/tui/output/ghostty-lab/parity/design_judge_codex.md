# Codex Design Judge Report

**Date:** 2026-03-27  
**Stage:** JudgeCodex  
**Artifacts reviewed:** `Tests/tui/output/ghostty-lab/parity/validation/` screenshots, `design_demo.gif`, current source tree, `swift build`

## Scope note

The validation screenshots still show the regular KitchenSink flow from header through footer. They do **not** directly exercise most of the design-parity features from `design_audit.md` and `consolidated_design.md`. I therefore used the screenshots to confirm the capture set, but I graded the design features from the actual implementation state in `Sources/OmniUICore` and related files.

`swift build` succeeds on the current tree.

## Grades

| Feature | Grade | Evidence |
|---|---|---|
| GeometryReader enhancements | PARTIAL | `GeometryProxy` still exposes only `size`, and `GeometryReader` still approximates from `_currentRenderSize`; there is no `frame(in:)`, `safeAreaInsets`, or proposed-size threading. See `Sources/OmniUICore/Primitives.swift:182-200`. |
| ViewThatFits | FAIL | The render path exists, but child extraction only recognizes a custom `TupleView2<AnyView, AnyView>` and otherwise falls back to a single child, so ordinary `@ViewBuilder` alternatives are not reliably compared. See `Sources/OmniUICore/Primitives.swift:2621-2649`. |
| `.fixedSize()` | PARTIAL | The node, measurement, and draw logic exist, but stack flex classification still unwraps through `.fixedSize` instead of treating it as non-flex, so compression resistance is not reliably enforced in stacks. See `Sources/OmniUICore/RenderTree.swift:513-573` and `Sources/OmniUICore/RenderTree.swift:1115-1120`. |
| `.layoutPriority()` | PARTIAL | Priority-band allocation exists, but only after the current flex gate admits a child. Collective overflow of individually non-flex siblings still bypasses priority. See `Sources/OmniUICore/RenderTree.swift:616-669`. |
| `.alignmentGuide()` | FAIL | The modifier computes and stores an offset, but stack layout never consumes alignment-guide offsets, so the wrapper is effectively a no-op. See `Sources/OmniUICore/Modifiers.swift:2152-2170` and `Sources/OmniUICore/RenderTree.swift:1156-1158`. |
| `.aspectRatio()` | PARTIAL | Fit/fill behavior exists, but it uses a hard-coded `cellAspect = 2.0` instead of a renderer/environment value, and the screenshot set does not include a dedicated validation demo. See `Sources/OmniUICore/RenderTree.swift:1126-1154`. |
| `PreferenceKey` protocol | FAIL | The protocol exists, but the runtime collection/callback lifecycle is effectively dead code. `_setPreferenceRaw`, `_firePreferenceCallbacks`, and `_clearPreferences` are defined but not wired into render/layout. See `Sources/OmniUICore/State.swift:97-102` and `Sources/OmniUICore/Runtime.swift:933-966`. |
| `.preference(key:value:)` | FAIL | The modifier emits `.preferenceNode`, but no pass reduces or stores those values. See `Sources/OmniUICore/Modifiers.swift:2173-2190` and `Sources/OmniUICore/RenderTree.swift:1160-1163`. |
| `.onPreferenceChange()` | FAIL | The modifier registers callbacks, but because preferences are never collected/fired as part of layout, the behavior is not functional. See `Sources/OmniUICore/Modifiers.swift:2193-2211` and `Sources/OmniUICore/Runtime.swift:945-960`. |
| `.anchorPreference()` | WONTFIX | It is still a pure stub in the generated signature sink, and the design consolidation explicitly deferred it indefinitely. See `Sources/OmniUICore/GeneratedSwiftUISignatureSink.swift:418` and `Tests/tui/output/ghostty-lab/parity/consolidated_design.md:510-545`. |
| TextEditor | FAIL | A public `TextEditor` type now exists, but it still returns a single-line `.textField` node, discards its computed multiline stack, and Enter still submits instead of inserting a newline. See `Sources/OmniUICore/Primitives.swift:2652-2695` and `Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift:1176-1185`. |
| AttributedString | FAIL | The public type exists, but `Text.init(_ attributedString:)` drops foreground-color data and converts into plain `_TextSegment`s before rendering. See `Sources/OmniUICore/Primitives.swift:2698-2717`. |
| Text concatenation improvements | FAIL | `Text + Text` stores segments, but `Text._makeNode` immediately joins them into plain text and `_applyTextEnvironment` emits `.text` / stack nodes, not `.styledText`. Per-segment styling is therefore lost. See `Sources/OmniUICore/Primitives.swift:38-83` and `Sources/OmniUICore/Primitives.swift:2183-2205`. |
| `.swipeActions()` | FAIL | The wrapper exists, but it always creates `.swipeActions(..., revealed: false, ...)` and there is no reveal/list-row integration path. See `Sources/OmniUICore/Modifiers.swift:2214-2224`. |
| Tab order control | FAIL | `focusSection()` exists, but public `focusable(...)` remains stubbed and runtime tab traversal still uses plain registration order. See `Sources/OmniUICore/GeneratedSwiftUISignatureSink.swift:623-626` and `Sources/OmniUICore/Runtime.swift:973-995`. |
| `.rotationEffect()` | WONTFIX | It is explicitly implemented as a terminal no-op, which matches the character-grid limitation. See `Sources/OmniUICore/Modifiers.swift:580-582` and `Sources/OmniUICore/RenderTree.swift:1171-1173`. |

## Totals

- PASS: `0`
- PARTIAL: `5`
- FAIL: `9`
- WONTFIX: `2`

## Verdict

`partial_success`

Reason: the current validation screenshot set does not prove the design-parity feature batch, and source inspection shows multiple core items are still stubbed, inert, or only partially implemented. Only `.anchorPreference()` and `.rotationEffect()` qualify as WONTFIX-style outcomes.
