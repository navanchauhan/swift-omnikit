# SwiftUI Non-Renderer Parity Audit

_Generated from `docs/swiftui-non-renderer-parity.json` by `scripts/swiftui_non_renderer_parity.py`._

## Summary

- Baseline: Full public SwiftUI API (validated against the local SwiftUI SDK symbol graph when available)
- Scope: non-renderer SwiftUI compatibility stack only
- API status counts: `supported`: 0, `partial`: 10, `compile-only`: 0, `missing`: 0, `unknown`: 0
- Behavior status counts: `supported`: 0, `partial`: 9, `compile-only`: 1, `missing`: 0, `unknown`: 0
- SwiftUI SDK reference: validated representative patterns against 3043 extracted symbol titles

## Scope

**Included modules**
- `Sources/SwiftUI`
- `Sources/OmniUI`
- `Sources/OmniUICore`
- `Sources/SwiftData`
- `Sources/OmniSwiftUISymbolExtras`

**Supporting targets used as evidence**
- `Sources/SwiftUIMacros`
- `Sources/SwiftDataMacros`
- `Sources/SwiftUICompatibilityHarness`
- `Tests/OmniUICoreTests`

**Excluded from this audit**
- `Sources/OmniUINotcursesRenderer` — Renderer behavior is explicitly out of scope for this audit.
- `Sources/OmniKit` — General utility module, not part of the SwiftUI compatibility surface.

## SwiftUI SDK Baseline

- Source: local `xcrun swift-symbolgraph-extract` extraction of `SwiftUI`
- Extracted symbol graph files: 7
- Unique symbol titles: 3043
- Target triple: `arm64-apple-macosx`
## Taxonomy

- `supported` — API or behavior exists with meaningful semantics and no known category-level gaps.
- `partial` — The category is present, but important APIs are missing or implemented as approximations.
- `compile-only` — The surface mainly keeps call sites compiling; behavior is passthrough, placeholder, or intentionally lightweight.
- `missing` — The category is not present in the non-renderer stack.
- `unknown` — The category has not been audited yet.

## Current Status

| Domain | API | Behavior |
| --- | --- | --- |
| App / Scene / Commands | `partial` | `partial` |
| State / Observation / Environment | `partial` | `partial` |
| Core Views / Controls | `partial` | `partial` |
| Collections / Data-driven Containers | `partial` | `partial` |
| Navigation / Presentation | `partial` | `partial` |
| Layout / Interaction Modifiers | `partial` | `partial` |
| Drawing / Shapes / Animation | `partial` | `partial` |
| Styles / Materials / Platform Bridges | `partial` | `partial` |
| SwiftData Compatibility | `partial` | `partial` |
| Compatibility Macros | `partial` | `compile-only` |

## Domain Breakdown

### App / Scene / Commands

- API status: `partial`
- Behavior status: `partial`
- Summary: App, Scene, and Commands now compose into a concrete OmniUI/notcurses root, with lightweight command-bar and preferred-size metadata support instead of pure compile-time shims.

**Implemented / verified**
- `App`, `Scene`, `WindowGroup`, `Settings`, `CommandGroup`, `SidebarCommands`, `DocumentGroup`, `MenuBarExtra`, and related app/window compile-surface names now exist in the non-renderer stack.
- `SwiftUICompatibilityHarnessApp` exercises `App`, `WindowGroup`, and `.commands { ... }`, while the generated shim catalog covers much more of the app-scene name surface.

**Compile-only / approximated**
- `App.main()` in `OmniUI` now launches the notcurses runner, but lifecycle/window ownership still remains far lighter than Apple SwiftUI platforms.
- `defaultSize(...)` is preserved as preferred-size metadata and command groups are rendered as a lightweight bottom command bar rather than native platform menus.

**Representative missing APIs**
- Real platform lifecycle ownership
- Window launch/resizability semantics
- Command removal semantics
- External-event routing semantics

**SwiftUI SDK reference patterns**
- `App`
- `Scene`
- `WindowGroup`
- `DocumentGroup`
- `MenuBarExtra`
- `OpenWindowAction`

