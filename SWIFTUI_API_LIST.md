# SwiftUI Compatibility Checklist (Target: iGopherBrowser)

This is the concrete task list for implementing a SwiftUI-compatible surface (and minimal runtime behavior) sufficient to compile and run the app in `references/iGopherBrowser` using this repo as the “SwiftUI” replacement.

Scope notes:
- The call sites are in `references/iGopherBrowser/iGopherBrowser/*.swift`.
- The current compatibility layer lives primarily in `Sources/OmniUICore/*` and is re-exported via `Sources/OmniUI/OmniUI.swift`.
- Many APIs can initially be “compile-only” stubs, but this list calls out places where behavior is required for iGopherBrowser UX (keyboard focus, text entry, scrolling, etc.).

Legend (for implementers):
- **Compile blocker**: cannot build iGopherBrowser until fixed.
- **Stubbed**: symbol exists but is a no-op / wrong shape.
- **Behavior**: compiles today but iGopherBrowser needs runtime behavior to be usable.

## 0. Module / Build Integration

- [x] Provide a `SwiftUI`-named shim module that re-exports OmniUI (so `import SwiftUI` works unchanged in iGopherBrowser).
- [x] Provide a `SwiftData`-named shim module (or move SwiftData compatibility into the SwiftUI shim) so `import SwiftData` resolves.
- [x] Add a small “compat build harness” target that tries to compile `references/iGopherBrowser/iGopherBrowser/*.swift` against the shim modules (CI gate). (Implemented as the `SwiftUICompatibilityHarness` target exercising iGopherBrowser-like call patterns.)

## 1. Core Protocol & Type Mismatches (Compile Blockers)

