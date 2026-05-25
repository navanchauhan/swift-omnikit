import Foundation
#if os(macOS)
import AppKit
#endif
#if canImport(Observation)
import Observation
#endif

#if os(macOS)
private final class _OmniAppKitAppearanceState: @unchecked Sendable {
    static let shared = _OmniAppKitAppearanceState()

    private let lock = NSLock()
    private var preferredColorScheme: ColorScheme?
    private var applicationAppearanceWasSet = false
    private var lastDeliveredColorScheme: ColorScheme?
    private var handler: (@Sendable (ColorScheme?) -> Void)?
    private var isObservingApplicationAppearance = false
    private var appearanceObservation: NSKeyValueObservation?
    private var effectiveAppearanceObservation: NSKeyValueObservation?

    func currentColorScheme() -> ColorScheme? {
        lock.lock()
        let preferred = preferredColorScheme
        let useApplicationAppearance = applicationAppearanceWasSet
        lock.unlock()
        if let preferred { return preferred }
        if let explicit = Self.currentExplicitApplicationColorScheme() {
            return explicit
        }
        if useApplicationAppearance {
            return Self.currentApplicationColorScheme() ?? Self.environmentColorSchemeOverride()
        }
        return Self.environmentColorSchemeOverride() ?? Self.currentApplicationColorScheme()
    }

    func setPreferredColorScheme(_ scheme: ColorScheme?) {
        let callback: (@Sendable (ColorScheme?) -> Void)?
        let previous = currentColorScheme()
        lock.lock()
        preferredColorScheme = scheme
        callback = handler
        lock.unlock()
        let effective = currentColorScheme()
        lock.lock()
        lastDeliveredColorScheme = effective
        lock.unlock()
        if effective != previous {
            callback?(effective)
        }
    }

    func setChangeHandler(_ next: (@Sendable (ColorScheme?) -> Void)?) {
        installApplicationAppearanceObserversIfNeeded()
        let scheme = currentColorScheme()
        lock.lock()
        handler = next
        lastDeliveredColorScheme = scheme
        lock.unlock()
        next?(scheme)
    }

    static func currentApplicationColorScheme() -> ColorScheme? {
        if Thread.isMainThread {
            return currentApplicationColorSchemeOnMain()
        }
        var scheme: ColorScheme?
        DispatchQueue.main.sync {
            scheme = currentApplicationColorSchemeOnMain()
        }
        return scheme
    }

    static func currentExplicitApplicationColorScheme() -> ColorScheme? {
        if Thread.isMainThread {
            return currentExplicitApplicationColorSchemeOnMain()
        }
        var scheme: ColorScheme?
        DispatchQueue.main.sync {
            scheme = currentExplicitApplicationColorSchemeOnMain()
        }
        return scheme
    }

    private static func currentApplicationColorSchemeOnMain() -> ColorScheme? {
        MainActor.assumeIsolated {
            if let explicit = colorScheme(for: NSApplication.shared.appearance) {
                return explicit
            }
            return colorScheme(for: NSApplication.shared.effectiveAppearance)
        }
    }

    private static func currentExplicitApplicationColorSchemeOnMain() -> ColorScheme? {
        MainActor.assumeIsolated {
            colorScheme(for: NSApplication.shared.appearance)
        }
    }

    private func installApplicationAppearanceObserversIfNeeded() {
        lock.lock()
        guard !isObservingApplicationAppearance else {
            lock.unlock()
            return
        }
        isObservingApplicationAppearance = true
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let app = NSApplication.shared
                let appearance = app.observe(\.appearance, options: [.new]) { [weak self] _, _ in
                    self?.applicationAppearanceChanged(explicitApplicationAppearance: true)
                }
                let effectiveAppearance = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                    self?.applicationAppearanceChanged(explicitApplicationAppearance: false)
                }
                self.lock.lock()
                self.appearanceObservation = appearance
                self.effectiveAppearanceObservation = effectiveAppearance
                self.lock.unlock()
            }
        }
    }

    private func applicationAppearanceChanged(explicitApplicationAppearance: Bool) {
        if explicitApplicationAppearance {
            lock.lock()
            applicationAppearanceWasSet = true
            lock.unlock()
        }
        let effective = currentColorScheme()
        let callback: (@Sendable (ColorScheme?) -> Void)?
        let shouldNotify: Bool
        lock.lock()
        callback = handler
        shouldNotify = effective != lastDeliveredColorScheme
        if shouldNotify {
            lastDeliveredColorScheme = effective
        }
        lock.unlock()
        if shouldNotify {
            callback?(effective)
        }
    }

    private static func colorScheme(for appearance: NSAppearance?) -> ColorScheme? {
        guard let match = appearance?.bestMatch(from: [.aqua, .darkAqua]) else { return nil }
        if match == .darkAqua { return .dark }
        if match == .aqua { return .light }
        return nil
    }

    private static func environmentColorSchemeOverride() -> ColorScheme? {
        let environment = ProcessInfo.processInfo.environment
        for key in ["OMNIUI_ADWAITA_COLOR_SCHEME", "OMNIUI_COLOR_SCHEME"] {
            guard let raw = environment[key]?.lowercased(), !raw.isEmpty else { continue }
            if raw == "dark" || raw == "force-dark" { return .dark }
            if raw == "light" || raw == "force-light" { return .light }
            if raw == "system" || raw == "default" { return nil }
        }
        if let gtkTheme = environment["GTK_THEME"]?.lowercased(), gtkTheme.contains(":dark") {
            return .dark
        }
        return nil
    }
}

public func _omniSetAppearanceChangeHandler(_ handler: (@Sendable (ColorScheme?) -> Void)?) {
    _OmniAppKitAppearanceState.shared.setChangeHandler(handler)
}

public func _omniCurrentAppearanceColorScheme() -> ColorScheme? {
    _OmniAppKitAppearanceState.shared.currentColorScheme()
}

public func _omniCurrentApplicationAppearanceColorScheme() -> ColorScheme? {
    _OmniAppKitAppearanceState.currentApplicationColorScheme()
}

public func _omniEffectiveAppearanceColorScheme() -> ColorScheme {
    _omniCurrentAppearanceColorScheme() ?? .light
}

public func _omniSetPreferredColorScheme(_ scheme: ColorScheme?) {
    _OmniAppKitAppearanceState.shared.setPreferredColorScheme(scheme)
}
#endif

// Safety: OmniUI runtime state is confined to a single render/event loop owner.
public final class _UIRuntime: @unchecked Sendable {
    private static let _overlayPathSentinel = Int.min
    private static let _maxSynchronousRenderPasses = 4

    /// Build-time ambient runtime. Set by `_BuildContext.withRuntime`.
    @TaskLocal public static var _current: _UIRuntime?

    /// A traversal path to disambiguate state keys for repeated view instances.
    @TaskLocal static var _currentPath: [Int]?

    /// Build-time ambient environment values.
    @TaskLocal static var _currentEnvironment: EnvironmentValues?

    /// Build-time ambient terminal/grid size for the current render pass.
    @TaskLocal static var _currentRenderSize: _Size?

    /// The current `ScrollViewReader` scope path while building descendants.
    @TaskLocal static var _currentScrollReaderScopePath: [Int]?

    @TaskLocal static var _currentScrollViewport: _LazyViewport?

    @TaskLocal static var _currentLazyRealization: _LazyRealization?

    /// Whether hit testing is enabled for the current subtree (SwiftUI `.allowsHitTesting`).
    @TaskLocal static var _hitTestingEnabled: Bool = true

    /// Used by modifiers like `.focused`/`.onSubmit` to discover the first focusable control
    /// in a subtree, regardless of intervening modifier wrappers.
    @TaskLocal static var _currentFocusCaptureID: Int?

    /// Used by `Menu` to discover nested `Button` actions without rendering them as normal controls.
    @TaskLocal static var _currentMenuCaptureID: Int?

    /// Used by `.labelsHidden()` to hide built-in labels for certain controls.
    @TaskLocal static var _labelsHidden: Bool = false

    private var nextActionID: Int = 1
    private var actions: [_ActionID: (path: [Int], env: EnvironmentValues, action: () -> Void)] = [:]
    private var dateSetters: [_ActionID: (path: [Int], env: EnvironmentValues, setter: (TimeInterval) -> Void)] = [:]
    private var doubleSetters: [_ActionID: (path: [Int], env: EnvironmentValues, setter: (Double) -> Void)] = [:]

    private var nextFocusCaptureID: Int = 1
    private var focusCaptureResults: [Int: [Int]] = [:]

    struct _MenuCaptureItem {
        var label: String
        var role: ButtonRole?
        var actionScopePath: [Int]
        var env: EnvironmentValues
        var action: () -> Void
    }
    private var nextMenuCaptureID: Int = 1
    private var menuCaptureResults: [Int: [_MenuCaptureItem]] = [:]

    private var state: [String: Any] = [:]
    private var modifierState: [String: Any] = [:]

    private var focusedPath: [Int]? = nil
    private var textEditors: [[Int]: _TextEditor] = [:]
    private var textEditorCursors: [[Int]: Int] = [:]
    private var focusOrder: [[Int]] = []
    private var focusPriorities: [[Int]: Int] = [:]
    private var focusActivation: [[Int]: _ActionID] = [:]
    private var focusBoolBindings: [[Int]: (Bool) -> Void] = [:]
    private var submitHandlers: [[Int]: (path: [Int], env: EnvironmentValues, action: () -> Void)] = [:]
    private var keyPressHandlers: [[Int]: [KeyEquivalent: (path: [Int], env: EnvironmentValues, action: () -> Bool)]] = [:]
    private var nextHoverID: Int = 1
    private var hoverHandlers: [_HoverID: (path: [Int], env: EnvironmentValues, action: (Bool) -> Void)] = [:]
    private var activeHoverID: _HoverID? = nil
    private var exitCommand: (path: [Int], env: EnvironmentValues, action: () -> Void)? = nil
    private var keyboardShortcuts: [KeyboardShortcut: [(path: [Int], id: _ActionID)]] = [:]

    // Preference system
    private var _preferences: [ObjectIdentifier: Any] = [:]
    private var _preferenceCallbacks: [(keyID: ObjectIdentifier, callback: (Any) -> Void)] = []
    private var _previousPreferences: [ObjectIdentifier: Any] = [:]

    private struct _TaskEntry {
        var env: EnvironmentValues
        var path: [Int]
        var action: () async -> Void
        var task: Task<Void, Never>?
    }
    private let taskRegistryLock = NSLock()
    private var tasks: [String: _TaskEntry] = [:]
    private var tasksSeenThisFrame: Set<String> = []
    private var receiveSubscriptions: [String: AnyObject] = [:]
    private var nextLaunchedAsyncActionID: Int = 1
    private var launchedAsyncActions: [Int: _TaskEntry] = [:]

    private var expandedPickerPath: [Int]? = nil
    private var scrollOffsets: [String: Int] = [:]
    private var scrollTargets: [_ScrollTarget] = []
    private var pendingScrollRequests: [_PendingScrollRequest] = []
    private var globalEditMode: EditMode = .inactive
    private var lastHitRegions: [_HitRegion] = []
    private var lastScrollRegions: [_ScrollRegion] = []
    private var activeDragItemProviders: [NSItemProvider] = []
    private var activeDragLocation: CGPoint = .zero
    private var dropFallbackActionIDs: Set<_ActionID> = []
    private var activationPointsByActionID: [_ActionID: CGPoint] = [:]
    private var currentInvokedActionID: _ActionID?
    private var nextDragGestureID: Int = 1
    private var dragGestures: [_DragGestureID: (path: [Int], env: EnvironmentValues, gesture: DragGesture)] = [:]
    private var dragGestureByActionID: [_ActionID: _DragGestureID] = [:]
    private var activeNativeDragGesture: (id: _DragGestureID, start: CGPoint, hasMoved: Bool)?

    private struct _NavEntry {
        var view: AnyView
        var ownerKey: String?
        var onPop: (() -> Void)?
    }
    private typealias _NavResolver = @MainActor (AnyHashable) -> AnyView
    private var navStacks: [String: [_NavEntry]] = [:]
    private var navStackRoots: Set<[Int]> = []
    private var navResolvers: [String: [ObjectIdentifier: _NavResolver]] = [:]