**Evidence**
- `Sources/OmniUICore/AppScene.swift` — Core scene metadata and command composition now feed the portable renderer instead of being discarded.
- `Sources/SwiftUICompatibilityHarness/main.swift` — Compatibility harness exercises the public app/scene surface.
- `Sources/OmniUI/OmniUI.swift` — The OmniUI-facing App entry point now launches the notcurses renderer using extracted scene root/commands metadata.

### State / Observation / Environment

- API status: `partial`
- Behavior status: `partial`
- Summary: Runtime-backed property wrappers and environment access exist, but observation is simplified and the environment surface is selective rather than SwiftUI-complete.

**Implemented / verified**
- `State`, `Binding`, `Environment`, `EnvironmentObject`, `ObservedObject`, `StateObject`, `Bindable`, `FocusState`, `AppStorage`, `Namespace`, and many focused/default-app-storage compile-surface names are present.
- Dismiss/openURL environment actions exist and are used by navigation and keyboard shortcut tests.

**Compile-only / approximated**
- The `@Observable` compatibility macro only adds `ObservableObject` conformance rather than full Observation tracking.
- Observation updates rely on the runtime rebuild model instead of SwiftUI's native dependency graph.

**Representative missing APIs**
- Projected wrapper symbols such as `$document`, `$isExpanded`, `$isOn`, and `$selection`
- Semantic focus/value propagation parity beyond compile surface
- Preference propagation semantics
- Scene-phase behavior parity

**SwiftUI SDK reference patterns**
- `AppStorage`
- `SceneStorage`
- `FocusedValue`
- `scenePhase`
- `onPreferenceChange(`

**Evidence**
- `Sources/OmniUICore/State.swift` — State and binding are runtime-backed rather than compiler-special-cased.
- `Sources/OmniUICore/Environment.swift` — Environment values include a focused subset of common SwiftUI keys.
- `Sources/OmniUICore/ObservableObjects.swift` — Object wrappers exist without Combine or Observation runtime integration.
- `Sources/OmniUICore/SwiftUIPropertyWrappers.swift` — Common property wrappers are available for compatibility-heavy call sites.
- `Sources/OmniUICore/FocusState.swift` — Focus state is modeled explicitly in the portable runtime.
- `Sources/SwiftUI/SwiftUI.swift` — The compatibility module re-exports the `@Observable` macro surface.
- `Sources/SwiftUIMacros/ObservableMacro.swift` — Macro expansion is intentionally minimal.
- `Sources/SwiftUICompatibilityHarness/main.swift` — Harness exercises the public wrapper surface.

### Core Views / Controls

- API status: `partial`
- Behavior status: `partial`
- Summary: The non-renderer stack covers many high-traffic view and control types, but some controls remain stubs or simplified approximations.

**Implemented / verified**
- `Text`, `Image`, `Button`, `Toggle`, `TextField`, `SecureField`, `Picker`, `Menu`, `Label`, `GroupBox`, `LabeledContent`, `ContentUnavailableView`, `ShareLink`, `ProgressView`, `GeometryReader`, `Canvas`, `DatePicker`, `Gauge`, `AsyncImage`, and `TimelineView` are present.
- `SwiftUICompatibilityHarness` exercises `Toggle`, `TextField`, `Menu`, `GroupBox`, `LabeledContent`, `ContentUnavailableView`, `ShareLink`, and `ColorPicker`, while `OmniUICoreTests` now cover the newly added core parity views.

**Compile-only / approximated**
- `ColorPicker` is explicitly described as a minimal stub for SwiftUI compatibility.
- `quickLookPreview(_:)` is a passthrough compatibility modifier rather than a full Quick Look integration.

**Representative missing APIs**
- `DatePickerStyle.Configuration`
- `GaugeStyle.Configuration`
- `AsyncImagePhase.failure(_:)`
- `TimelineViewDefaultContext`

**SwiftUI SDK reference patterns**
- `Button`
- `Toggle`
- `TextField`
- `DatePicker`
- `Gauge`
- `AsyncImage`
- `TimelineView`

**Evidence**
- `Sources/OmniUICore/Primitives.swift` — A broad set of primitive views and controls are implemented in a portable way, including the newer date/gauge/async/timeline surfaces.
- `Sources/OmniUICore/ColorPicker.swift` — ColorPicker now exposes a concrete terminal approximation that cycles a palette through a focusable control.
- `Sources/SwiftUICompatibilityHarness/main.swift` — Harness covers representative control types from the public API surface.
- `Tests/OmniUICoreTests/OmniUICoreTests.swift` — Focused tests cover interactive controls plus the newly added core parity views.

