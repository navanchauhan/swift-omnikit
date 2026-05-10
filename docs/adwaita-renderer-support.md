# OmniUI Adwaita Renderer Support

The Adwaita backend lowers OmniUI's `_VNode` tree through `SemanticSnapshot` and `SemanticNode` into GTK/libadwaita widgets. It is a native widget renderer, not a drawing-surface renderer.

Apps can use the `OmniUIAdwaita` facade product as a backend-selecting drop-in for the package's default `OmniUI` facade: it re-exports OmniUI core symbols and gives `App.main()` the Adwaita renderer. Apps can also launch through `AdwaitaApp(scene:)` for explicit scene wiring or through the named `App.adwaitaMain(...)` helper when the app type has a default initializer. The helper is deliberately named so it can live alongside the existing notcurses `App.main()` entry point without changing the default `OmniUI` product behavior.

Scene `.defaultSize(width:height:)` metadata is read by `AdwaitaApp(scene:)` and forwarded to the native GTK window default size. Compact terminal-style sizes are scaled to practical pixels; pixel-sized scene defaults are used directly for the native window while the semantic snapshot receives a cell-like size derived from those pixels. That keeps shared layout primitives such as `NavigationSplitView` from treating a native 1100 px window as 1100 terminal columns.

`OmniUIAdwaitaSmoke` is a small executable that imports only `OmniUIAdwaita` and uses an `@main App` entry point, which verifies the facade-style drop-in path. `OmniUIAdwaitaSwiftUISmoke` is stricter: its source imports `SwiftUI` and `SwiftData`, and the target builds with `-module-alias SwiftUI=OmniUIAdwaita` plus `-module-alias SwiftData=OmniSwiftData` so the same facade is exercised through a SwiftUI-shaped import while still covering SwiftData model/query/container wiring. `scripts/run-omniui-adwaita-smoke-app.sh` and `scripts/run-omniui-adwaita-swiftui-smoke-app.sh` wrap the smoke executables in minimal macOS `.app` bundles so Computer Use can see and verify the native GTK windows.

`KitchenSinkAdwaita` is the broader BrowserView-subset demo. `scripts/run-kitchensink-adwaita-app.sh` wraps it in a minimal macOS `.app` bundle with the `dev.omnikit.KitchenSinkAdwaita` bundle identifier so the same Computer Use path can exercise the full native GTK/libadwaita kitchen sink rather than a raw terminal-launched executable.

## Native Widgets

- `Text` and `Image` lower to `GtkLabel`-based text widgets.
- `Button`, tap targets, and gesture targets lower to `GtkButton`.
- `Toggle` lowers to `GtkCheckButton`.
- `TextField` lowers to `GtkEntry` with native change callbacks into OmniUI bindings.
- `SecureField` preserves the actual binding value in the semantic tree, masks shared terminal/debug output, and lowers to a native hidden `GtkEntry` password field in Adwaita.
- `TextEditor` is tagged distinctly in the semantic tree and lowers to a multiline `GtkTextView` with native buffer callbacks into OmniUI bindings.
- `ProgressView` carries a renderer-neutral semantic progress role and lowers to `GtkProgressBar`, including in-place progress-bar fraction updates.
- `Slider` carries a renderer-neutral semantic slider role and lowers to a native GTK scale. Native scale value changes route back through the same OmniUICore increment/decrement actions used by the terminal fallback.
- `Picker`/semantic menu controls preserve option action IDs even while collapsed and lower to native GTK combo controls when choices are available.
- `Stepper` is preserved as a semantic role and lowers to a native `GtkSpinButton`. Native spin value changes route back through the same OmniUICore increment/decrement actions used by the terminal fallback.
- `DatePicker` is preserved as a semantic role and lowers to a native GTK calendar. Native calendar day/month/year changes route back through the same OmniUICore day increment/decrement actions used by the terminal fallback for adjacent date moves.
- `ScrollView` lowers to `GtkScrolledWindow`.
- `Divider` lowers to `GtkSeparator`.
- `List` lowers to native `GtkListBox` rows.
- `Form` lowers to an Adwaita-styled native GTK vertical box/card so arbitrary SwiftUI Form children remain visible and interactive.
- `VStack`, `HStack`, `ZStack`, `Group`, and toolbar stacks lower through native GTK boxes and semantic containers. Toolbar items preserve leading, trailing, principal, and bottom-bar placement by becoming semantic button groups around the base content. Scene commands lower into a native header-bar menu, scene settings lower into a separate native settings window, and sheets/alerts are extracted from the semantic root and presented as transient modal Adwaita windows instead of inline content.
- `NavigationSplitView` unwraps the renderer-neutral sidebar/detail semantic stack into a native horizontal `GtkPaned` split view.
- `LazyVStack` and `NavigationStack` are tagged in OmniUICore and lower to semantic Adwaita containers with stable semantic IDs.