    private struct _PendingScrollRequest {
        var scopePath: [Int]
        var id: AnyHashable
        var anchor: Alignment?
    }

    private struct _OverlayEntry {
        var view: AnyView
        var dismiss: () -> Void
    }
    private var overlays: [_OverlayEntry] = []

    private var onAppearPathKeys: Set<String> = []
    private var onAppearSeenThisFrame: Set<String> = []
    private var onDisappearHandlers: [String: (path: [Int], env: EnvironmentValues, action: () -> Void)] = [:]
    private var onDisappearSeenThisFrame: Set<String> = []

    private struct _ViewCacheEntry {
        var node: _VNode
        var typeID: ObjectIdentifier
        var viewSignature: Int
        var isPure: Bool
        var subtreePathKeys: Set<String>
    }

    private struct _ActiveBuildRecord {
        var path: [Int]
        var pathKey: String
        var subtreePathKeys: Set<String>
        var sideEffectStart: Int
    }

    private var _viewCache: [String: _ViewCacheEntry] = [:]
    private var _stateReaders: [String: Set<String>] = [:]
    private var _viewStateDependencies: [String: Set<String>] = [:]

    private var _pendingDirtyEverything: Bool = true
    private var _pendingDirtyPaths: [[Int]] = []
    private var _pendingDirtyPathKeys: Set<String> = []

    private var _frameDirtyEverything: Bool = true
    private var _frameDirtyPaths: [[Int]] = []
    private var _frameAlivePathKeys: Set<String> = []
    private var _activeBuildRecords: [_ActiveBuildRecord] = []
    private var _buildSideEffectCount: Int = 0
    private var _isBuildingFrame: Bool = false

    private var _lastRenderedSize: _Size? = nil
    private var _hasRenderedAtLeastOnce: Bool = false

    // ── Animation tick scheduler ──────────────────────────────────────
    private struct _ActiveAnimation {
        let curve: AnimationCurve
        /// Total ticks for this animation (derived from duration at ~60fps ≈ 16ms/tick).
        let totalTicks: Int
        /// Current tick counter (0 ..< totalTicks).
        var currentTick: Int = 0
    }
    private var _activeAnimations: [_ActiveAnimation] = []

    /// Register a new animation that should drive re-renders over the given duration.
    public func _registerAnimation(curve: AnimationCurve, duration: Double) {
        let tickRate: Double = 0.016 // ~16ms per tick
        let ticks = max(1, Int((duration / tickRate).rounded()))
        _activeAnimations.append(_ActiveAnimation(curve: curve, totalTicks: ticks))
        _markDirty()
    }

    /// Advance all active animations by one tick. Returns true if any are still running.
    public func _tickAnimations() -> Bool {
        guard !_activeAnimations.isEmpty else { return false }
        var i = 0
        while i < _activeAnimations.count {
            _activeAnimations[i].currentTick += 1
            if _activeAnimations[i].currentTick >= _activeAnimations[i].totalTicks {
                _activeAnimations.remove(at: i)
            } else {
                i += 1
            }
        }
        if !_activeAnimations.isEmpty {
            _markDirty()
        }
        return !_activeAnimations.isEmpty
    }

    /// The current animation progress fraction t ∈ [0,1] for the most recently registered animation,
    /// or 1.0 if no animation is active.
    public var _animationProgress: Double {
        guard let anim = _activeAnimations.last else { return 1.0 }
        let linearT = Double(anim.currentTick) / Double(max(1, anim.totalTicks))
        return anim.curve.evaluate(linearT)
    }

    /// Whether any animations are currently in-flight.
    public var _hasActiveAnimations: Bool {
        !_activeAnimations.isEmpty
    }

    // Base environment at the root render call.
    var _baseEnvironment: EnvironmentValues = EnvironmentValues()
    public private(set) var lastPreferredColorScheme: ColorScheme?
    private var framePreferredColorScheme: ColorScheme?
    private var defaultShareURLAction: OpenURLAction = OpenURLAction()

    public init() {
        // Provide a per-runtime model context so `@Environment(\\.modelContext)` and `@Query` have
        // a stable default even if the app doesn't call `.modelContainer(...)`.
        _baseEnvironment.modelContext = ModelContext()
        _baseEnvironment.editMode = Binding(
            get: { [weak self] in self?.globalEditMode ?? .inactive },
            set: { [weak self] in self?._setGlobalEditMode($0) }
        )
    }

    // ScenePhase support — called by renderer when terminal focus changes
    public func _setScenePhase(_ phase: ScenePhase) {
        let old = _baseEnvironment.scenePhase
        guard old != phase else { return }
        _baseEnvironment.scenePhase = phase
        _markDirty()
    }

    func _recordPreferredColorScheme(_ scheme: ColorScheme) {
        framePreferredColorScheme = scheme
    }

    /// Deliver a URL to the top-level `onOpenURL` handler registered in the environment.
    public func deliverURL(_ url: URL) {
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        let result = env.openURL(url)
        _ = result
        _markDirty()
    }

    public func setDefaultOpenURLAction(_ action: OpenURLAction) {
        _baseEnvironment.openURL = action
        _markDirty()
    }

    public func setDefaultOpenSettingsAction(_ action: OpenSettingsAction) {
        _baseEnvironment.openSettings = action
        _markDirty()
    }

    public func setDefaultShareURLAction(_ action: OpenURLAction) {
        defaultShareURLAction = action
    }

    func _shareURL(_ url: URL) {
        _ = defaultShareURLAction(url)
    }

    func _beginFocusCapture() -> Int {
        let id = nextFocusCaptureID
        nextFocusCaptureID += 1
        return id
    }

    func _endFocusCapture(_ id: Int) -> [Int]? {
        focusCaptureResults.removeValue(forKey: id)
    }

    func _beginMenuCapture() -> Int {
        let id = nextMenuCaptureID
        nextMenuCaptureID += 1
        return id
    }

    func _registerMenuCaptureItem(_ item: _MenuCaptureItem, captureID: Int) {
        menuCaptureResults[captureID, default: []].append(item)
    }

    func _invokeCapturedMenuItem(_ item: _MenuCaptureItem) {
        _UIRuntime.$_currentEnvironment.withValue(item.env) {
            _BuildContext.withRuntime(self, path: item.actionScopePath) {
                item.action()
            }
        }
        _markDirty(path: item.actionScopePath)
    }

    func _endMenuCapture(_ id: Int) -> [_MenuCaptureItem] {
        menuCaptureResults.removeValue(forKey: id) ?? []
    }

    private func _pathKey(prefix: String, path: [Int]) -> String {
        let p = path.map(String.init).joined(separator: ".")
        return "\(prefix):\(p)"
    }

    func _viewPathKey(path: [Int]) -> String {
        _pathKey(prefix: "view", path: path)
    }

    private func _pathFromKey(_ key: String, prefix: String) -> [Int]? {
        let marker = "\(prefix):"
        guard key.hasPrefix(marker) else { return nil }
        let raw = String(key.dropFirst(marker.count))
        if raw.isEmpty { return [] }
        let comps = raw.split(separator: ".")
        var out: [Int] = []
        out.reserveCapacity(comps.count)
        for c in comps {
            guard let v = Int(c) else { return nil }
            out.append(v)
        }
        return out
    }

    fileprivate func _viewSignature<V>(for view: V) -> Int {
        var hasher = Hasher()
        hasher.combine(ObjectIdentifier(V.self))
        hasher.combine(String(reflecting: view))
        return hasher.finalize()
    }

    private func _markDirty(path: [Int]? = nil) {
        if let path {
            let key = _viewPathKey(path: path)
            if _pendingDirtyPathKeys.insert(key).inserted {
                _pendingDirtyPaths.append(path)
            }
            return
        }
        _pendingDirtyEverything = true
    }

    /// Called by ObservableObject/StateObject/EnvironmentObject bindings to mark
    /// the owning view path dirty when a property is mutated via a binding.
    public func _markDirtyFromBinding(path: [Int]) {
        _markDirty(path: path)
    }

    private func _markDirty(paths: [[Int]]) {
        for p in paths {
            _markDirty(path: p)
        }
    }

    private func _isPathDirtyThisFrame(_ path: [Int]) -> Bool {
        if _frameDirtyEverything { return true }
        guard !_frameDirtyPaths.isEmpty else { return false }
        for dirty in _frameDirtyPaths {
            if _isPrefix(path, of: dirty) || _isPrefix(dirty, of: path) {
                return true
            }
        }
        return false
    }

    private func _noteBuildSideEffect() {
        guard _isBuildingFrame else { return }
        _buildSideEffectCount += 1
    }

    private func _removeStateDependencies(forViewPathKey pathKey: String) {
        guard let deps = _viewStateDependencies.removeValue(forKey: pathKey) else { return }
        for stateKey in deps {
            guard var readers = _stateReaders[stateKey] else { continue }
            readers.remove(pathKey)
            if readers.isEmpty {
                _stateReaders.removeValue(forKey: stateKey)
            } else {
                _stateReaders[stateKey] = readers
            }
        }
    }

    private func _recordStateRead(stateKey: String, viewPath: [Int]) {
        let pathKey = _viewPathKey(path: viewPath)
        _stateReaders[stateKey, default: []].insert(pathKey)
        _viewStateDependencies[pathKey, default: []].insert(stateKey)
    }

    private func _markDirtyForState(stateKey: String, ownerPath: [Int]) {
        guard let readers = _stateReaders[stateKey], !readers.isEmpty else {
            _markDirty(path: ownerPath)
            return
        }
        var resolvedPaths: [[Int]] = []
        resolvedPaths.reserveCapacity(readers.count)
        for key in readers {
            guard let path = _pathFromKey(key, prefix: "view") else { continue }
            resolvedPaths.append(path)
        }
        if resolvedPaths.isEmpty {
            _markDirty(path: ownerPath)
            return
        }
        _markDirty(paths: resolvedPaths)
    }

    private func _beginFrameBuild(size: _Size) {
        #if os(Linux) || os(macOS)
        _baseEnvironment.colorScheme = _omniEffectiveAppearanceColorScheme()
        #endif
        let runtimeID = "runtime:\(ObjectIdentifier(self)):"
        _OmniRepresentableFallback.beginFrame(runtimeID: runtimeID)
        framePreferredColorScheme = nil
        let sizeChanged = (_lastRenderedSize != size)
        if sizeChanged {
            _viewCache.removeAll(keepingCapacity: true)
            _stateReaders.removeAll(keepingCapacity: true)
            _viewStateDependencies.removeAll(keepingCapacity: true)
        }

        _frameDirtyEverything = _pendingDirtyEverything || sizeChanged || !_hasRenderedAtLeastOnce
        _frameDirtyPaths = _pendingDirtyPaths

        _pendingDirtyEverything = false
        _pendingDirtyPaths.removeAll(keepingCapacity: true)
        _pendingDirtyPathKeys.removeAll(keepingCapacity: true)

        _frameAlivePathKeys.removeAll(keepingCapacity: true)
        _activeBuildRecords.removeAll(keepingCapacity: true)
        _buildSideEffectCount = 0
        _isBuildingFrame = true
    }