### Collections / Data-driven Containers

- API status: `partial`
- Behavior status: `partial`
- Summary: Lists, forms, grids, tables, and data-driven repetition are available, but identity handling and richer collection APIs are still simplified.

**Implemented / verified**
- `List`, `Form`, `ForEach`, `LazyVGrid`, `Table`, `Section`, and `ScrollViewReader` exist in the non-renderer stack.
- The current test suite covers list rendering, list interaction, on-delete edit mode, and model-backed queries.

**Compile-only / approximated**
- `Table` is currently implemented as a list-backed table approximation rather than a native multi-column SwiftUI table.
- `ForEach` intentionally does not incorporate `id` into the runtime path, so state can move when data reorders.

**Representative missing APIs**
- `TableStyle.Configuration`
- `ForEach.TableRowBody`
- `SectionedFetchResults` iterator/value surfaces
- `Grid` layout semantics beyond compile surface

**SwiftUI SDK reference patterns**
- `List`
- `ForEach`
- `Table`
- `LazyHGrid`
- `GridRow`
- `TableColumn`

**Evidence**
- `Sources/OmniUICore/Primitives.swift` — Collections are present, with table currently funneled through the richer list implementation rather than a separate native table widget.
- `Tests/OmniUICoreTests/OmniUICoreTests.swift` — Existing tests cover row rendering, nested interaction, and delete support.

### Navigation / Presentation

- API status: `partial`
- Behavior status: `partial`
- Summary: Navigation stacks, split views, tabs, alerts, and sheets are implemented with real runtime behavior, but the long-tail navigation and presentation APIs remain absent.

**Implemented / verified**
- `NavigationView`, `NavigationViewStyle`, `NavigationStack`, `NavigationPath`, `NavigationLink`, `NavigationLink(value:)`, `NavigationSplitView`, `TabView`, `.tabItem`, `.sheet`, `.sheet(item:)`, `.popover(isPresented:...)`, `.popover(item:...)`, `.fullScreenCover`, `.alert`, `.confirmationDialog`, and `.navigationDestination(...)` are present.
- The test suite covers adaptive split-view behavior, item-sheet presentation, popovers, confirmation-dialog action capture, and the bool/item/value navigation-destination flows; additional compile-surface names are supplied by generated shims.

**Compile-only / approximated**
- `NavigationLink` outside a `NavigationStack` degrades to an inert button to preserve call-site compatibility.
- Presentation modifiers such as detents and drag indicators exist but remain passthrough wrappers.

**Representative missing APIs**
- `PopoverAttachmentAnchor.point(_:)`
- `PopoverAttachmentAnchor.rect(_:)`
- Navigation transition semantics
- Split-view style semantics

**SwiftUI SDK reference patterns**
- `NavigationStack`
- `NavigationLink`
- `NavigationSplitView`
- `NavigationPath`
- `navigationDestination(`
- `confirmationDialog(`
- `fullScreenCover`
- `popover(`

**Evidence**
- `Sources/OmniUICore/Primitives.swift` — Core navigation containers now include `NavigationView`, a lightweight `NavigationPath`, and value-based links.
- `Sources/OmniUICore/Modifiers.swift` — Overlay/presentation APIs now include item popovers, presented confirmation dialogs, and all three navigation-destination families; detents remain passthrough-only polish.
- `Tests/OmniUICoreTests/OmniUICoreTests.swift` — Focused tests cover split-view adaptation plus the bool/item/value navigation flows and the newer presentation overlays.
- `Sources/SwiftUICompatibilityHarness/main.swift` — Harness exercises toolbar-backed presentation flows.
- `Sources/OmniUICore/SwiftUIStyleProtocols.swift` — The compatibility layer now exposes the core `NavigationViewStyle` names used by older SwiftUI code.

### Layout / Interaction Modifiers

- API status: `partial`
- Behavior status: `partial`
- Summary: The stack/layout core and a growing subset of lifecycle and interaction modifiers are implemented, including terminal-backed search, refresh, disabled-state, help, and exit-command behavior.