- [x] Replace the following “enum-as-namespace” stubs with SwiftUI-shaped **protocols** and concrete types:
- [x] `ButtonStyle` (currently conflicts with iGopherBrowser `struct … : ButtonStyle` in `references/iGopherBrowser/iGopherBrowser/LiquidGlass.swift` and `references/iGopherBrowser/iGopherBrowser/WhatsNew.swift`).
- [x] `ToggleStyle` (used in `references/iGopherBrowser/iGopherBrowser/SettingsView.swift`).
- [x] `PickerStyle` (used in `references/iGopherBrowser/iGopherBrowser/BookmarksView.swift` and `references/iGopherBrowser/iGopherBrowser/SettingsView.swift`).
- [x] `TextFieldStyle` (used across `references/iGopherBrowser/iGopherBrowser/SearchInputView.swift`, `references/iGopherBrowser/iGopherBrowser/SettingsView.swift`, `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] `ListStyle` (used in `references/iGopherBrowser/iGopherBrowser/ContentView.swift`, `references/iGopherBrowser/iGopherBrowser/FileView.swift`, `references/iGopherBrowser/iGopherBrowser/BookmarksView.swift`).

- [x] Implement `ViewModifier` protocol + `View.modifier(_:)` (used heavily in `references/iGopherBrowser/iGopherBrowser/CRTEffect.swift` and toolbar style helpers in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] Implement `LabelStyle` protocol + `.labelStyle(_:)` + built-in `.iconOnly` (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).

## 2. App / Scene / Commands Surface (Compile Blockers if building the app entry)

Used by `references/iGopherBrowser/iGopherBrowser/iGopherBrowserApp.swift`.

- [x] `protocol App` + `@main` integration for non-Apple platforms (even if implemented as a CLI wrapper).
- [x] `protocol Scene`, `struct WindowGroup`, and `SceneBuilder` equivalents.
- [x] `.commands { … }` surface.
- [x] `SidebarCommands` stub (macOS-only in iGopherBrowser; must exist behind `#if os(macOS)`).
- [x] `Settings` scene surface (macOS-only in iGopherBrowser).

## 3. Property Wrappers (Compile Blockers)

- [x] `@AppStorage` property wrapper (used across almost every view).
- [x] `@Namespace` property wrapper (declared in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] SwiftData `@Query` property wrapper (used in `references/iGopherBrowser/iGopherBrowser/BookmarksView.swift`).
- [x] SwiftData `@Model` macro/attribute (used in `references/iGopherBrowser/iGopherBrowser/Bookmark.swift` and `references/iGopherBrowser/iGopherBrowser/History.swift`).

## 4. Environment & Bindings (Compile Blockers + Behavior)

- [x] Match SwiftUI’s `@Environment(\.presentationMode)` type: iGopherBrowser expects `Binding<PresentationMode>` and calls `presentationMode.wrappedValue.dismiss()` (used in `references/iGopherBrowser/iGopherBrowser/SearchInputView.swift`).
- [x] Implement `View.environment(_:_:)` modifier to set `EnvironmentValues` entries (used in `references/iGopherBrowser/iGopherBrowser/CRTEffect.swift` via `.environment(\\.colorScheme, .dark)`).
- [x] Implement `EnvironmentValues` entries and keys required by iGopherBrowser:
- [x] `colorScheme` (already exists, but must be settable via `.preferredColorScheme` and `.environment`).
- [x] `dismiss` (already exists; verify correctness for sheets/navigation).
- [x] `presentationMode` (see Binding mismatch above).
- [x] `modelContext` (currently placeholder; needs real API surface for insert/delete).
- [x] Implement `openURL` environment action + `.onOpenURL` modifier wiring (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).

## 5. Navigation (Compile Blockers + Behavior)

- [x] `NavigationSplitView` (used in `references/iGopherBrowser/iGopherBrowser/ContentView.swift`).
- [x] `NavigationSplitViewVisibility` enum (used in `references/iGopherBrowser/iGopherBrowser/ContentView.swift`).
- [x] `NavigationStack`/`NavigationLink` parity gaps:
- [x] Push/pop behavior already exists; ensure `@Environment(\\.dismiss)` and `@Environment(\\.presentationMode)` behave like SwiftUI for pushed destinations.

## 6. Lists, Scrolling, and Identifiers (Compile Blockers + Behavior)

- [x] Hierarchical list initializer: `List(_:children:rowContent:)` (used in `references/iGopherBrowser/iGopherBrowser/SidebarView.swift`).
- [x] `ScrollViewReader` + `ScrollViewProxy.scrollTo(_:anchor:)` (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] `.id(_:)` modifier (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift` list rows).
- [x] `.onDelete(perform:)` support for `ForEach` inside `List` (used in `references/iGopherBrowser/iGopherBrowser/BookmarksView.swift`).
- [x] `.listRowSeparator(_:)` modifier + `Visibility.hidden`/`.hidden` equivalent (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] `.listRowBackground(_:)` modifier (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] `.scrollContentBackground(_:)` + `.automatic`/`.hidden` API (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift` and `references/iGopherBrowser/iGopherBrowser/SidebarView.swift`).

## 7. Text Input, Focus, and Submit (Behavior-Critical)

Keyboard + text entry must work in the notcurses renderer for iGopherBrowser to be usable.

- [x] Integrate `@FocusState` with the OmniUI focus system (currently “does not integrate”).
- [x] Implement `.focused(_:)` behavior for `FocusState<Bool>.Binding` and `Binding<Bool>` so iGopherBrowser can focus URL/find fields (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] Implement `.onSubmit { … }` so TextField submission triggers actions (used in `references/iGopherBrowser/iGopherBrowser/SearchInputView.swift` and `references/iGopherBrowser/iGopherBrowser/SettingsView.swift`).
- [x] Implement `SubmitLabel` (already stubbed type exists) + `.submitLabel(_:)` behavior if iGopherBrowser relies on it in future.
- [x] Add missing TextField configuration modifiers as compile-only stubs (iOS-only in iGopherBrowser, but should exist):
- [x] `.keyboardType(_:)` (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] `.textInputAutocapitalization(_:)` (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] `.textContentType(_:)` (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] `.disableAutocorrection(_:)` (used in `references/iGopherBrowser/iGopherBrowser/SettingsView.swift`).

## 8. Gestures & Hit Testing (Compile Blockers + Behavior)

- [x] `.onTapGesture { … }` (used in `references/iGopherBrowser/iGopherBrowser/SidebarView.swift`).
- [x] `.allowsHitTesting(_:)` (used in `references/iGopherBrowser/iGopherBrowser/ContentView.swift` and `references/iGopherBrowser/iGopherBrowser/CRTEffect.swift`).
- [ ] `contentShape(_:)` exists as stub; implement if needed for correct click hit-testing in lists/buttons (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).

## 9. Layout & Containers (Compile Blockers)

- [x] `GeometryReader` (used in `references/iGopherBrowser/iGopherBrowser/FileView.swift` and `references/iGopherBrowser/iGopherBrowser/CRTEffect.swift`).
- [x] `LazyVStack` (used in `references/iGopherBrowser/iGopherBrowser/FileView.swift` and `references/iGopherBrowser/iGopherBrowser/WhatsNew.swift`).
- [x] `Form` (used in `references/iGopherBrowser/iGopherBrowser/BookmarksView.swift` and `references/iGopherBrowser/iGopherBrowser/SettingsView.swift`).
- [x] `GroupBox` (used in `references/iGopherBrowser/iGopherBrowser/SettingsView.swift`).
- [x] `ContentUnavailableView` (used in `references/iGopherBrowser/iGopherBrowser/BookmarksView.swift`).
- [x] `LabeledContent` (used in `references/iGopherBrowser/iGopherBrowser/BookmarksView.swift`).
- [x] `Divider` (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).

## 10. Menus, Toolbars, and Buttons (Compile Blockers + Behavior)

- [x] `Menu` view (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] `.toolbar { … }` is currently stubbed; add required types so toolbar bodies compile:
- [x] `ToolbarItem` type (used in `references/iGopherBrowser/iGopherBrowser/BookmarksView.swift` and `references/iGopherBrowser/iGopherBrowser/WhatsNew.swift`).
- [x] `ToolbarItemPlacement` + cases used by iGopherBrowser (`.cancellationAction`, `.confirmationAction`, `.topBarLeading`, `.topBarTrailing`, `.topBar…`).
- [x] `EditButton` (used in `references/iGopherBrowser/iGopherBrowser/BookmarksView.swift`).
- [x] `.controlSize(_:)` (used in `references/iGopherBrowser/iGopherBrowser/WhatsNew.swift`).

## 11. Presentation (Sheets, Alerts, Insets) (Compile Blockers + Behavior)

- [x] `.sheet(isPresented:onDismiss:content:)` exists; ensure dismiss environment is SwiftUI-compatible for iGopherBrowser sheets.
- [x] `.alert(isPresented:content:)` currently expects a `View`; iGopherBrowser uses `Alert(...)` (used in `references/iGopherBrowser/iGopherBrowser/SettingsView.swift`).
- [x] Implement `Alert` type + `Alert.Button` + `Alert(title:message:dismissButton:)` initializer.
- [x] Implement `.safeAreaInset(edge:content:)` (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [x] Implement `.presentationDetents(_:)` and `.presentationDragIndicator(_:)` as compile-only stubs (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift` and `references/iGopherBrowser/iGopherBrowser/WhatsNew.swift`).

## 12. Drawing / Effects / Gradients (Compile Blockers)

Used mostly for CRT + “What’s New” UI.

- [ ] `Canvas` view + minimal `GraphicsContext` + `GraphicsContext.fill(_:with:)` + `.color(_)` shading (used in `references/iGopherBrowser/iGopherBrowser/CRTEffect.swift`).
- [ ] `Gradient` type + `Gradient(colors:)` initializer.
- [ ] `LinearGradient` view (used in `references/iGopherBrowser/iGopherBrowser/CRTEffect.swift` and `references/iGopherBrowser/iGopherBrowser/WhatsNew.swift`).
- [ ] `RadialGradient` view (used in `references/iGopherBrowser/iGopherBrowser/CRTEffect.swift`).
- [ ] `UnitPoint` + `.center`/`.topLeading`/`.bottomTrailing` (used by gradients in `references/iGopherBrowser/iGopherBrowser/CRTEffect.swift` and `references/iGopherBrowser/iGopherBrowser/WhatsNew.swift`).
- [ ] `RoundedCornerStyle` + `.continuous` (required for `RoundedRectangle(cornerRadius:style:)` usage in `references/iGopherBrowser/iGopherBrowser/WhatsNew.swift`).
- [ ] `Material.ultraThinMaterial` (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift` and `references/iGopherBrowser/iGopherBrowser/WhatsNew.swift`).
- [ ] `glassEffect` / `GlassEffectContainer` / related Liquid Glass APIs as compile-only stubs (used in `references/iGopherBrowser/iGopherBrowser/LiquidGlass.swift` and toolbars in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).

## 13. Color & ColorPicker (Compile Blockers)

- [ ] Implement `ColorPicker` view (used in `references/iGopherBrowser/iGopherBrowser/SettingsView.swift`).
- [ ] Implement `.labelsHidden()` modifier (used with ColorPicker in `references/iGopherBrowser/iGopherBrowser/SettingsView.swift`).
- [ ] Fix/extend `Color` construction patterns used by iGopherBrowser:
- [ ] `Color(nsColor:)` initializer (used in macOS-only code paths).
- [ ] `Color(uiColor:)` initializer (used in iOS-only code paths).
- [ ] Support `Color(.systemBackground)`/`Color(.systemGray6)` patterns used in iOS-only code paths (can be stubbed to named colors).
- [ ] Provide a strategy for `Color` persistence compatible with `@AppStorage` (iGopherBrowser stores `Color.rawValue` strings in `references/iGopherBrowser/iGopherBrowser/SettingsView.swift`).

## 14. Keyboard Shortcuts & Exit Command (Compile Blockers + Behavior)

- [ ] `keyboardShortcut` modifier exists but is stubbed; implement at least:
- [ ] `KeyboardShortcut(.cancelAction)` and `KeyboardShortcut(.defaultAction)` behavior for sheets/search bars where used.
- [ ] `onExitCommand` modifier (used in macOS-only `references/iGopherBrowser/iGopherBrowser/SearchInputView.swift`).
- [ ] `withAnimation` + `Animation` API stubs (`.spring()`, etc.) so `withAnimation { proxy.scrollTo(...) }` compiles (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).

## 15. Text API Gaps (Compile Blockers)

- [ ] `Text` initializer `init(_ image: Image)` (used as `Text(Image(systemName: ...))` in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift`).
- [ ] `.fontWeight(_:)` modifier (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift` and others; can be stubbed).
- [ ] `.foregroundColor(_:)` modifier overloads used by iGopherBrowser (distinct from `.foregroundStyle`).

## 16. Sharing / QuickLook (Compile-Only Stubs)

- [ ] `ShareLink` view (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift` and `references/iGopherBrowser/iGopherBrowser/FileView.swift`).
- [ ] `quickLookPreview(_:)` modifier stub (used in `references/iGopherBrowser/iGopherBrowser/FileView.swift`).

## 17. SwiftData Compatibility Layer (Compile Blockers + Behavior)

The goal is not full SwiftData; the goal is “enough to run iGopherBrowser”:

- [ ] `Schema` type and `Schema([Model.Type])` initializer (used in `references/iGopherBrowser/iGopherBrowser/iGopherBrowserApp.swift`).
- [ ] `ModelConfiguration(schema:isStoredInMemoryOnly:)` (used in `references/iGopherBrowser/iGopherBrowser/iGopherBrowserApp.swift`).
- [ ] `ModelContainer(for:configurations:)` and `ModelContainer(for:inMemory:)` (used in `references/iGopherBrowser/iGopherBrowser/iGopherBrowserApp.swift` and previews).
- [ ] `ModelContext` API: `insert(_:)`, `delete(_:)`, and `fetch`/query hooks used by `@Query` (used in `references/iGopherBrowser/iGopherBrowser/BrowserView.swift` and `references/iGopherBrowser/iGopherBrowser/BookmarksView.swift`).
- [ ] `@Query(sort:order:)` implementation supporting:
- [ ] key-path sort (e.g. `\\Bookmark.dateAdded`, `\\HistoryItem.visitedAt`).
- [ ] order `.reverse` (and the enum used by iGopherBrowser).
- [ ] live updates when `ModelContext` changes (or at least “eventual” updates for this app).

## 18. “Stub Today, Implement Later” Items Already Present in OmniUICore

These exist in `Sources/OmniUICore/Modifiers.swift` but are currently no-ops; iGopherBrowser would benefit from real behavior:

- [ ] `.task { … }` should run/cancel tasks tied to view lifecycle (used in `references/iGopherBrowser/iGopherBrowser/FileView.swift`).
- [ ] `.preferredColorScheme(_:)` should set `EnvironmentValues.colorScheme` (used in `references/iGopherBrowser/iGopherBrowser/ContentView.swift`).
- [ ] `.modelContainer(_:)` should seed the `modelContext` environment value (used in `references/iGopherBrowser/iGopherBrowser/iGopherBrowserApp.swift`).
- [ ] `.shadow`, `.cornerRadius`, `.clipShape`, `.overlay`, `.background` should eventually render meaningfully in notcurses/terminal renderers (CRT visuals depend on it).

## 19. File-by-File “Definition of Done” (Compile Targets)

These are practical “compile gates” for the shim:

- [ ] `references/iGopherBrowser/iGopherBrowser/ContentView.swift` compiles unchanged.
- [ ] `references/iGopherBrowser/iGopherBrowser/SidebarView.swift` compiles unchanged.
- [ ] `references/iGopherBrowser/iGopherBrowser/BrowserView.swift` compiles unchanged.
- [ ] `references/iGopherBrowser/iGopherBrowser/BookmarksView.swift` compiles unchanged.
- [ ] `references/iGopherBrowser/iGopherBrowser/SettingsView.swift` compiles unchanged.
- [ ] `references/iGopherBrowser/iGopherBrowser/SearchInputView.swift` compiles unchanged (excluding `#if os(macOS)` blocks on non-macOS).
- [ ] `references/iGopherBrowser/iGopherBrowser/FileView.swift` compiles unchanged (excluding platform-only blocks).
- [ ] `references/iGopherBrowser/iGopherBrowser/CRTEffect.swift` compiles unchanged.
- [ ] `references/iGopherBrowser/iGopherBrowser/LiquidGlass.swift` compiles unchanged.
- [ ] `references/iGopherBrowser/iGopherBrowser/WhatsNew.swift` compiles unchanged.
- [ ] `references/iGopherBrowser/iGopherBrowser/iGopherBrowserApp.swift` compiles unchanged (if we want full app entry compatibility).