    private func _finishFrameBuild(size: _Size) {
        _isBuildingFrame = false

        if _frameAlivePathKeys.isEmpty {
            if !_viewCache.isEmpty {
                for (_, entry) in _viewCache {
                    for dead in entry.subtreePathKeys {
                        _removeStateDependencies(forViewPathKey: dead)
                    }
                }
                _viewCache.removeAll(keepingCapacity: true)
            }
        } else if !_viewCache.isEmpty {
            var removeKeys: [String] = []
            removeKeys.reserveCapacity(_viewCache.count)
            for (key, entry) in _viewCache where !_frameAlivePathKeys.contains(key) {
                removeKeys.append(key)
                for dead in entry.subtreePathKeys {
                    _removeStateDependencies(forViewPathKey: dead)
                }
            }
            for key in removeKeys {
                _viewCache.removeValue(forKey: key)
            }
        }

        _frameDirtyEverything = false
        _frameDirtyPaths.removeAll(keepingCapacity: true)
        lastPreferredColorScheme = framePreferredColorScheme
        let runtimeID = "runtime:\(ObjectIdentifier(self)):"
        _OmniRepresentableFallback.endFrame(runtimeID: runtimeID)
        let alivePathKeys = _frameAlivePathKeys
        if !onAppearPathKeys.isEmpty {
            onAppearPathKeys = Set(
                onAppearPathKeys.filter { key in
                    alivePathKeys.contains(key) && onAppearSeenThisFrame.contains(key)
                }
            )
        }
        if !onDisappearHandlers.isEmpty {
            var removed: [String] = []
            removed.reserveCapacity(onDisappearHandlers.count)
            for key in onDisappearHandlers.keys where !alivePathKeys.contains(key) {
                removed.append(key)
            }
            for key in removed {
                guard let entry = onDisappearHandlers.removeValue(forKey: key) else { continue }
                _UIRuntime.$_currentEnvironment.withValue(entry.env) {
                    _BuildContext.withRuntime(self, path: entry.path) {
                        entry.action()
                    }
                }
            }

            // If the view at a given path still exists but no longer has `.onDisappear`,
            // remove the stale handler so we don't fire it in a later frame.
            var stale: [String] = []
            stale.reserveCapacity(onDisappearHandlers.count)
            for key in onDisappearHandlers.keys where alivePathKeys.contains(key) && !onDisappearSeenThisFrame.contains(key) {
                stale.append(key)
            }
            for key in stale {
                onDisappearHandlers.removeValue(forKey: key)
            }
        }
        _frameAlivePathKeys.removeAll(keepingCapacity: true)
        _activeBuildRecords.removeAll(keepingCapacity: true)
        onAppearSeenThisFrame.removeAll(keepingCapacity: true)
        onDisappearSeenThisFrame.removeAll(keepingCapacity: true)

        _lastRenderedSize = size
        _hasRenderedAtLeastOnce = true
    }

    fileprivate func _beginPathBuild(path: [Int], pathKey: String) {
        _frameAlivePathKeys.insert(pathKey)
        _removeStateDependencies(forViewPathKey: pathKey)
        let record = _ActiveBuildRecord(
            path: path,
            pathKey: pathKey,
            subtreePathKeys: [pathKey],
            sideEffectStart: _buildSideEffectCount
        )
        _activeBuildRecords.append(record)
    }

    fileprivate func _endPathBuild(typeID: ObjectIdentifier, viewSignature: Int, node: _VNode) {
        guard let record = _activeBuildRecords.popLast() else { return }
        let isPure = (_buildSideEffectCount == record.sideEffectStart)
        _viewCache[record.pathKey] = _ViewCacheEntry(
            node: node,
            typeID: typeID,
            viewSignature: viewSignature,
            isPure: isPure,
            subtreePathKeys: record.subtreePathKeys
        )
        if !_activeBuildRecords.isEmpty {
            _activeBuildRecords[_activeBuildRecords.count - 1].subtreePathKeys.formUnion(record.subtreePathKeys)
        }
    }

    fileprivate func _canReuseNode(path: [Int], pathKey: String, typeID: ObjectIdentifier, viewSignature: Int) -> Bool {
        guard !_isPathDirtyThisFrame(path) else { return false }
        guard let entry = _viewCache[pathKey] else { return false }
        guard entry.typeID == typeID else { return false }
        guard entry.viewSignature == viewSignature else { return false }
        return entry.isPure
    }

    fileprivate func _reuseNode(pathKey: String) -> _VNode? {
        guard let entry = _viewCache[pathKey] else { return nil }
        _frameAlivePathKeys.formUnion(entry.subtreePathKeys)
        if !_activeBuildRecords.isEmpty {
            _activeBuildRecords[_activeBuildRecords.count - 1].subtreePathKeys.formUnion(entry.subtreePathKeys)
        }
        return entry.node
    }

    private func _prepareRuntimeRegistriesForFrame() {
        nextActionID = 1
        actions.removeAll(keepingCapacity: true)
        dateSetters.removeAll(keepingCapacity: true)
        doubleSetters.removeAll(keepingCapacity: true)
        textEditors.removeAll(keepingCapacity: true)
        focusOrder.removeAll(keepingCapacity: true)
        focusPriorities.removeAll(keepingCapacity: true)
        focusActivation.removeAll(keepingCapacity: true)
        focusBoolBindings.removeAll(keepingCapacity: true)
        submitHandlers.removeAll(keepingCapacity: true)
        nextHoverID = 1
        hoverHandlers.removeAll(keepingCapacity: true)
        exitCommand = nil
        keyboardShortcuts.removeAll(keepingCapacity: true)
        dropFallbackActionIDs.removeAll(keepingCapacity: true)
        navStackRoots.removeAll(keepingCapacity: true)
        navResolvers.removeAll(keepingCapacity: true)
        overlays.removeAll(keepingCapacity: true)
        _withTaskRegistryLock {
            tasksSeenThisFrame.removeAll(keepingCapacity: true)
        }
        onAppearSeenThisFrame.removeAll(keepingCapacity: true)
        onDisappearSeenThisFrame.removeAll(keepingCapacity: true)
    }

    @MainActor
    private func _buildRootNode<V: View>(_ root: V, size: _Size) -> _VNode {
        let runtime = self
        let ctx = _BuildContext(runtime: runtime, path: [], nextChildIndex: 0)
        let rootPath: [Int] = []
        let rootPathKey = _viewPathKey(path: rootPath)
        let rootTypeID = ObjectIdentifier(V.self)
        let rootSignature = _viewSignature(for: root)

        _beginPathBuild(path: rootPath, pathKey: rootPathKey)
        let build = {
            _UIRuntime.$_currentRenderSize.withValue(size) {
                _BuildContext.withRuntime(runtime, path: rootPath) {
                    var local = ctx
                    return _makeNode(root, &local)
                }
            }
        }
        let node: _VNode
        #if canImport(Observation)
        node = withObservationTracking {
            build()
        } onChange: { [weak runtime] in
            runtime?._markDirty(path: rootPath)
        }
        #else
        node = build()
        #endif
        _endPathBuild(typeID: rootTypeID, viewSignature: rootSignature, node: node)
        return node
    }

    @MainActor
    private func _applyOverlays(to node: _VNode) -> _VNode {
        guard !overlays.isEmpty else { return node }
        var merged = node
        var local = _BuildContext(runtime: self, path: [Int.min], nextChildIndex: 0)
        for entry in overlays {
            let current = _UIRuntime._currentEnvironment ?? _baseEnvironment
            var next = current
            next.dismiss = DismissAction(entry.dismiss)
            let mode = PresentationMode(dismiss: entry.dismiss)
            next.presentationMode = Binding(get: { mode }, set: { _ in })
            let overlayNode = _UIRuntime.$_currentEnvironment.withValue(next) {
                local.buildChild(entry.view)
            }
            merged = .zstack(alignment: .center, children: [merged, .elevated(zOffset: 1000, child: overlayNode)])
        }
        return merged
    }

    private func _finalizePostBuildState() {
        // Sort focus order by priority (stable, with registration-order tiebreaker)
        if !focusPriorities.isEmpty {
            let indexed = focusOrder.enumerated().map { ($0.offset, $0.element) }
            let sorted = indexed.sorted { a, b in
                let pa = focusPriorities[a.1] ?? 0
                let pb = focusPriorities[b.1] ?? 0
                return pa != pb ? pa > pb : a.0 < b.0
            }
            focusOrder = sorted.map(\.1)
        }

        // If a picker/menu was expanded in a view that no longer exists, clear the stale state.
        if let expanded = expandedPickerPath {
            let stillExists = focusOrder.contains(where: { _isPrefix(expanded, of: $0) })
            if !stillExists {
                expandedPickerPath = nil
            }
        }

        let overlayFocusOrder = _overlayFocusablePaths()
        if !overlayFocusOrder.isEmpty {
            if focusedPath == nil || !overlayFocusOrder.contains(where: { $0 == focusedPath }) {
                _setFocus(path: overlayFocusOrder[0])
            }
        }

        // If nothing is focused yet, default focus to the first focusable control.
        if focusedPath == nil, let first = focusOrder.first {
            _setFocus(path: first)
        }

        _reconcileTasksAfterFrame()
    }

    public func needsRender(size: _Size) -> Bool {
        renderInvalidationReason(size: size) != nil
    }

    public func renderInvalidationReason(size: _Size) -> String? {
        if !_hasRenderedAtLeastOnce { return "initial" }
        if _lastRenderedSize != size { return "size" }
        if _pendingDirtyEverything { return "dirty-all" }
        if !_activeAnimations.isEmpty { return "animations:\(_activeAnimations.count)" }
        if !_pendingDirtyPaths.isEmpty {
            let preview = _pendingDirtyPaths.prefix(6).map { path in
                _viewPathKey(path: path)
            }.joined(separator: ",")
            return "dirty-paths:\(_pendingDirtyPaths.count):\(preview)"
        }
        return nil
    }

    private var _hasPendingSynchronousInvalidation: Bool {
        _pendingDirtyEverything || !_pendingDirtyPaths.isEmpty
    }

    private func _setGlobalEditMode(_ mode: EditMode) {
        if globalEditMode == mode { return }
        globalEditMode = mode
        _markDirty()
    }

    func _getScrollOffset(path: [Int]) -> Int {
        scrollOffsets[_pathKey(prefix: "scroll", path: path)] ?? 0
    }

    func _getScrollOffsetX(path: [Int]) -> Int {
        scrollOffsets[_pathKey(prefix: "scrollX", path: path)] ?? 0
    }

    func _setScrollOffsetX(path: [Int], offset: Int) {
        let key = _pathKey(prefix: "scrollX", path: path)
        let clamped = max(0, offset)
        if scrollOffsets[key] == clamped { return }
        scrollOffsets[key] = clamped
        _markDirty(path: path)
    }

    func _setScrollOffset(path: [Int], offset: Int) {
        let key = _pathKey(prefix: "scroll", path: path)
        let clamped = max(0, offset)
        if scrollOffsets[key] == clamped { return }
        scrollOffsets[key] = clamped
        _markDirty(path: path)
    }

    @discardableResult
    func _scroll(path: [Int], deltaY: Int, maxOffset: Int) -> Bool {
        let key = _pathKey(prefix: "scroll", path: path)
        let current = scrollOffsets[key] ?? 0
        let next = min(max(0, current + deltaY), max(0, maxOffset))
        if next == current { return false }
        scrollOffsets[key] = next
        _markDirty(path: path)
        return true
    }

    /// Scroll horizontally.
    @discardableResult
    func _scrollX(path: [Int], deltaX: Int, maxOffset: Int) -> Bool {
        let key = _pathKey(prefix: "scrollX", path: path)
        let current = scrollOffsets[key] ?? 0
        let next = min(max(0, current + deltaX), max(0, maxOffset))
        if next == current { return false }
        scrollOffsets[key] = next
        _markDirty(path: path)
        return true
    }

    func _requestScrollTo(id: AnyHashable, anchor: Alignment?, scopePath: [Int]) {
        if _applyScrollRequest(scopePath: scopePath, id: id, anchor: anchor) { return }

        if let existing = pendingScrollRequests.firstIndex(where: { $0.scopePath == scopePath && $0.id == id }) {
            pendingScrollRequests[existing].anchor = anchor
        } else {
            pendingScrollRequests.append(_PendingScrollRequest(scopePath: scopePath, id: id, anchor: anchor))
        }
    }

    private func _applyScrollRequest(scopePath: [Int], id: AnyHashable, anchor: Alignment?) -> Bool {
        guard let target = _resolveScrollTarget(scopePath: scopePath, id: id) else { return false }
        let viewport = max(1, target.viewportHeight)
        let itemHeight = max(1, target.height)
        let minY = max(0, target.minY)
        let maxY = minY + itemHeight

        let desired: Int
        switch anchor?.raw {
        case Alignment.center.raw:
            desired = minY + (itemHeight / 2) - (viewport / 2)
        case Alignment.bottom.raw:
            desired = maxY - viewport
        default:
            desired = minY
        }

        _setScrollOffset(path: target.scrollPath, offset: min(max(0, desired), max(0, target.maxOffsetY)))
        return true
    }