**Implemented / verified**
- `HStack`, `VStack`, `ZStack`, `Group`, `.frame(...)`, `.padding(...)`, `.onTapGesture`, `.onAppear`, `.onDisappear`, `.onChange`, `.task`, `.keyboardShortcut`, `.focused(...)`, `.safeAreaInset(...)`, `.searchable`, `.refreshable`, `.disabled`, `.help`, and `.onExitCommand` now have concrete OmniUI/notcurses behavior.
- The current test suite covers tap gestures, keyboard shortcuts, tasks, on-appear lifecycle, search-field editing, refresh actions, disabled controls, Quick Look overlays, and exit-command dispatch.

**Compile-only / approximated**
- Several platform-specific modifiers still lower to `_Passthrough`, including `.onHover`, most text-input platform configuration modifiers, and many gesture/animation compatibility overloads.
- Multi-tap gesture counts are accepted for source compatibility but not behaviorally modeled.

**Representative missing APIs**
- Gesture/drag semantic parity behind the generated compile-surface names
- Matched-geometry runtime behavior
- High-priority/simultaneous gesture conflict resolution
- Drag-and-drop runtime semantics

**SwiftUI SDK reference patterns**
- `safeAreaInset(`
- `task(`
- `onTapGesture(`
- `matchedGeometryEffect(`
- `simultaneousGesture(`
- `highPriorityGesture(`
- `draggable(`

**Evidence**
- `Sources/OmniUICore/Modifiers.swift` — This file now separates concrete terminal-backed modifiers from the remaining passthrough-only platform shims.
- `Tests/OmniUICoreTests/OmniUICoreTests.swift` — Focused tests now cover representative lifecycle, search, refresh, disabled-state, and exit-command behavior.

### Drawing / Shapes / Animation

- API status: `partial`
- Behavior status: `partial`
- Summary: Shape and gradient APIs now emit real render-tree operations for OmniUI/notcurses, while animation-heavy SwiftUI semantics still remain simplified or compile-surface only.

**Implemented / verified**
- `Path`, `Rectangle`, `RoundedRectangle`, `Circle`, `Ellipse`, `Capsule`, `Canvas`, `Gradient`, `LinearGradient`, `RadialGradient`, `Animation`, `AnimationTimelineSchedule`, `NavigationTransition`, `ContentTransition`, many matched/symbol-effect compile-surface names, `withAnimation`, and `.phaseAnimator(...)` are present.
- Canvas now records filled shapes into the render tree, and the gradient views now emit renderer-visible nodes rather than no-op placeholders.

**Compile-only / approximated**
- Arbitrary shape styles are still collapsed to simplified fills, and animation/transition types largely remain terminal-friendly approximations rather than full SwiftUI semantics.
- High-fidelity animation timing, matched-transition behavior, and mesh-gradient semantics are still deferred.

**Representative missing APIs**
- `AnimationTimelineSchedule.Entries` runtime behavior
- Matched-transition semantics
- Glass transition semantics
- Mesh-gradient semantics

**SwiftUI SDK reference patterns**
- `AnimationTimelineSchedule`
- `contentTransition(`
- `navigationTransition(`
- `matchedTransitionSource(`
- `glassEffectTransition(`
- `FillShapeStyle`

**Evidence**
- `Sources/OmniUICore/Drawing.swift` — Drawing APIs now lower to concrete gradient/shape nodes that the render tree and notcurses renderer consume.
- `Sources/OmniUICore/Shapes.swift` — Shapes lower into the render tree, but style fidelity is still intentionally limited.
- `Sources/SwiftUI/Animation.swift` — Animation surface now also exposes an `AnimationTimelineSchedule` shim alongside lightweight animation hooks.
- `Sources/SwiftUICompatibilityHarness/main.swift` — Harness covers the currently implemented public drawing and animation entry points.
- `Sources/OmniUICore/StyleTypes.swift` — Transition shims now exist as public drawing/navigation-adjacent surface types.
- `Sources/OmniUICore/Modifiers.swift` — Transition modifiers now have terminal-friendly approximations instead of pure passthrough shims.

### Styles / Materials / Platform Bridges

- API status: `partial`
- Behavior status: `partial`
- Summary: Style protocols still lean compile-surface, but many style modifiers, glass effects, and representable bridges now produce concrete terminal-visible approximations instead of being ignored.

