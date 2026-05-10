import Foundation

// Safety: OmniUI runtime state is confined to a single render/event loop owner.
// We intentionally do not use `@MainActor` here because notcurses/terminal renderers
// may drive the runtime off the process main actor, but they still preserve
// single-threaded ownership for mutation.
public final class _UIRuntime: @unchecked Sendable {
    private static let _overlayPathSentinel = Int.min

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

    private var focusedPath: [Int]? = nil
    private var textEditors: [[Int]: _TextEditor] = [:]
    private var textEditorCursors: [[Int]: Int] = [:]
    private var focusOrder: [[Int]] = []
    private var focusPriorities: [[Int]: Int] = [:]
    private var focusActivation: [[Int]: _ActionID] = [:]
    private var focusBoolBindings: [[Int]: (Bool) -> Void] = [:]
    private var submitHandlers: [[Int]: (path: [Int], env: EnvironmentValues, action: () -> Void)] = [:]
    private var nextHoverID: Int = 1
    private var hoverHandlers: [_HoverID: (path: [Int], env: EnvironmentValues, action: (Bool) -> Void)] = [:]
    private var activeHoverID: _HoverID? = nil
    private var exitCommand: (path: [Int], env: EnvironmentValues, action: () -> Void)? = nil
    private var keyboardShortcuts: [KeyboardShortcut: _ActionID] = [:]

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
    private var nextLaunchedAsyncActionID: Int = 1
    private var launchedAsyncActions: [Int: _TaskEntry] = [:]

    private var expandedPickerPath: [Int]? = nil
    private var scrollOffsets: [String: Int] = [:]
    private var scrollTargets: [_ScrollTarget] = []
    private var pendingScrollRequests: [_PendingScrollRequest] = []
    private var globalEditMode: EditMode = .inactive
    private var lastHitRegions: [(_Rect, _ActionID)] = []
    private var lastScrollRegions: [_ScrollRegion] = []

    private struct _NavEntry {
        var view: AnyView
        var ownerKey: String?
        var onPop: (() -> Void)?
    }
    private typealias _NavResolver = (AnyHashable) -> AnyView
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

    /// Deliver a URL to the top-level `onOpenURL` handler registered in the environment.
    public func deliverURL(_ url: URL) {
        let env = _UIRuntime._currentEnvironment ?? _baseEnvironment
        let result = env.openURL(url)
        _ = result
        _markDirty()
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
        navStackRoots.removeAll(keepingCapacity: true)
        navResolvers.removeAll(keepingCapacity: true)
        overlays.removeAll(keepingCapacity: true)
        _withTaskRegistryLock {
            tasksSeenThisFrame.removeAll(keepingCapacity: true)
        }
        onAppearSeenThisFrame.removeAll(keepingCapacity: true)
        onDisappearSeenThisFrame.removeAll(keepingCapacity: true)
    }