    private func _resolveScrollTarget(scopePath: [Int], id: AnyHashable) -> _ScrollTarget? {
        let candidates = scrollTargets.filter { $0.id == id }
        guard !candidates.isEmpty else { return nil }

        if let exact = candidates.first(where: { $0.readerScopePath == scopePath }) {
            return exact
        }

        let prefixMatches = candidates.compactMap { candidate -> (Int, _ScrollTarget)? in
            guard let scope = candidate.readerScopePath, _isPrefix(scope, of: scopePath) else { return nil }
            return (scope.count, candidate)
        }
        if let best = prefixMatches.max(by: { $0.0 < $1.0 })?.1 {
            return best
        }

        if let unscoped = candidates.first(where: { $0.readerScopePath == nil }) {
            return unscoped
        }

        return candidates.first
    }

    @discardableResult
    func _updateScrollTargets(_ targets: [_ScrollTarget]) -> Bool {
        scrollTargets = targets
        guard !pendingScrollRequests.isEmpty else { return false }

        var remaining: [_PendingScrollRequest] = []
        remaining.reserveCapacity(pendingScrollRequests.count)
        var applied = false
        for request in pendingScrollRequests {
            if _applyScrollRequest(scopePath: request.scopePath, id: request.id, anchor: request.anchor) {
                applied = true
            } else {
                remaining.append(request)
            }
        }
        pendingScrollRequests = remaining
        return applied
    }

    func _updateLastInteractionRegions(
        hitRegions: [_HitRegion],
        scrollRegions: [_ScrollRegion]
    ) {
        lastHitRegions = hitRegions
        lastScrollRegions = scrollRegions
    }

    private func _ensureFocusedControlVisible(path: [Int]) {
        guard let focusedID = focusActivation[path] else { return }
        guard let focusedRect = lastHitRegions.last(where: { $0.actionID == focusedID })?.rect else { return }
        guard let region = lastScrollRegions
            .filter({ _isPrefix($0.path, of: path) })
            .max(by: { $0.path.count < $1.path.count })
        else { return }

        switch region.axis {
        case .horizontal:
            let current = _getScrollOffsetX(path: region.path)
            let viewportMin = region.rect.origin.x
            let viewportMax = region.rect.origin.x + region.rect.size.width
            let rectMin = focusedRect.origin.x
            let rectMax = focusedRect.origin.x + focusedRect.size.width
            var desired = current
            if rectMin < viewportMin {
                desired += rectMin - viewportMin
            } else if rectMax > viewportMax {
                desired += rectMax - viewportMax
            }
            desired = min(max(0, desired), max(0, region.maxOffsetX))
            if desired != current {
                _setScrollOffsetX(path: region.path, offset: desired)
            }
        case .vertical:
            let current = _getScrollOffset(path: region.path)
            let viewportMin = region.rect.origin.y
            let viewportMax = region.rect.origin.y + region.rect.size.height
            let rectMin = focusedRect.origin.y
            let rectMax = focusedRect.origin.y + focusedRect.size.height
            var desired = current
            if rectMin < viewportMin {
                desired += rectMin - viewportMin
            } else if rectMax > viewportMax {
                desired += rectMax - viewportMax
            }
            desired = min(max(0, desired), max(0, region.maxOffsetY))
            if desired != current {
                _setScrollOffset(path: region.path, offset: desired)
            }
        }
    }

    func _navKey(stackPath: [Int]) -> String {
        _pathKey(prefix: "nav", path: stackPath)
    }

    func _registerNavDestinationResolver<Value: Hashable>(stackPath: [Int], valueType: Value.Type, destination: @escaping @MainActor (Value) -> AnyView) {
        _noteBuildSideEffect()
        let key = _navKey(stackPath: stackPath)
        var resolvers = navResolvers[key] ?? [:]
        resolvers[ObjectIdentifier(valueType)] = { any in
            guard let typed = any.base as? Value else { return AnyView(EmptyView()) }
            return destination(typed)
        }
        navResolvers[key] = resolvers
    }

    @MainActor
    func _resolveNavDestination(stackPath: [Int], value: AnyHashable) -> AnyView? {
        let key = _navKey(stackPath: stackPath)
        let typeID = ObjectIdentifier(type(of: value.base))
        guard let resolver = navResolvers[key]?[typeID] else { return nil }
        return resolver(value)
    }

    func _navPush(stackPath: [Int], view: AnyView, ownerKey: String? = nil, onPop: (() -> Void)? = nil) {
        let key = _navKey(stackPath: stackPath)
        var s = navStacks[key] ?? []
        s.append(_NavEntry(view: view, ownerKey: ownerKey, onPop: onPop))
        navStacks[key] = s
        _markDirty(path: stackPath)
    }

    func _navPop(stackPath: [Int]) {
        let key = _navKey(stackPath: stackPath)
        guard var s = navStacks[key], !s.isEmpty else { return }
        let popped = s.removeLast()
        navStacks[key] = s
        popped.onPop?()
        _markDirty(path: stackPath)
    }

    func _navContainsOwner(stackPath: [Int], ownerKey: String) -> Bool {
        let key = _navKey(stackPath: stackPath)
        return navStacks[key]?.contains(where: { $0.ownerKey == ownerKey }) == true
    }

    func _navRemoveOwned(stackPath: [Int], ownerKey: String) {
        let key = _navKey(stackPath: stackPath)
        guard var stack = navStacks[key], let index = stack.lastIndex(where: { $0.ownerKey == ownerKey }) else { return }
        let removed = Array(stack[index...])
        stack.removeSubrange(index...)
        navStacks[key] = stack
        for entry in removed.reversed() {
            entry.onPop?()
        }
        _markDirty(path: stackPath)
    }

    func _navTop(stackPath: [Int]) -> AnyView? {
        let key = _navKey(stackPath: stackPath)
        return navStacks[key]?.last?.view
    }

    func _navDepth(stackPath: [Int]) -> Int {
        let key = _navKey(stackPath: stackPath)
        return navStacks[key]?.count ?? 0
    }

    func _registerAction(_ action: @escaping () -> Void, path: [Int]) -> _ActionID {
        _noteBuildSideEffect()
        let id = _ActionID(raw: nextActionID)
        nextActionID += 1
        // Capture the current environment so `@Environment` reads correctly inside actions.
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        actions[id] = (path: path, env: env, action: action)
        return id
    }

    func _registerDragGesture(_ gesture: DragGesture, actionID: _ActionID, path: [Int]) -> _DragGestureID {
        _noteBuildSideEffect()
        let id = _DragGestureID(raw: nextDragGestureID)
        nextDragGestureID += 1
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        dragGestures[id] = (path: path, env: env, gesture: gesture)
        dragGestureByActionID[actionID] = id
        return id
    }

    @MainActor
    func _invokeDragGesture(_ id: _DragGestureID, start: CGPoint, current: CGPoint, ended: Bool) {
        guard let entry = dragGestures[id] else { return }
        let value = DragGesture.Value(
            startLocation: start,
            location: current,
            translation: CGSize(width: current.x - start.x, height: current.y - start.y)
        )
        _UIRuntime.$_currentEnvironment.withValue(entry.env) {
            _BuildContext.withRuntime(self, path: entry.path) {
                entry.gesture._fireChanged(value)
                if ended {
                    entry.gesture._fireEnded(value)
                }
            }
        }
        _markDirty(path: entry.path)
    }

    @discardableResult
    @MainActor
    public func _handleNativeDragEvent(actionID rawActionID: Int, eventType: Int, x: Double, y: Double) -> Bool {
        let point = CGPoint(x: x, y: y)
        switch eventType {
        case 1:
            let actionID = _ActionID(raw: rawActionID)
            guard let dragID = dragGestureByActionID[actionID] else { return false }
            activeNativeDragGesture = (dragID, point, false)
            return false
        case 5:
            guard let activeNativeDragGesture else { return false }
            let dx = point.x - activeNativeDragGesture.start.x
            let dy = point.y - activeNativeDragGesture.start.y
            guard activeNativeDragGesture.hasMoved || hypot(dx, dy) >= 4 else { return false }
            self.activeNativeDragGesture = (activeNativeDragGesture.id, activeNativeDragGesture.start, true)
            _invokeDragGesture(activeNativeDragGesture.id, start: activeNativeDragGesture.start, current: point, ended: false)
            return true
        case 2:
            guard let activeNativeDragGesture else { return false }
            self.activeNativeDragGesture = nil
            guard activeNativeDragGesture.hasMoved else { return false }
            _invokeDragGesture(activeNativeDragGesture.id, start: activeNativeDragGesture.start, current: point, ended: true)
            _performDropFallback(at: point)
            return true
        default:
            return false
        }
    }

    func _beginDragFallback(provider: NSItemProvider, location: CGPoint = .zero) {
        activeDragItemProviders = [provider]
        activeDragLocation = location
        _markDirty()
    }

    public func _recordNativeActivationPoint(actionID rawActionID: Int, x: Double, y: Double) {
        guard rawActionID > 0 else { return }
        activationPointsByActionID[_ActionID(raw: rawActionID)] = CGPoint(x: x, y: y)
    }

    func _dropInfoForActiveDragFallback() -> DropInfo? {
        guard !activeDragItemProviders.isEmpty else { return nil }
        return DropInfo(location: activeDragLocation, itemProviders: activeDragItemProviders)
    }

    func _registerDropFallbackAction(_ id: _ActionID) {
        dropFallbackActionIDs.insert(id)
    }

    @discardableResult
    func _performDropFallback(at point: CGPoint) -> Bool {
        guard !activeDragItemProviders.isEmpty else { return false }
        let hitPoint = _Point(x: Int(point.x), y: Int(point.y))
        guard let hit = lastHitRegions.last(where: { region in
            region.rect.contains(hitPoint) && dropFallbackActionIDs.contains(region.actionID)
        }) else { return false }
        activeDragLocation = point
        _recordNativeActivationPoint(actionID: hit.actionID.raw, x: point.x, y: point.y)
        _invokeAction(hit.actionID)
        return true
    }

    func _performNativeDragFallback(on view: NSView) -> Bool {
#if os(Linux)
        guard !activeDragItemProviders.isEmpty, !view.registeredDraggedTypes.isEmpty else { return false }
        let pasteboard = NSPasteboard()
        guard pasteboard.writeObjects(activeDragItemProviders.map(\.object)) else { return false }
        guard view.registeredDraggedTypes.contains(where: { pasteboard.types.contains($0) }) else { return false }

        let windowPoint: NSPoint
        if let currentInvokedActionID,
           let activationPoint = activationPointsByActionID[currentInvokedActionID] {
            windowPoint = activationPoint
        } else {
            let localCenter = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
            windowPoint = view.convert(localCenter, to: nil)
        }
        let info = NSDraggingInfoSnapshot(draggingPasteboard: pasteboard, draggingLocation: windowPoint)
        guard !view.draggingEntered(info).isEmpty || !view.draggingUpdated(info).isEmpty else { return false }
        let performed = view.performDragOperation(info)
        if performed {
            _endDragFallback()
        }
        return performed
#else
        _ = view
        return false
#endif
    }

    func _hasActiveDragFallback() -> Bool {
        !activeDragItemProviders.isEmpty
    }

    func _endDragFallback() {
        guard !activeDragItemProviders.isEmpty else { return }
        activeDragItemProviders = []
        activeDragLocation = .zero
        _markDirty()
    }

    func _registerOnAppear(path: [Int], action: @escaping () -> Void) {
        _noteBuildSideEffect()
        let key = _viewPathKey(path: path)
        onAppearSeenThisFrame.insert(key)

        guard onAppearPathKeys.insert(key).inserted else { return }

        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        _UIRuntime.$_currentEnvironment.withValue(env) {
            _BuildContext.withRuntime(self, path: path) {
                action()
            }
        }
    }

    func _registerOnDisappear(path: [Int], action: @escaping () -> Void) {
        _noteBuildSideEffect()
        let key = _viewPathKey(path: path)
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        onDisappearHandlers[key] = (path: path, env: env, action: action)
        onDisappearSeenThisFrame.insert(key)
    }