**Implemented / verified**
- `ButtonStyle`, `ToggleStyle`, `PickerStyle`, `TextFieldStyle`, `DatePickerStyle`, `GaugeStyle`, `ListStyle`, `FormStyle`, `LabelStyle`, `NavigationViewStyle`, `Material`, `GlassEffect`, platform color bridges, representable protocols, and many style-related compile-surface modifiers are present.
- `Color(uiColor:)` and `UIColor(Color)` bridging are available through lightweight cross-platform stand-ins.

**Compile-only / approximated**
- Many style protocol bodies still collapse to simplified terminal renderings rather than full SwiftUI configuration semantics.
- Platform bridges remain placeholder approximations rather than true AppKit/UIKit embedding.

**Representative missing APIs**
- Style-configuration semantic bodies
- Menu/progress/control-group style runtime semantics
- Button border shape rendering semantics
- Representable runtime integration beyond compile surface

**SwiftUI SDK reference patterns**
- `ProgressViewStyle`
- `MenuStyle`
- `ControlGroupStyle`
- `FillShapeStyle`
- `buttonBorderShape(`

**Evidence**
- `Sources/OmniUICore/SwiftUIStyleProtocols.swift` — Style protocols are explicitly called out as compile-surface shims.
- `Sources/OmniUICore/PlatformColors.swift` — Platform color bridges are compile-friendly rather than semantically complete.
- `Sources/OmniUICore/Representable.swift` — Representable protocols now render placeholder type-name nodes instead of disappearing entirely.
- `Sources/OmniUICore/GlassEffect.swift` — The public Liquid Glass types still exist, while the modifier path now maps them to terminal-friendly background/shadow approximations.

### SwiftData Compatibility

- API status: `partial`
- Behavior status: `partial`
- Summary: The SwiftData shim provides a useful in-memory subset for model containers, contexts, and queries, but it intentionally stops far short of full persistence and schema semantics.

**Implemented / verified**
- `SwiftData` re-exports `Schema`, `ModelConfiguration`, `ModelContainer`, `ModelContext`, `Query`, and `SortOrder`.
- `ModelContainer`, `ModelContext`, and `Query` work together in the in-memory compatibility layer and are covered by tests and the harness.

**Compile-only / approximated**
- The top-level `SwiftData` module explicitly states that it exists so common call sites compile on non-Apple platforms.
- Persistence, migrations, and advanced model metadata are intentionally out of scope for the current shim.

**Representative missing APIs**
- `FetchDescriptor`
- `PersistentIdentifier`
- `DeleteRule`
- `ModelActor`

**Evidence**
- `Sources/SwiftData/SwiftData.swift` — The public SwiftData shim is deliberately small and forwarding.
- `Sources/OmniUICore/SwiftDataCompat.swift` — The compatibility layer implements an in-memory data model.
- `Sources/SwiftUICompatibilityHarness/main.swift` — Harness uses the public SwiftData compatibility surface end to end.
- `Tests/OmniUICoreTests/OmniUICoreTests.swift` — The current test suite covers query refresh and model-container stability.

### Compatibility Macros

- API status: `partial`
- Behavior status: `compile-only`
- Summary: The public `SwiftUI` and `SwiftData` modules expose the key macro names needed by portability-focused code, but the expansions are intentionally minimal.

**Implemented / verified**
- `#Preview`, `@Observable`, and `@Model` are available through the compatibility modules.
- `SwiftUICompatibilityHarness` uses both `@Observable` and `@Model`.

**Compile-only / approximated**
- `#Preview` expands to nothing so preview blocks parse and are ignored.
- `@Observable` only adds `ObservableObject` conformance, and `@Model` only adds `Identifiable` conformance.

**Representative missing APIs**
- Generated preview providers or preview metadata
- Observation registrar synthesis
- SwiftData persistence metadata synthesis

**Evidence**
- `Sources/SwiftUI/SwiftUI.swift` — The public SwiftUI compatibility module exposes the expected macro names.
- `Sources/SwiftUIMacros/PreviewMacro.swift` — Preview blocks are intentionally ignored after parsing.
- `Sources/SwiftUIMacros/ObservableMacro.swift` — Observable compatibility is intentionally restricted to `ObservableObject` conformance.
- `Sources/SwiftDataMacros/ModelMacro.swift` — SwiftData models gain just enough synthesis for common list/query call sites.