    private func _buildRootNode<V: View>(_ root: V, size: _Size) -> _VNode {
        let runtime = self
        let ctx = _BuildContext(runtime: runtime, path: [], nextChildIndex: 0)
        let rootPath: [Int] = []
        let rootPathKey = _viewPathKey(path: rootPath)
        let rootTypeID = ObjectIdentifier(V.self)
        let rootSignature = _viewSignature(for: root)

        _beginPathBuild(path: rootPath, pathKey: rootPathKey)
        let node = _UIRuntime.$_currentRenderSize.withValue(size) {
            _BuildContext.withRuntime(runtime, path: rootPath) {
                var local = ctx
                return _makeNode(root, &local)
            }
        }
        _endPathBuild(typeID: rootTypeID, viewSignature: rootSignature, node: node)
        return node
    }

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
            merged = .zstack(children: [merged, .elevated(zOffset: 1000, child: overlayNode)])
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
        if !_hasRenderedAtLeastOnce { return true }
        if _lastRenderedSize != size { return true }
        if _pendingDirtyEverything { return true }
        if !_activeAnimations.isEmpty { return true }
        return !_pendingDirtyPaths.isEmpty
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
        hitRegions: [(_Rect, _ActionID)],
        scrollRegions: [_ScrollRegion]
    ) {
        lastHitRegions = hitRegions
        lastScrollRegions = scrollRegions
    }

    private func _ensureFocusedControlVisible(path: [Int]) {
        guard let focusedID = focusActivation[path] else { return }
        guard let focusedRect = lastHitRegions.last(where: { $0.1 == focusedID })?.0 else { return }
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

    func _registerNavDestinationResolver<Value: Hashable>(stackPath: [Int], valueType: Value.Type, destination: @escaping (Value) -> AnyView) {
        _noteBuildSideEffect()
        let key = _navKey(stackPath: stackPath)
        var resolvers = navResolvers[key] ?? [:]
        resolvers[ObjectIdentifier(valueType)] = { any in
            guard let typed = any.base as? Value else { return AnyView(EmptyView()) }
            return destination(typed)
        }
        navResolvers[key] = resolvers
    }

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
        _UIRuntime.$_currentEnvironment.withValue(entry.env) {
            _BuildContext.withRuntime(self, path: entry.path) {
                entry.action()
            }
        }
        // Actions typically mutate state (ObservableObject properties, navigation, etc.).
        // Mark the action's owning subtree dirty so the change is reflected on the next frame.
        _markDirty(path: entry.path)
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

    public func handleNativeKeyForRawActionID(_ rawID: Int, keyKind: Int, codepoint: UInt32) {
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
        _invokeAction(id)
        guard let path = _textEditorPath(forNativeActionID: id) else { return }

        switch keyKind {
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

    public func _handleKeyPress(_ codepoint: UInt32) {
        _handleKey(.char(codepoint))
    }

    public func _handleKey(_ ev: _KeyEvent) {
        // When a picker is expanded, it owns the keyboard.
        if expandedPickerPath != nil { return }
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
        keyboardShortcuts[shortcut] = id
    }

    @discardableResult
    public func invokeKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> Bool {
        func lookup(_ mods: EventModifiers) -> _ActionID? {
            keyboardShortcuts[KeyboardShortcut(key, modifiers: mods)]
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
        let t = Task(priority: p) { @MainActor in
            await runtime._runTask(key: key)
        }
        let inserted = _withTaskRegistryLock {
            if tasks[key] != nil { return false }
            tasks[key] = _TaskEntry(env: env, path: path, action: action, task: t)
            return true
        }
        if !inserted {
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
        let t = Task(priority: p) { @MainActor in
            await runtime._runTask(key: key)
        }
        let inserted = _withTaskRegistryLock {
            guard taskLastIds[key] == id else { return false }
            tasks[key] = _TaskEntry(env: env, path: path, action: action, task: t)
            return true
        }
        if !inserted {
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
        state[key] = value
        _markDirtyForState(stateKey: key, ownerPath: path)
    }

    func _setState<Value: Equatable>(seed: _StateSeed, path: [Int], value: Value) {
        let key = _stateKey(seed: seed, path: path)
        if let existing = state[key] as? Value, existing == value {
            return
        }
        state[key] = value
        _markDirtyForState(stateKey: key, ownerPath: path)
    }

    private func _stateKey(seed: _StateSeed, path: [Int]) -> String {
        // Keep this deterministic and stable across processes (avoid ObjectIdentifier / memory addresses).
        let p = path.map(String.init).joined(separator: ".")
        return "\(seed.fileID):\(seed.line):\(p)"
    }

    public func debugRender<V: View>(_ root: V, size: _Size, renderShapeGlyphs: Bool = true) -> DebugSnapshot {
        let runtime = self
        runtime._prepareRuntimeRegistriesForFrame()
        runtime._beginFrameBuild(size: size)
        var node = runtime._buildRootNode(root, size: size)
        node = runtime._applyOverlays(to: node)
        runtime._finalizePostBuildState()

        let laidOut = _DebugLayout.layout(
            node: node,
            in: _Rect(origin: _Point(x: 0, y: 0), size: size),
            renderShapeGlyphs: renderShapeGlyphs
        )
        runtime._updateScrollTargets(laidOut.scrollTargets)
        runtime._updateLastInteractionRegions(
            hitRegions: laidOut.hitRegions,
            scrollRegions: laidOut.scrollRegions
        )
        runtime._firePreferenceCallbacks()
        runtime._finishFrameBuild(size: size)
        let focusedRect: _Rect? = {
            guard let raw = focusedActionRawID() else { return nil }
            return laidOut.hitRegions.last(where: { $0.1.raw == raw })?.0
        }()
        return DebugSnapshot(
            size: size,
            lines: laidOut.lines,
            cells: laidOut.cells,
            styledCells: laidOut.styledCells,
            focusedRect: focusedRect,
            shapeRegions: laidOut.shapeRegions,
            hitRegions: laidOut.hitRegions,
            hoverRegions: laidOut.hoverRegions,
            scrollRegions: laidOut.scrollRegions,
            runtime: runtime
        )
    }
}

extension _UIRuntime {
    func _markDirtyFromModelContext() {
        _markDirty()
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
    public func render<V: View>(_ root: V, size: _Size) -> RenderSnapshot {
        let runtime = self

        runtime._prepareRuntimeRegistriesForFrame()
        runtime._beginFrameBuild(size: size)
        var node = runtime._buildRootNode(root, size: size)
        node = runtime._applyOverlays(to: node)
        runtime._finalizePostBuildState()

        let laidOut = _RenderLayout.layout(node: node, size: size)
        runtime._updateScrollTargets(laidOut.scrollTargets)
        runtime._updateLastInteractionRegions(
            hitRegions: laidOut.hitRegions,
            scrollRegions: laidOut.scrollRegions
        )
        runtime._firePreferenceCallbacks()
        runtime._finishFrameBuild(size: size)
        let focusedRect: _Rect? = {
            guard let raw = focusedActionRawID() else { return nil }
            return laidOut.hitRegions.last(where: { $0.1.raw == raw })?.0
        }()
        return RenderSnapshot(
            size: size,
            ops: laidOut.ops,
            focusedRect: focusedRect,
            shapeRegions: laidOut.shapeRegions,
            cursorPosition: laidOut.cursorPosition,
            activeMenu: laidOut.activeMenu,
            activePicker: laidOut.activePicker,
            activeTextField: laidOut.activeTextField,
            hitRegions: laidOut.hitRegions,
            hoverRegions: laidOut.hoverRegions,
            scrollRegions: laidOut.scrollRegions,
            runtime: runtime
        )
    }

    public func semanticSnapshot<V: View>(_ root: V, size: _Size) -> SemanticSnapshot {
        let runtime = self

        runtime._prepareRuntimeRegistriesForFrame()
        runtime._beginFrameBuild(size: size)
        var node = runtime._buildRootNode(root, size: size)
        node = runtime._applyOverlays(to: node)
        runtime._finalizePostBuildState()
        if !runtime.pendingScrollRequests.isEmpty || runtime._containsScrollReaderTarget(node) {
            let firstLayout = _RenderLayout.layout(node: node, size: size)
            if runtime._updateScrollTargets(firstLayout.scrollTargets) {
                runtime._prepareRuntimeRegistriesForFrame()
                node = runtime._buildRootNode(root, size: size)
                node = runtime._applyOverlays(to: node)
                runtime._finalizePostBuildState()
                let secondLayout = _RenderLayout.layout(node: node, size: size)
                runtime._updateScrollTargets(secondLayout.scrollTargets)
            }
        }

        runtime._firePreferenceCallbacks()
        runtime._finishFrameBuild(size: size)

        return SemanticSnapshot(
            root: SemanticLowerer.lower(node),
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
        case .group(let children), .stack(_, _, let children), .zstack(let children):
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
             .tapTarget(_, let child),
             .hover(_, let child),
             .scrollView(_, _, _, _, _, let child),
             .onDelete(_, _, let child),
             .tagged(_, let child),
             .gestureTarget(_, let child),
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
    let handle: (_KeyEvent) -> Void
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

    let hitRegions: [(_Rect, _ActionID)]
    let hoverRegions: [(_Rect, _HoverID)]
    let scrollRegions: [_ScrollRegion]
    let runtime: _UIRuntime

    public var text: String { lines.joined(separator: "\n") }

    public func containsHitRegion(at point: _Point) -> Bool {
        hitRegions.contains(where: { $0.0.contains(point) })
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
    public func click(x: Int, y: Int) {
        let p = _Point(x: x, y: y)
        // Prefer the last-added region (topmost) so overlays like Picker dropdowns win hit-testing.
        guard let (_, id) = hitRegions.last(where: { $0.0.contains(p) }) else { return }
        runtime._invokeAction(id)
    }

    /// Emulate a scroll wheel event at a coordinate in the last rendered snapshot.
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

    public func hover(x: Int, y: Int) {
        let p = _Point(x: x, y: y)
        let id = hoverRegions.last(where: { $0.0.contains(p) })?.1
        runtime.updateHover(id)
    }

    /// Emulate typing into the currently-focused `TextField` (if any).
    public func type(_ s: String) {
        for scalar in s.unicodeScalars {
            runtime._handleKey(.char(scalar.value))
        }
    }

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

    mutating func buildChild<V: View>(_ view: V) -> _VNode {
        buildChild(view, pathComponent: nil)
    }

    mutating func buildIdentifiedChild<V: View, ID: Hashable>(_ view: V, id: ID) -> _VNode {
        buildChild(view, pathComponent: Self.stablePathComponent(for: AnyHashable(id)))
    }

    private mutating func buildChild<V: View>(_ view: V, pathComponent: Int?) -> _VNode {
        let index = nextChildIndex
        nextChildIndex += 1
        let childPath = path + [pathComponent ?? index]
        let childPathKey = runtime._viewPathKey(path: childPath)
        let childTypeID = ObjectIdentifier(V.self)
        let childSignature = runtime._viewSignature(for: view)

        if runtime._canReuseNode(path: childPath, pathKey: childPathKey, typeID: childTypeID, viewSignature: childSignature),
           let cached = runtime._reuseNode(pathKey: childPathKey) {
            return cached
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
}