    func _invokeAction(_ id: _ActionID) {
        guard let entry = actions[id] else { return }
        let previousInvokedActionID = currentInvokedActionID
        currentInvokedActionID = id
        defer {
            currentInvokedActionID = previousInvokedActionID
            activationPointsByActionID.removeValue(forKey: id)
        }
        _UIRuntime.$_currentEnvironment.withValue(entry.env) {
            _BuildContext.withRuntime(self, path: entry.path) {
                entry.action()
            }
        }
        // Actions can mutate shared reference state read by sibling or ancestor views.
        // Rebuild from the root so navigation, selections, and toolbar state update together.
        _markDirty()
    }

    /// Public entry point for invoking an action by its raw integer ID.
    /// Used by renderers that need to fire actions from native widgets.
    public func invokeActionByRawID(_ rawID: Int) {
        _invokeAction(_ActionID(raw: rawID))
    }

    func _registerDateSetter(_ setter: @escaping (TimeInterval) -> Void, path: [Int]) -> _ActionID {
        _noteBuildSideEffect()
        let id = _ActionID(raw: nextActionID)
        nextActionID += 1
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        dateSetters[id] = (path: path, env: env, setter: setter)
        return id
    }

    func _registerDoubleSetter(_ setter: @escaping (Double) -> Void, path: [Int]) -> _ActionID {
        _noteBuildSideEffect()
        let id = _ActionID(raw: nextActionID)
        nextActionID += 1
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        doubleSetters[id] = (path: path, env: env, setter: setter)
        return id
    }

    @discardableResult
    public func setDateForRawActionID(_ rawID: Int, timestamp: TimeInterval) -> Bool {
        let id = _ActionID(raw: rawID)
        guard let entry = dateSetters[id] else { return false }
        _UIRuntime.$_currentEnvironment.withValue(entry.env) {
            _BuildContext.withRuntime(self, path: entry.path) {
                entry.setter(timestamp)
            }
        }
        _markDirty(path: entry.path)
        return true
    }

    @discardableResult
    public func setDoubleForRawActionID(_ rawID: Int, value: Double) -> Bool {
        let id = _ActionID(raw: rawID)
        guard let entry = doubleSetters[id] else { return false }
        _UIRuntime.$_currentEnvironment.withValue(entry.env) {
            _BuildContext.withRuntime(self, path: entry.path) {
                entry.setter(value)
            }
        }
        _markDirty(path: entry.path)
        return true
    }

    /// Public entry point for native renderers to mirror platform focus changes
    /// back into OmniUI's focus path and any attached `@FocusState` bindings.
    @discardableResult
    public func focusByRawActionID(_ rawID: Int) -> Bool {
        let id = _ActionID(raw: rawID)
        if let focusPath = focusActivation.first(where: { $0.value == id })?.key {
            return _setFocus(path: focusPath)
        }
        guard let actionPath = actions[id]?.path else { return false }
        return _setFocus(path: actionPath)
    }

    /// Replace text for the text field associated with a native-widget action.
    /// This intentionally routes through the registered text editor so bindings,
    /// focus state, cursor state, keyboard filtering, and dirty marking stay in one place.
    @MainActor
    public func replaceTextForRawActionID(_ rawID: Int, previous: String, next: String) {
        let id = _ActionID(raw: rawID)
        _invokeAction(id)
        guard let path = _textEditorPath(forNativeActionID: id) else { return }

        if previous == next { return }

        let newScalars = Array(next.unicodeScalars)
        _handleKey(.end)
        for _ in previous.unicodeScalars {
            _handleKey(.backspace)
        }
        for scalar in newScalars {
            _handleKey(.char(scalar.value))
        }
        _markDirty(path: path)
    }

    @MainActor
    public func handleNativeKeyForRawActionID(_ rawID: Int, keyKind: Int, codepoint: UInt32) {
        if rawID > 0 {
            let id = _ActionID(raw: rawID)
            _invokeAction(id)
        }

        if _dispatchKeyPress(kind: keyKind, codepoint: codepoint) {
            return
        }

        if rawID <= 0 {
            switch keyKind {
            case 7:
                _ = invokeKeyboardShortcut(.return)
            case 8:
                _ = invokeKeyboardShortcut(.escape)
            default:
                break
            }
            return
        }

        let id = _ActionID(raw: rawID)
        guard let path = _textEditorPath(forNativeActionID: id) else { return }

        switch keyKind {
        case 7:
            submitFocusedTextEditor()
            return
        case 8:
            _ = invokeKeyboardShortcut(.escape)
            return
        case 0:
            _handleKey(.char(codepoint))
        case 1:
            _handleKey(.backspace)
        case 2:
            _handleKey(.delete)
        case 3:
            _handleKey(.left)
        case 4:
            _handleKey(.right)
        case 5:
            _handleKey(.home)
        case 6:
            _handleKey(.end)
        default:
            return
        }
        _markDirty(path: path)
    }

    private func _textEditorPath(forNativeActionID id: _ActionID) -> [Int]? {
        let candidates: [[Int]?] = [
            focusActivation.first(where: { $0.value == id })?.key,
            focusedPath,
            actions[id]?.path,
        ]
        for candidate in candidates {
            guard let path = candidate, textEditors[path] != nil else { continue }
            return path
        }
        return nil
    }

    @discardableResult
    func _setFocus(path: [Int]?) -> Bool {
        let old = focusedPath
        focusedPath = path
        // Update any `FocusState<Bool>` bindings.
        if !focusBoolBindings.isEmpty {
            for (p, set) in focusBoolBindings {
                set(p == path)
            }
        }
        if let expanded = expandedPickerPath, let p = path {
            if !_isPrefix(expanded, of: p) {
                expandedPickerPath = nil
            }
        } else if expandedPickerPath != nil, path == nil {
            expandedPickerPath = nil
        }
        if old != path, let path, !_isBuildingFrame {
            _ensureFocusedControlVisible(path: path)
        }
        if old != path, !_isBuildingFrame {
            if let old { _markDirty(path: old) }
            if let path { _markDirty(path: path) }
            if old == nil || path == nil { _markDirty() }
        }
        return old != path
    }

    func _isFocused(path: [Int]) -> Bool {
        focusedPath == path
    }

    func _registerTextEditor(path: [Int], _ editor: _TextEditor) {
        _noteBuildSideEffect()
        textEditors[path] = editor
    }

    func _registerFocusable(path: [Int], activate: _ActionID) {
        _noteBuildSideEffect()
        focusOrder.append(path)
        focusActivation[path] = activate
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        let priority = env._focusPriority
        if priority != 0 {
            focusPriorities[path] = priority
        }
        if let captureID = _UIRuntime._currentFocusCaptureID, focusCaptureResults[captureID] == nil {
            focusCaptureResults[captureID] = path
        }
    }

    func _isPickerExpanded(path: [Int]) -> Bool {
        expandedPickerPath == path
    }

    func _openPicker(path: [Int]) {
        if expandedPickerPath == path { return }
        expandedPickerPath = path
        _markDirty(path: path)
    }

    func _closePicker(path: [Int]) {
        if expandedPickerPath == path {
            expandedPickerPath = nil
            _markDirty(path: path)
        }
    }

    public func hasExpandedPicker() -> Bool {
        expandedPickerPath != nil
    }

    public func collapseExpandedPicker() {
        guard let expanded = expandedPickerPath else { return }
        expandedPickerPath = nil
        _markDirty(path: expanded)
    }

    public func focusNextWithinExpandedPicker() {
        guard let expanded = expandedPickerPath else {
            focusNext()
            return
        }
        let candidates = focusOrder.filter { _isPrefix(expanded, of: $0) }
        guard !candidates.isEmpty else { return }
        let next: [Int]
        if let f = focusedPath, let idx = candidates.firstIndex(of: f) {
            next = candidates[(idx + 1) % candidates.count]
        } else {
            next = candidates[0]
        }
        _setFocus(path: next)
    }

    public func focusPrevWithinExpandedPicker() {
        guard let expanded = expandedPickerPath else {
            focusPrev()
            return
        }
        let candidates = focusOrder.filter { _isPrefix(expanded, of: $0) }
        guard !candidates.isEmpty else { return }
        let next: [Int]
        if let f = focusedPath, let idx = candidates.firstIndex(of: f) {
            next = candidates[(idx - 1 + candidates.count) % candidates.count]
        } else {
            next = candidates[0]
        }
        _setFocus(path: next)
    }

    @MainActor
    public func _handleKeyPress(_ codepoint: UInt32) {
        _handleKey(.char(codepoint))
    }

    @MainActor
    public func _handleKey(_ ev: _KeyEvent) {
        // When a picker is expanded, it owns the keyboard.
        if expandedPickerPath != nil { return }
        if _dispatchKeyPress(event: ev) { return }
        guard let p = focusedPath, let editor = textEditors[p] else { return }
        editor.handle(ev)
        _markDirty(path: p)
    }

    func _getTextCursor(path: [Int]) -> Int {
        textEditorCursors[path] ?? 0
    }

    func _setTextCursor(path: [Int], _ v: Int) {
        let next = max(0, v)
        if textEditorCursors[path] == next { return }
        textEditorCursors[path] = next
        _markDirty(path: path)
    }

    func _ensureTextCursorAtEndIfUnset(path: [Int], text: String) {
        if textEditorCursors[path] == nil {
            textEditorCursors[path] = text.unicodeScalars.count
            _markDirty(path: path)
        }
    }

    struct _MultiLineEditorState {
        var text: String
        var cursor: Int
    }

    func _getTextEditor(path: [Int], initial: String) -> _MultiLineEditorState {
        let cursor = textEditorCursors[path] ?? initial.unicodeScalars.count
        return _MultiLineEditorState(text: initial, cursor: cursor)
    }

    func _updateTextEditor(path: [Int], text: String) {
        // Sync external binding change to the cursor
        let maxCursor = text.unicodeScalars.count
        if let existing = textEditorCursors[path], existing > maxCursor {
            textEditorCursors[path] = maxCursor
        }
    }

    // MARK: Preference System

    func _setPreferenceRaw(keyID: ObjectIdentifier, value: Any, reduce: (inout Any, () -> Any) -> Void) {
        if let existing = _preferences[keyID] {
            var parentValue = value
            reduce(&parentValue, { existing })
            _preferences[keyID] = parentValue
        } else {
            _preferences[keyID] = value
        }
    }

    func _registerPreferenceCallback(keyID: ObjectIdentifier, callback: @escaping (Any) -> Void) {
        _preferenceCallbacks.append((keyID: keyID, callback: callback))
    }

    func _firePreferenceCallbacks() {
        for (keyID, callback) in _preferenceCallbacks {
            if let value = _preferences[keyID] {
                // Only fire if changed
                let prevStr = String(describing: _previousPreferences[keyID] ?? "nil")
                let curStr = String(describing: value)
                if prevStr != curStr {
                    callback(value)
                }
            }
        }
        _previousPreferences = _preferences
    }

    func _clearPreferences() {
        _preferences.removeAll(keepingCapacity: true)
        _preferenceCallbacks.removeAll(keepingCapacity: true)
    }

    public func isTextEditingFocused() -> Bool {
        guard let p = focusedPath else { return false }
        return textEditors[p] != nil
    }

    public func focusNext() {
        let candidates = _activeFocusCycle()
        guard !candidates.isEmpty else { return }
        expandedPickerPath = nil
        let next: [Int]
        if let f = focusedPath, let idx = candidates.firstIndex(of: f) {
            next = candidates[(idx + 1) % candidates.count]
        } else {
            next = candidates[0]
        }
        _setFocus(path: next)
    }

    public func focusPrev() {
        let candidates = _activeFocusCycle()
        guard !candidates.isEmpty else { return }
        expandedPickerPath = nil
        let next: [Int]
        if let f = focusedPath, let idx = candidates.firstIndex(of: f) {
            next = candidates[(idx - 1 + candidates.count) % candidates.count]
        } else {
            next = candidates[0]
        }
        _setFocus(path: next)
    }