## Implementation Roadmap

### Wave 1 — Surface Correctness

- Focus domains: `App / Scene / Commands`, `Styles / Materials / Platform Bridges`, `SwiftData Compatibility`, `Compatibility Macros`

**Goals**
- Turn the highest-risk silent passthroughs into explicit, documented compatibility behavior.
- Close the most painful public signature gaps blocking compile-time portability in the app/scene, style, SwiftData, and macro surfaces.
- Keep hard-cutover behavior: prefer clear support or explicit deferral over backward-compat wrappers.

**Acceptance**
- Representative scene, command, style, macro, and SwiftData compile samples build through the compatibility modules.
- The parity manifest cleanly distinguishes implemented behavior from compile-only shims in these domains.

**Verification**
- `python3 scripts/swiftui_non_renderer_parity.py --check`
- `swift build --target SwiftUICompatibilityHarness`

### Wave 2 — Semantic Correctness

- Focus domains: `State / Observation / Environment`, `Core Views / Controls`, `Collections / Data-driven Containers`, `Navigation / Presentation`, `Layout / Interaction Modifiers`

**Goals**
- Strengthen state identity, focus, environment propagation, and lifecycle behavior.
- Improve list/table/grid selection and deletion semantics, then tighten navigation and presentation behavior.
- Replace the most misleading passthrough interaction modifiers with real semantics or explicit deferrals.

**Acceptance**
- Focused `OmniUICoreTests` cover state stability, navigation push/pop, tab selection, modifier lifecycle, and collection updates.
- The compatibility harness can exercise these flows without depending on renderer-specific behavior.

**Verification**
- `swift test --filter OmniUICoreTests`
- `python3 scripts/swiftui_non_renderer_parity.py --check`

### Wave 3 — Visual and Interaction Fidelity

- Focus domains: `Drawing / Shapes / Animation`, `Styles / Materials / Platform Bridges`, `Layout / Interaction Modifiers`, `Core Views / Controls`

**Goals**
- Replace placeholder drawing and style behavior with node-tree semantics that can be consumed consistently by non-renderer runtimes.
- Connect style protocols and materials to meaningful render-tree state instead of pure passthrough wrappers.
- Improve control and layout modifiers whose current behavior is visually misleading compared with SwiftUI.

**Acceptance**
- Shapes, gradients, materials, and style-driven controls no longer degrade to obvious placeholders in the debug/runtime path.
- Animation-related modifiers either change runtime behavior meaningfully or are explicitly documented as deferred.

**Verification**
- `swift test --filter OmniUICoreTests`
- `swift build --target SwiftUICompatibilityHarness`
- `python3 scripts/swiftui_non_renderer_parity.py --check`

### Wave 4 — Public Completeness and Long Tail

- Focus domains: `App / Scene / Commands`, `State / Observation / Environment`, `Core Views / Controls`, `Collections / Data-driven Containers`, `Navigation / Presentation`, `Layout / Interaction Modifiers`, `Drawing / Shapes / Animation`, `Styles / Materials / Platform Bridges`, `SwiftData Compatibility`, `Compatibility Macros`

**Goals**
- Continue pushing toward the full public SwiftUI baseline, or explicitly defer Apple-only APIs so the audit never goes stale.
- Refresh the manifest and generated report after each implementation slice so support levels remain decision-useful.
- Keep parity work balanced across domains instead of optimizing only for the shortest migration path.

**Acceptance**
- Every tracked domain has an up-to-date missing list and a clear support classification.
- The generated Markdown report stays in sync with the manifest and checker output.

**Verification**
- `python3 scripts/swiftui_non_renderer_parity.py --check --write-markdown docs/swiftui-non-renderer-parity.md`

## Repeat the Audit

- `python3 scripts/swiftui_non_renderer_parity.py --swiftui-sdk auto --check` — Validate the manifest and evidence
- `python3 scripts/swiftui_non_renderer_parity.py --swiftui-sdk auto --write-markdown docs/swiftui-non-renderer-parity.md` — Refresh the generated Markdown report
- `swift build --target SwiftUICompatibilityHarness` — Build the public compatibility harness
- `swift test --filter OmniUICoreTests` — Run focused non-renderer tests