## Runtime State

- `@State`, `@Binding`, `@Environment`, `@AppStorage`, `@FocusState`, `@Namespace`, and `@Bindable` stay owned by OmniUICore's runtime and are re-read on each semantic render.
- SwiftData wrappers (`@Query`, `modelContainer`, `modelContext`) stay owned by OmniUICore and SwiftData compatibility layers; the Adwaita backend renders the resulting semantic tree.
- Explicit `.id(...)` values are preserved in semantic node IDs so native renderers can use stable identity across rebuilds.
- `ForEach(..., id:)` elements use stable ID-derived runtime path components and semantic identity wrappers, so row-local state remains attached to the same data ID when list data reorders.
- `SemanticDiff` indexes previous and next semantic trees by stable ID and reports inserted, removed, updated, and reordered nodes.
- The Adwaita renderer applies simple leaf updates (`Text`, `Image`, `Button`, `Toggle`, `TextField`, `SecureField`, `TextEditor`, `Menu`, `ProgressView`, `Slider`, `Stepper`, `DatePicker`) in place through native GTK mutation when the diff contains only supported updates.
- Localized insertions, removals, child reorders, and unsupported node updates replace the smallest existing named semantic subtree when all changed IDs fall under one stable ancestor. Ambiguous structural changes still use full-tree GTK replacement.
- Full-tree GTK replacement preserves named `GtkScrolledWindow` vertical offsets across rebuilds and restores focused text/action controls through the semantic snapshot's focused action ID.
- Native action callbacks invoke OmniUI action IDs, compute the next semantic snapshot, and reconcile the GTK tree.
- Native Return and Escape key presses invoke OmniUI `.keyboardShortcut(.defaultAction)` and `.keyboardShortcut(.cancelAction)` handlers through the shared runtime shortcut registry.

## Drawing Islands

The renderer uses drawing islands where there is no appropriate native GTK control:

- `Canvas` lowers to a `GtkDrawingArea`.
- `Path`, shapes, and gradients lower to semantic drawing islands.
- Drawing islands carry tooltips/metadata so they remain inspectable in the native tree.

## Style And Modifier Approximations

- Liquid Glass and CRT effect modifiers are semantic metadata in the Adwaita backend. They preserve the real content subtree and drop decorative Canvas, Path, shape, and gradient overlays when those layers would otherwise become visible fake GTK widgets.
- Common layout modifiers such as frame, padding, opacity, and positive offset map to native GTK size requests, margins, and opacity on wrapper widgets. Style modifiers such as badge become Adwaita CSS classes, while background, shadow, glass, and CRT wrappers preserve primary content unless they are a real Adwaita dialog background. Clip, safe-area insets, toolbar backgrounds, sheets, and alerts are represented in OmniUICore and either become native containers, transient modal Adwaita windows, or documented no-op/metadata approximations where GTK has no direct equivalent.
- Accessibility labels and identifiers are preserved in the semantic tree. The Adwaita backend uses labels for native action metadata, GTK accessible labels, and GTK widget names where the modifier wraps a native child. macOS Computer Use still exposes the GTK child tree opaquely in this environment, so UI verification relies on screenshot deltas for child widgets.

## Known Gaps

- Incremental reconciliation covers stable leaf updates and localized structural subtree replacement. Structural changes that span multiple stable ancestors still fall back to full GTK tree replacement.
- Computer Use can click controls and verify visible widget state through screenshot deltas. GTK child controls still are not enumerated as separate macOS accessibility elements in this environment.
- The kitchen sink includes explicit `Type !` and `Backspace` smoke controls that focus and mutate the same `TextField` binding as the native `GtkEntry`; after focus is established, Computer Use `type_text` and `BackSpace` key input visibly update the same binding.
- This is a BrowserView-required subset implementation, not full SwiftUI parity.