    public func activateFocused() {
        guard let f = focusedPath, let id = focusActivation[f] else { return }
        _invokeAction(id)
    }

    public func focusedActionRawID() -> Int? {
        guard let f = focusedPath, let id = focusActivation[f] else { return nil }
        return id.raw
    }

    public func dismissTopOverlay() -> Bool {
        guard let overlay = overlays.last else { return false }
        overlay.dismiss()
        return true
    }

    private func _overlayFocusablePaths() -> [[Int]] {
        focusOrder.filter { !$0.isEmpty && $0[0] == Self._overlayPathSentinel }
    }

    private func _activeFocusCycle() -> [[Int]] {
        let overlayFocusOrder = _overlayFocusablePaths()
        return overlayFocusOrder.isEmpty ? focusOrder : overlayFocusOrder
    }

    func _registerKeyboardShortcut(_ shortcut: KeyboardShortcut, forFocusablePath path: [Int]) {
        _noteBuildSideEffect()
        guard let id = focusActivation[path] else { return }
        keyboardShortcuts[shortcut, default: []].append((path: path, id: id))
    }

    func _registerKeyPress(_ key: KeyEquivalent, forFocusablePath path: [Int], actionPath: [Int], action: @escaping () -> Bool) {
        _noteBuildSideEffect()
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        var handlers = keyPressHandlers[path] ?? [:]
        handlers[key] = (path: actionPath, env: env, action: action)
        keyPressHandlers[path] = handlers
    }

    @discardableResult
    private func _dispatchKeyPress(kind: Int, codepoint: UInt32) -> Bool {
        guard let key = _keyEquivalent(kind: kind, codepoint: codepoint) else { return false }
        return _dispatchKeyPress(key)
    }

    @discardableResult
    private func _dispatchKeyPress(event: _KeyEvent) -> Bool {
        guard let key = _keyEquivalent(event: event) else { return false }
        return _dispatchKeyPress(key)
    }

    @discardableResult
    private func _dispatchKeyPress(_ key: KeyEquivalent) -> Bool {
        guard let focusedPath else { return false }
        var candidate = focusedPath
        while true {
            if let entry = keyPressHandlers[candidate]?[key] {
                let handled = _UIRuntime.$_currentEnvironment.withValue(entry.env) {
                    _BuildContext.withRuntime(self, path: entry.path) {
                        entry.action()
                    }
                }
                if handled {
                    _markDirty(path: entry.path)
                    return true
                }
            }
            guard !candidate.isEmpty else { break }
            candidate.removeLast()
        }
        return false
    }

    private func _keyEquivalent(kind: Int, codepoint: UInt32) -> KeyEquivalent? {
        switch kind {
        case 0:
            guard let scalar = UnicodeScalar(codepoint) else { return nil }
            return KeyEquivalent(Character(scalar).description)
        case 3:
            return .leftArrow
        case 4:
            return .rightArrow
        case 5:
            return .home
        case 6:
            return .end
        case 7:
            return .return
        case 8:
            return .escape
        case 9:
            return .upArrow
        case 10:
            return .downArrow
        default:
            return nil
        }
    }

    private func _keyEquivalent(event: _KeyEvent) -> KeyEquivalent? {
        switch event {
        case .char(let codepoint):
            guard let scalar = UnicodeScalar(codepoint) else { return nil }
            return KeyEquivalent(Character(scalar).description)
        case .left:
            return .leftArrow
        case .right:
            return .rightArrow
        case .home:
            return .home
        case .end:
            return .end
        default:
            return nil
        }
    }

    @discardableResult
    public func invokeKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> Bool {
        func lookup(_ mods: EventModifiers) -> _ActionID? {
            let entries = keyboardShortcuts[KeyboardShortcut(key, modifiers: mods)] ?? []
            if !overlays.isEmpty {
                return entries.reversed().first { entry in
                    !entry.path.isEmpty && entry.path[0] == Self._overlayPathSentinel
                }?.id
            }
            return entries.last?.id
        }

        if let id = lookup(modifiers) {
            _invokeAction(id)
            return true
        }

        // Terminal environments typically don't have a "Command" key. We treat Control and Command as
        // interchangeable for shortcut matching so `KeyboardShortcut(..., modifiers: .command)` works.
        if modifiers.contains(.control), !modifiers.contains(.command) {
            let alt = modifiers.subtracting(.control).union(.command)
            if let id = lookup(alt) {
                _invokeAction(id)
                return true
            }
        }
        if modifiers.contains(.command), !modifiers.contains(.control) {
            let alt = modifiers.subtracting(.command).union(.control)
            if let id = lookup(alt) {
                _invokeAction(id)
                return true
            }
        }

        return false
    }

    @MainActor
    private func _runTask(key: String) async {
        guard let entry = _withTaskRegistryLock({ tasks[key] }) else { return }
        let env = entry.env
        let path = entry.path
        let action = entry.action

        // Run with the view's environment so `@Environment` reads correctly.
        await _UIRuntime.$_current.withValue(self) {
            await _UIRuntime.$_currentPath.withValue(path) {
                await _UIRuntime.$_currentEnvironment.withValue(env) {
                    await action()
                }
            }
        }
        _markDirty(path: path)
    }

    func _registerTask(path: [Int], priority: TaskPriority? = nil, action: @escaping () async -> Void) {
        _noteBuildSideEffect()
        let key = _pathKey(prefix: "task", path: path)
        let needsRegistration = _withTaskRegistryLock {
            tasksSeenThisFrame.insert(key)
            return tasks[key] == nil
        }
        if !needsRegistration { return }

        let runtime = self
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment

        let p = priority ?? .userInitiated
        let inserted = _withTaskRegistryLock {
            if tasks[key] != nil { return false }
            tasks[key] = _TaskEntry(env: env, path: path, action: action, task: nil)
            return true
        }
        guard inserted else { return }

        let t = Task(priority: p) { @MainActor in
            await runtime._runTask(key: key)
        }
        let stored = _withTaskRegistryLock {
            guard tasks[key] != nil else { return false }
            tasks[key]?.task = t
            return true
        }
        if !stored {
            t.cancel()
        }
    }

    // Task registration with id-based cancellation/restart
    private var taskLastIds: [String: AnyHashable] = [:]

    private func _withTaskRegistryLock<R>(_ body: () -> R) -> R {
        taskRegistryLock.lock()
        defer { taskRegistryLock.unlock() }
        return body()
    }

    func _registerTaskWithId(path: [Int], id: AnyHashable, priority: TaskPriority? = nil, action: @escaping () async -> Void) {
        _noteBuildSideEffect()
        let key = _pathKey(prefix: "task", path: path)
        let previousTask: Task<Void, Never>? = _withTaskRegistryLock {
            tasksSeenThisFrame.insert(key)

            if let existing = tasks[key] {
                if let lastId = taskLastIds[key], lastId == id {
                    return nil
                }
                tasks[key] = nil
                taskLastIds[key] = id
                return existing.task
            }

            taskLastIds[key] = id
            return nil
        }
        previousTask?.cancel()
        let stillNeedsRegistration = _withTaskRegistryLock {
            tasks[key] == nil && taskLastIds[key] == id
        }
        if !stillNeedsRegistration { return }

        let runtime = self
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment

        let p = priority ?? .userInitiated
        let inserted = _withTaskRegistryLock {
            guard taskLastIds[key] == id else { return false }
            tasks[key] = _TaskEntry(env: env, path: path, action: action, task: nil)
            return true
        }
        guard inserted else { return }

        let t = Task(priority: p) { @MainActor in
            await runtime._runTask(key: key)
        }
        let stored = _withTaskRegistryLock {
            guard tasks[key] != nil, taskLastIds[key] == id else { return false }
            tasks[key]?.task = t
            return true
        }
        if !stored {
            t.cancel()
        }
    }

    // Focus section support
    private var _focusSectionStack: [[Int]] = []
    private var _focusSections: [([Int], ClosedRange<Int>)] = [] // (sectionPath, range in focusOrder)

    func _beginFocusSection(path: [Int]) {
        _noteBuildSideEffect()
        _focusSectionStack.append(path)
    }

    func _endFocusSection() {
        _noteBuildSideEffect()
        _ = _focusSectionStack.popLast()
    }

    func _launchAsyncAction(path: [Int], action: @escaping () async -> Void) {
        _noteBuildSideEffect()
        let runtime = self
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        let id = _withTaskRegistryLock {
            let id = nextLaunchedAsyncActionID
            nextLaunchedAsyncActionID += 1
            launchedAsyncActions[id] = _TaskEntry(env: env, path: path, action: action, task: nil)
            return id
        }
        let task = Task { @MainActor in
            await runtime._runLaunchedAsyncAction(id: id)
        }
        let stored = _withTaskRegistryLock {
            guard launchedAsyncActions[id] != nil else { return false }
            launchedAsyncActions[id]?.task = task
            return true
        }
        if !stored {
            task.cancel()
        }
    }

    @MainActor
    private func _runLaunchedAsyncAction(id: Int) async {
        guard let entry = _withTaskRegistryLock({ launchedAsyncActions[id] }) else { return }
        await _UIRuntime.$_current.withValue(self) {
            await _UIRuntime.$_currentPath.withValue(entry.path) {
                await _UIRuntime.$_currentEnvironment.withValue(entry.env) {
                    await entry.action()
                }
            }
        }
        _withTaskRegistryLock {
            launchedAsyncActions[id] = nil
        }
        _markDirty()
    }

    func _reconcileTasksAfterFrame() {
        let toCancel: [Task<Void, Never>?] = _withTaskRegistryLock {
            guard !tasks.isEmpty else { return [] }
            let seen = tasksSeenThisFrame
            var handles: [Task<Void, Never>?] = []
            handles.reserveCapacity(tasks.count)
            for (k, entry) in tasks where !seen.contains(k) {
                handles.append(entry.task)
                tasks[k] = nil
                taskLastIds[k] = nil
            }
            return handles
        }
        for handle in toCancel {
            handle?.cancel()
        }
    }

    func _getState<Value>(seed: _StateSeed, path: [Int], initial: () -> Value) -> Value {
        let key = _stateKey(seed: seed, path: path)
        if _isBuildingFrame {
            _recordStateRead(stateKey: key, viewPath: _UIRuntime._currentPath ?? path)
        }
        if let existing = state[key] as? Value {
            return existing
        }
        let v = initial()
        state[key] = v
        return v
    }

    func _setState<Value>(seed: _StateSeed, path: [Int], value: Value) {
        let key = _stateKey(seed: seed, path: path)
        if let old = state[key] as? AnyHashable, let new = value as? AnyHashable, old == new {
            return
        }
        traceStateSet(path: path, key: key, value: value)
        state[key] = value
        _markDirtyForState(stateKey: key, ownerPath: path)
    }

    func _setState<Value: Equatable>(seed: _StateSeed, path: [Int], value: Value) {
        let key = _stateKey(seed: seed, path: path)
        if let existing = state[key] as? Value, existing == value {
            return
        }
        traceStateSet(path: path, key: key, value: value)
        state[key] = value
        _markDirtyForState(stateKey: key, ownerPath: path)
    }

    private func traceStateSet<Value>(path: [Int], key: String, value: Value) {
        guard ProcessInfo.processInfo.environment["OMNIUI_STATE_TRACE"] == "1" else { return }
        let pathText = path.map(String.init).joined(separator: ".")
        FileHandle.standardError.write(
            Data("OmniUI state: path=\(pathText) key=\(key) \(String(reflecting: Value.self))=\(value)\n".utf8)
        )
    }

    private func _stateKey(seed: _StateSeed, path: [Int]) -> String {
        // Keep this deterministic and stable across processes (avoid ObjectIdentifier / memory addresses).
        let p = path.map(String.init).joined(separator: ".")
        return "\(seed.fileID):\(seed.line):\(p)"
    }

    private struct _OnChangeRuntimeState<Value> {
        var value: Value
        var firedInitial: Bool
    }

    func _consumeOnChange<Value: Equatable>(
        path: [Int],
        value: Value,
        initial: Bool
    ) -> (shouldFire: Bool, oldValue: Value) {
        let key = _pathKey(prefix: "onChange", path: path)
        if var state = modifierState[key] as? _OnChangeRuntimeState<Value> {
            let oldValue = state.value
            var shouldFire = false

            if initial && !state.firedInitial {
                state.firedInitial = true
                shouldFire = true
            }
            if oldValue != value {
                state.value = value
                shouldFire = true
            }

            modifierState[key] = state
            if shouldFire {
                traceOnChange(path: path, oldValue: oldValue, newValue: value)
                _noteBuildSideEffect()
            }
            return (shouldFire, oldValue)
        }

        modifierState[key] = _OnChangeRuntimeState(value: value, firedInitial: initial)
        if initial {
            traceOnChange(path: path, oldValue: value, newValue: value)
            _noteBuildSideEffect()
        }
        return (initial, value)
    }

    private func traceOnChange<Value>(path: [Int], oldValue: Value, newValue: Value) {
        guard ProcessInfo.processInfo.environment["OMNIUI_ONCHANGE_TRACE"] == "1" else { return }
        let pathText = path.map(String.init).joined(separator: ".")
        FileHandle.standardError.write(
            Data("OmniUI onChange: path=\(pathText) \(String(reflecting: Value.self)) \(oldValue) -> \(newValue)\n".utf8)
        )
    }

    func _replaceModifierValue<Value>(
        prefix: String,
        path: [Int],
        value: Value
    ) -> Value? {
        let key = _pathKey(prefix: prefix, path: path)
        let previous = modifierState[key] as? Value
        modifierState[key] = value
        return previous
    }

    @MainActor
    public func debugRender<V: View>(_ root: V, size: _Size, renderShapeGlyphs: Bool = true) -> DebugSnapshot {
        let runtime = self
        var laidOut: _DebugLayout.Result?
        var pass = 0
        repeat {
            pass += 1
            runtime._prepareRuntimeRegistriesForFrame()
            runtime._beginFrameBuild(size: size)
            var node = runtime._buildRootNode(root, size: size)
            node = runtime._applyOverlays(to: node)
            runtime._finalizePostBuildState()

            let current = _DebugLayout.layout(
                node: node,
                in: _Rect(origin: _Point(x: 0, y: 0), size: size),
                renderShapeGlyphs: renderShapeGlyphs
            )
            runtime._updateScrollTargets(current.scrollTargets)
            runtime._updateLastInteractionRegions(
                hitRegions: current.hitRegions,
                scrollRegions: current.scrollRegions
            )
            runtime._firePreferenceCallbacks()
            runtime._finishFrameBuild(size: size)
            laidOut = current
        } while runtime._hasPendingSynchronousInvalidation && pass < Self._maxSynchronousRenderPasses

        let finalLayout = laidOut!
        let focusedRect: _Rect? = {
            guard let raw = focusedActionRawID() else { return nil }
            return finalLayout.hitRegions.last(where: { $0.actionID.raw == raw })?.rect
        }()
        return DebugSnapshot(
            size: size,
            lines: finalLayout.lines,
            cells: finalLayout.cells,
            styledCells: finalLayout.styledCells,
            focusedRect: focusedRect,
            shapeRegions: finalLayout.shapeRegions,
            hitRegions: finalLayout.hitRegions,
            hoverRegions: finalLayout.hoverRegions,
            scrollRegions: finalLayout.scrollRegions,
            runtime: runtime
        )
    }
}

extension _UIRuntime {
    func _markDirtyFromModelContext() {
        _markDirty()
    }

    public func _markDirtyFromExternalResource() {
        _clearExternalResourceBackedState()
        _markDirty()
    }

    private func _clearExternalResourceBackedState() {
        let prefixes = [
            "OmniUICore.AppStorage:",
        ]
        let keys = state.keys.filter { key in
            prefixes.contains { key.hasPrefix($0) }
        }
        guard !keys.isEmpty else { return }
        for key in keys {
            state.removeValue(forKey: key)
            _stateReaders.removeValue(forKey: key)
        }
        for viewKey in Array(_viewStateDependencies.keys) {
            _viewStateDependencies[viewKey]?.subtract(keys)
            if _viewStateDependencies[viewKey]?.isEmpty == true {
                _viewStateDependencies.removeValue(forKey: viewKey)
            }
        }
    }

    func _ensureReceiveSubscription(path: [Int], identity: String, subscribe: () -> AnyObject) {
        _noteBuildSideEffect()
        let key = _pathKey(prefix: "receive:\(identity)", path: path)
        guard receiveSubscriptions[key] == nil else { return }
        if _omniRuntimeReceiveTraceEnabled() {
            let line = "[OmniKit receive] install identity=\(identity) path=\(path)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
        receiveSubscriptions[key] = subscribe()
    }

    /// Called by `_ObservationRegistrar.notify()` when an `@Observable` object's
    /// property changes.  Marks the specific view path dirty so only the relevant
    /// subtree is rebuilt.
    public func _markDirtyFromObservation(path: [Int]) {
        _markDirty(path: path)
    }

    func _registerOverlay(view: AnyView, dismiss: @escaping () -> Void) {
        _noteBuildSideEffect()
        overlays.append(_OverlayEntry(view: view, dismiss: dismiss))
    }

    func _registerFocusBoolBinding(path: [Int], set: @escaping (Bool) -> Void) {
        _noteBuildSideEffect()
        focusBoolBindings[path] = set
    }

    func _registerSubmitHandler(controlPath: [Int], actionScopePath: [Int], action: @escaping () -> Void) {
        _noteBuildSideEffect()
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        submitHandlers[controlPath] = (path: actionScopePath, env: env, action: action)
    }

    func _registerHoverHandler(actionScopePath: [Int], action: @escaping (Bool) -> Void) -> _HoverID {
        _noteBuildSideEffect()
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        let id = _HoverID(raw: nextHoverID)
        nextHoverID += 1
        hoverHandlers[id] = (path: actionScopePath, env: env, action: action)
        return id
    }

    func updateHover(_ id: _HoverID?) {
        guard activeHoverID != id else { return }
        if let previous = activeHoverID, let entry = hoverHandlers[previous] {
            _UIRuntime.$_currentEnvironment.withValue(entry.env) {
                _BuildContext.withRuntime(self, path: entry.path) {
                    entry.action(false)
                }
            }
        }
        activeHoverID = id
        if let id, let entry = hoverHandlers[id] {
            _UIRuntime.$_currentEnvironment.withValue(entry.env) {
                _BuildContext.withRuntime(self, path: entry.path) {
                    entry.action(true)
                }
            }
        }
        _markDirty()
    }

    public func clearHover() {
        updateHover(nil)
    }

    func _registerExitCommand(actionScopePath: [Int], action: @escaping () -> Void) {
        _noteBuildSideEffect()
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        exitCommand = (path: actionScopePath, env: env, action: action)
    }

    @discardableResult
    public func invokeExitCommand() -> Bool {
        guard let entry = exitCommand else { return false }
        _UIRuntime.$_currentEnvironment.withValue(entry.env) {
            _BuildContext.withRuntime(self, path: entry.path) {
                entry.action()
            }
        }
        return true
    }

    public func submitFocusedTextEditor() {
        guard let p = focusedPath, let entry = submitHandlers[p] else { return }
        _UIRuntime.$_currentEnvironment.withValue(entry.env) {
            _BuildContext.withRuntime(self, path: entry.path) {
                entry.action()
            }
        }
    }
}

extension _UIRuntime {
    @MainActor
    public func render<V: View>(_ root: V, size: _Size) -> RenderSnapshot {
        let runtime = self
        var laidOut: _RenderLayout.Result?
        var pass = 0
        repeat {
            pass += 1
            runtime._prepareRuntimeRegistriesForFrame()
            runtime._beginFrameBuild(size: size)
            var node = runtime._buildRootNode(root, size: size)
            node = runtime._applyOverlays(to: node)
            runtime._finalizePostBuildState()

            let current = _RenderLayout.layout(node: node, size: size)
            runtime._updateScrollTargets(current.scrollTargets)
            runtime._updateLastInteractionRegions(
                hitRegions: current.hitRegions,
                scrollRegions: current.scrollRegions
            )
            runtime._firePreferenceCallbacks()
            runtime._finishFrameBuild(size: size)
            laidOut = current
        } while runtime._hasPendingSynchronousInvalidation && pass < Self._maxSynchronousRenderPasses

        let finalLayout = laidOut!
        let focusedRect: _Rect? = {
            guard let raw = focusedActionRawID() else { return nil }
            return finalLayout.hitRegions.last(where: { $0.actionID.raw == raw })?.rect
        }()
        return RenderSnapshot(
            size: size,
            ops: finalLayout.ops,
            focusedRect: focusedRect,
            shapeRegions: finalLayout.shapeRegions,
            cursorPosition: finalLayout.cursorPosition,
            activeMenu: finalLayout.activeMenu,
            activePicker: finalLayout.activePicker,
            activeTextField: finalLayout.activeTextField,
            hitRegions: finalLayout.hitRegions,
            hoverRegions: finalLayout.hoverRegions,
            scrollRegions: finalLayout.scrollRegions,
            runtime: runtime
        )
    }

    @MainActor
    public func semanticSnapshot<V: View>(_ root: V, size: _Size) -> SemanticSnapshot {
        let runtime = self
        var node: _VNode?
        var pass = 0
        repeat {
            pass += 1
            runtime._prepareRuntimeRegistriesForFrame()
            runtime._beginFrameBuild(size: size)
            var current = runtime._buildRootNode(root, size: size)
            current = runtime._applyOverlays(to: current)
            runtime._finalizePostBuildState()
            if !runtime.pendingScrollRequests.isEmpty || runtime._containsScrollReaderTarget(current) {
                let firstLayout = _RenderLayout.layout(node: current, size: size)
                if runtime._updateScrollTargets(firstLayout.scrollTargets) {
                    runtime._prepareRuntimeRegistriesForFrame()
                    current = runtime._buildRootNode(root, size: size)
                    current = runtime._applyOverlays(to: current)
                    runtime._finalizePostBuildState()
                    let secondLayout = _RenderLayout.layout(node: current, size: size)
                    runtime._updateScrollTargets(secondLayout.scrollTargets)
                }
            }

            runtime._firePreferenceCallbacks()
            runtime._finishFrameBuild(size: size)
            node = current
        } while runtime._hasPendingSynchronousInvalidation && pass < Self._maxSynchronousRenderPasses

        return SemanticSnapshot(
            root: SemanticLowerer.lower(node!),
            size: size,
            focusedActionID: focusedActionRawID(),
            activeMenu: nil,
            activePicker: nil,
            activeTextField: nil
        )
    }

    private func _containsScrollReaderTarget(_ node: _VNode) -> Bool {
        switch node {
        case .identified(_, let readerScopePath, let child):
            return readerScopePath != nil || _containsScrollReaderTarget(child)
        case .group(let children), .stack(_, _, let children), .zstack(_, let children):
            return children.contains(where: _containsScrollReaderTarget)
        case .style(_, _, let child),
             .textStyled(_, let child),
             .contentShapeRect(_, let child),
             .clip(_, let child),
             .shadow(let child, _, _, _, _),
             .elevated(_, let child),
             .modalOverlay(_, _, _, let child),
             .frame(_, _, _, _, _, _, let child),
             .edgePadding(_, _, _, _, let child),
             .offset(_, _, let child),
             .opacity(_, let child),
             .tapTarget(_, _, let child),
             .hover(_, let child),
             .scrollView(_, _, _, _, _, let child),
             .onDelete(_, _, let child),
             .tagged(_, let child),
             .gestureTarget(_, _, let child),
             .dragSource(_, _, let child),
             .fixedSize(_, _, let child),
             .layoutPriority(_, let child),
             .aspectRatio(_, _, let child),
             .alignmentGuide(_, _, let child),
             .preferenceNode(_, let child):
            return _containsScrollReaderTarget(child)
        case .button(_, _, let label), .toggle(_, _, _, let label):
            return _containsScrollReaderTarget(label)
        case .viewThatFits(_, let children):
            return children.contains(where: _containsScrollReaderTarget)
        case .background(let child, let background):
            return _containsScrollReaderTarget(child) || _containsScrollReaderTarget(background)
        case .overlay(let child, let overlay):
            return _containsScrollReaderTarget(child) || _containsScrollReaderTarget(overlay)
        case .swipeActions(_, _, let actions, let child):
            return _containsScrollReaderTarget(child) || actions.contains(where: _containsScrollReaderTarget)
        default:
            return false
        }
    }
}

extension _UIRuntime {
    func _registerNavStackRoot(path: [Int]) {
        _noteBuildSideEffect()
        navStackRoots.insert(path)
    }

    func _nearestNavStackRoot(from path: [Int]) -> [Int]? {
        guard !navStackRoots.isEmpty else { return nil }
        if navStackRoots.contains(path) { return path }
        if path.isEmpty { return nil }
        for n in stride(from: path.count - 1, through: 0, by: -1) {
            let p = Array(path.prefix(n))
            if navStackRoots.contains(p) { return p }
        }
        return nil
    }

    private func _bestNavRoot(for path: [Int]) -> [Int]? {
        var best: [Int]? = nil
        for root in navStackRoots {
            if _isPrefix(root, of: path) {
                if best == nil || root.count > (best?.count ?? 0) {
                    best = root
                }
            }
        }
        return best
    }

    public func canPopNavigation() -> Bool {
        for root in navStackRoots where _navDepth(stackPath: root) > 0 {
            return true
        }
        return false
    }

    public func popNavigation() {
        let focus = focusedPath ?? []
        let preferred = _bestNavRoot(for: focus) ?? navStackRoots.first
        if let preferred, _navDepth(stackPath: preferred) > 0 {
            _navPop(stackPath: preferred)
            return
        }
        for root in navStackRoots where _navDepth(stackPath: root) > 0 {
            _navPop(stackPath: root)
            return
        }
    }
}

struct _TextEditor {
    let handle: @MainActor (_KeyEvent) -> Void
}

public enum _KeyEvent: Sendable {
    case char(UInt32)
    case backspace
    case delete
    case left
    case right
    case home
    case end
    case killToEnd
}

public struct StyledCell: Hashable, Sendable {
    public var egc: String
    public var fg: Color?
    public var bg: Color?

    public init(egc: String, fg: Color?, bg: Color?) {
        self.egc = egc
        self.fg = fg
        self.bg = bg
    }
}

public struct _ScrollRegion: Sendable {
    public let rect: _Rect
    public let path: [Int]
    public let maxOffsetY: Int
    public let maxOffsetX: Int
    let axis: _Axis

    init(rect: _Rect, path: [Int], maxOffsetY: Int, maxOffsetX: Int = 0, axis: _Axis = .vertical) {
        self.rect = rect
        self.path = path
        self.maxOffsetY = maxOffsetY
        self.maxOffsetX = maxOffsetX
        self.axis = axis
    }
}

struct _ScrollTarget {
    let id: AnyHashable
    let readerScopePath: [Int]?
    let scrollPath: [Int]
    let minY: Int
    let height: Int
    let viewportHeight: Int
    let maxOffsetY: Int
}

public struct DebugSnapshot: Sendable {
    public let size: _Size
    public let lines: [String]
    public let cells: [String]
    public let styledCells: [StyledCell]
    public let focusedRect: _Rect?
    public let shapeRegions: [(_Rect, _ShapeNode)]

    let hitRegions: [_HitRegion]
    let hoverRegions: [(_Rect, _HoverID)]
    let scrollRegions: [_ScrollRegion]
    let runtime: _UIRuntime

    public var text: String { lines.joined(separator: "\n") }

    public func containsHitRegion(at point: _Point) -> Bool {
        hitRegions.contains(where: { $0.rect.contains(point) })
    }

    public func containsHitRegion(x: Int, y: Int) -> Bool {
        containsHitRegion(at: _Point(x: x, y: y))
    }

    // MARK: Display List
    public var renderList: RenderList {
        var cmds: [RenderCommand] = []
        cmds.reserveCapacity(cells.count + shapeRegions.count)

        let w = size.width
        if w > 0, styledCells.count == size.width * size.height {
            for (idx, c) in styledCells.enumerated() where c.egc != " " || c.fg != nil || c.bg != nil {
                let y = idx / w
                let x = idx % w
                cmds.append(.cell(x: x, y: y, egc: c.egc, fg: c.fg, bg: c.bg))
            }
        }
        for (r, s) in shapeRegions {
            cmds.append(.shape(rect: r, shape: s))
        }

        return RenderList(size: size, commands: cmds)
    }

    /// Emulate a mouse click at a coordinate in the last rendered snapshot.
    @MainActor
    public func click(x: Int, y: Int) {
        click(x: x, y: y, count: 1)
    }

    @MainActor
    public func click(x: Int, y: Int, count: Int) {
        let p = _Point(x: x, y: y)
        // Prefer the last-added region (topmost) so overlays like Picker dropdowns win hit-testing.
        guard let hit = hitRegions.last(where: { $0.matches(p, tapCount: count) && $0.dragGestureID == nil })
            ?? hitRegions.last(where: { $0.matches(p, tapCount: count) }) else { return }
        runtime._recordNativeActivationPoint(actionID: hit.actionID.raw, x: Double(x), y: Double(y))
        runtime._invokeAction(hit.actionID)
    }

    @MainActor
    public func drag(from start: _Point, to end: _Point) {
        // Prefer the last-added region (topmost) so overlays and handles win hit-testing.
        guard let hit = hitRegions.last(where: { $0.rect.contains(start) && $0.dragGestureID != nil }),
              let dragGestureID = hit.dragGestureID else { return }
        runtime._invokeDragGesture(
            dragGestureID,
            start: CGPoint(x: start.x, y: start.y),
            current: CGPoint(x: end.x, y: end.y),
            ended: true
        )
        _ = runtime._performDropFallback(at: CGPoint(x: end.x, y: end.y))
    }

    /// Emulate a scroll wheel event at a coordinate in the last rendered snapshot.
    @MainActor
    public func scroll(x: Int, y: Int, deltaY: Int) {
        let p = _Point(x: x, y: y)
        for r in scrollRegions.reversed() where r.rect.contains(p) {
            if r.axis == .horizontal {
                // For horizontal scroll regions, apply deltaY as deltaX
                if runtime._scrollX(path: r.path, deltaX: deltaY, maxOffset: r.maxOffsetX) {
                    return
                }
            } else {
                if runtime._scroll(path: r.path, deltaY: deltaY, maxOffset: r.maxOffsetY) {
                    return
                }
            }
        }
    }

    @MainActor
    public func hover(x: Int, y: Int) {
        let p = _Point(x: x, y: y)
        let id = hoverRegions.last(where: { $0.0.contains(p) })?.1
        runtime.updateHover(id)
    }

    /// Emulate typing into the currently-focused `TextField` (if any).
    @MainActor
    public func type(_ s: String) {
        for scalar in s.unicodeScalars {
            runtime._handleKey(.char(scalar.value))
        }
    }

    @MainActor
    public func backspace() {
        runtime._handleKey(.backspace)
    }
}

public struct RenderList: Sendable {
    public let size: _Size
    public let commands: [RenderCommand]
}

public enum RenderCommand: Sendable {
    case cell(x: Int, y: Int, egc: String, fg: Color?, bg: Color?)
    case shape(rect: _Rect, shape: _ShapeNode)
}

private func _isPrefix(_ prefix: [Int], of path: [Int]) -> Bool {
    guard prefix.count <= path.count else { return false }
    return zip(prefix, path).allSatisfy { $0 == $1 }
}

struct _BuildContext {
    let runtime: _UIRuntime
    var path: [Int]
    var nextChildIndex: Int

    static func withRuntime<T>(_ runtime: _UIRuntime, path: [Int], _ body: () -> T) -> T {
        let env = _UIRuntime._currentEnvironment ?? runtime._baseEnvironment
        return _UIRuntime.$_current.withValue(runtime, operation: {
            _UIRuntime.$_currentPath.withValue(path, operation: {
                _UIRuntime.$_currentEnvironment.withValue(env, operation: body)
            })
        })
    }

    @MainActor
    mutating func buildChild<V: View>(_ view: V) -> _VNode {
        buildChild(view, pathComponent: nil)
    }

    @MainActor
    mutating func buildIdentifiedChild<V: View, ID: Hashable>(_ view: V, id: ID) -> _VNode {
        buildChild(view, pathComponent: Self.stablePathComponent(for: AnyHashable(id)))
    }

    @MainActor
    private mutating func buildChild<V: View>(_ view: V, pathComponent: Int?) -> _VNode {
        let index = nextChildIndex
        nextChildIndex += 1
        let childPath = path + [pathComponent ?? index]
        let childPathKey = runtime._viewPathKey(path: childPath)
        let childTypeID = ObjectIdentifier(V.self)
        let childSignature = runtime._viewSignature(for: view)

        if runtime._canReuseNode(path: childPath, pathKey: childPathKey, typeID: childTypeID, viewSignature: childSignature),
           let cached = runtime._reuseNode(pathKey: childPathKey) {
            if !Self.requiresNativeRepresentableRefresh(cached) {
                return cached
            }
        }

        runtime._beginPathBuild(path: childPath, pathKey: childPathKey)
        var child = _BuildContext(runtime: runtime, path: childPath, nextChildIndex: 0)
        let node = _BuildContext.withRuntime(runtime, path: child.path) {
            _makeNode(view, &child)
        }
        runtime._endPathBuild(typeID: childTypeID, viewSignature: childSignature, node: node)
        return node
    }

    private static func stablePathComponent(for id: AnyHashable) -> Int {
        let raw = String(reflecting: id.base)
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return -1 - Int(hash & 0x3FFF_FFFF)
    }

    private static func requiresNativeRepresentableRefresh(_ node: _VNode) -> Bool {
        switch node {
        case .image(let name):
            return name.hasPrefix("omni-webview:")
        case .group(let children), .stack(_, _, let children), .flowLayout(_, _, let children), .zstack(_, let children), .viewThatFits(_, let children):
            return children.contains(where: requiresNativeRepresentableRefresh)
        case .style(_, _, let child),
             .textStyled(_, let child),
             .contentShapeRect(_, let child),
             .clip(_, let child),
             .shadow(let child, _, _, _, _),
             .glass(_, _, let child),
             .crt(_, let child),
             .elevated(_, let child),
             .modalOverlay(_, _, _, let child),
             .frame(_, _, _, _, _, _, let child),
             .edgePadding(_, _, _, _, let child),
             .offset(_, _, let child),
             .opacity(_, let child),
             .button(_, _, let child),
             .tapTarget(_, _, let child),
             .hover(_, let child),
             .toggle(_, _, _, let child),
             .scrollView(_, _, _, _, _, let child),
             .identified(_, _, let child),
             .onDelete(_, _, let child),
             .tagged(_, let child),
             .gestureTarget(_, _, let child),
             .dragSource(_, _, let child),
             .contextMenu(_, let child),
             .fixedSize(_, _, let child),
             .layoutPriority(_, let child),
             .aspectRatio(_, _, let child),
             .alignmentGuide(_, _, let child),
             .preferenceNode(_, let child),
             .rotationEffect(_, let child),
             .textCase(_, let child),
             .blur(_, let child),
             .badge(_, let child),
             .anchorPreference(_, _, _, let child),
             .geometryReaderProxy(_, let child):
            return requiresNativeRepresentableRefresh(child)
        case .background(let child, let background), .overlay(let child, let background):
            return requiresNativeRepresentableRefresh(child) || requiresNativeRepresentableRefresh(background)
        case .swipeActions(_, _, let actions, let child):
            return requiresNativeRepresentableRefresh(child) || actions.contains(where: requiresNativeRepresentableRefresh)
        case .empty, .text, .spacer, .gradient, .shape, .textField, .menu, .divider, .styledText, .truncatedText:
            return false
        }
    }
}

private func _omniRuntimeReceiveTraceEnabled() -> Bool {
    guard let raw = getenv("OMNIKIT_RECEIVE_TRACE"),
          let value = String(validatingCString: raw) else {
        return false
    }
    return !value.isEmpty && value != "0" && value.lowercased() != "false"
}
