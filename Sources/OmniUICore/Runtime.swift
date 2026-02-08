public final class _UIRuntime: @unchecked Sendable {
    /// Build-time ambient runtime. Set by `_BuildContext.withRuntime`.
    @TaskLocal static var _current: _UIRuntime?

    /// A traversal path to disambiguate state keys for repeated view instances.
    @TaskLocal static var _currentPath: [Int]?

    /// Build-time ambient environment values.
    @TaskLocal static var _currentEnvironment: EnvironmentValues?

    private var nextActionID: Int = 1
    private var actions: [_ActionID: (path: [Int], action: () -> Void)] = [:]

    private var state: [String: Any] = [:]

    private var focusedPath: [Int]? = nil
    private var textEditors: [[Int]: _TextEditor] = [:]
    private var textEditorCursors: [[Int]: Int] = [:]
    private var focusOrder: [[Int]] = []
    private var focusActivation: [[Int]: _ActionID] = [:]
    private var focusBoolBindings: [[Int]: (Bool) -> Void] = [:]

    private var expandedPickerPath: [Int]? = nil
    private var scrollOffsets: [String: Int] = [:]

    private var navStacks: [String: [AnyView]] = [:]
    private var navStackRoots: Set<[Int]> = []

    private struct _OverlayEntry {
        var view: AnyView
        var dismiss: () -> Void
    }
    private var overlays: [_OverlayEntry] = []

    // Base environment at the root render call.
    var _baseEnvironment: EnvironmentValues = EnvironmentValues()

    public init() {}

    private func _pathKey(prefix: String, path: [Int]) -> String {
        let p = path.map(String.init).joined(separator: ".")
        return "\(prefix):\(p)"
    }

    func _getScrollOffset(path: [Int]) -> Int {
        scrollOffsets[_pathKey(prefix: "scroll", path: path)] ?? 0
    }

    func _setScrollOffset(path: [Int], offset: Int) {
        scrollOffsets[_pathKey(prefix: "scroll", path: path)] = max(0, offset)
    }

    func _scroll(path: [Int], deltaY: Int, maxOffset: Int) {
        let key = _pathKey(prefix: "scroll", path: path)
        let current = scrollOffsets[key] ?? 0
        scrollOffsets[key] = min(max(0, current + deltaY), max(0, maxOffset))
    }

    func _navKey(stackPath: [Int]) -> String {
        _pathKey(prefix: "nav", path: stackPath)
    }

    func _navPush(stackPath: [Int], view: AnyView) {
        let key = _navKey(stackPath: stackPath)
        var s = navStacks[key] ?? []
        s.append(view)
        navStacks[key] = s
    }

    func _navPop(stackPath: [Int]) {
        let key = _navKey(stackPath: stackPath)
        guard var s = navStacks[key], !s.isEmpty else { return }
        _ = s.popLast()
        navStacks[key] = s
    }

    func _navTop(stackPath: [Int]) -> AnyView? {
        let key = _navKey(stackPath: stackPath)
        return navStacks[key]?.last
    }

    func _navDepth(stackPath: [Int]) -> Int {
        let key = _navKey(stackPath: stackPath)
        return navStacks[key]?.count ?? 0
    }

    func _registerAction(_ action: @escaping () -> Void, path: [Int]) -> _ActionID {
        let id = _ActionID(raw: nextActionID)
        nextActionID += 1
        actions[id] = (path: path, action: action)
        return id
    }

    func _invokeAction(_ id: _ActionID) {
        guard let entry = actions[id] else { return }
        _BuildContext.withRuntime(self, path: entry.path) {
            entry.action()
        }
    }

    func _setFocus(path: [Int]?) {
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
    }

    func _isFocused(path: [Int]) -> Bool {
        focusedPath == path
    }

    func _registerTextEditor(path: [Int], _ editor: _TextEditor) {
        textEditors[path] = editor
    }

    func _registerFocusable(path: [Int], activate: _ActionID) {
        focusOrder.append(path)
        focusActivation[path] = activate
    }

    func _isPickerExpanded(path: [Int]) -> Bool {
        expandedPickerPath == path
    }

    func _openPicker(path: [Int]) {
        expandedPickerPath = path
    }

    func _closePicker(path: [Int]) {
        if expandedPickerPath == path {
            expandedPickerPath = nil
        }
    }

    public func hasExpandedPicker() -> Bool {
        expandedPickerPath != nil
    }

    public func collapseExpandedPicker() {
        expandedPickerPath = nil
    }

    public func focusNextWithinExpandedPicker() {
        guard let expanded = expandedPickerPath else {
            focusNext()
            return
        }
        let candidates = focusOrder.filter { _isPrefix(expanded, of: $0) }
        guard !candidates.isEmpty else { return }
        if let f = focusedPath, let idx = candidates.firstIndex(of: f) {
            focusedPath = candidates[(idx + 1) % candidates.count]
        } else {
            focusedPath = candidates[0]
        }
    }

    public func focusPrevWithinExpandedPicker() {
        guard let expanded = expandedPickerPath else {
            focusPrev()
            return
        }
        let candidates = focusOrder.filter { _isPrefix(expanded, of: $0) }
        guard !candidates.isEmpty else { return }
        if let f = focusedPath, let idx = candidates.firstIndex(of: f) {
            focusedPath = candidates[(idx - 1 + candidates.count) % candidates.count]
        } else {
            focusedPath = candidates[0]
        }
    }

    public func _handleKeyPress(_ codepoint: UInt32) {
        _handleKey(.char(codepoint))
    }

    public func _handleKey(_ ev: _KeyEvent) {
        // When a picker is expanded, it owns the keyboard.
        if expandedPickerPath != nil { return }
        guard let p = focusedPath, let editor = textEditors[p] else { return }
        editor.handle(ev)
    }

    func _getTextCursor(path: [Int]) -> Int {
        textEditorCursors[path] ?? 0
    }

    func _setTextCursor(path: [Int], _ v: Int) {
        textEditorCursors[path] = max(0, v)
    }

    func _ensureTextCursorAtEndIfUnset(path: [Int], text: String) {
        if textEditorCursors[path] == nil {
            textEditorCursors[path] = text.unicodeScalars.count
        }
    }

    public func isTextEditingFocused() -> Bool {
        guard let p = focusedPath else { return false }
        return textEditors[p] != nil
    }

    public func focusNext() {
        guard !focusOrder.isEmpty else { return }
        expandedPickerPath = nil
        if let f = focusedPath, let idx = focusOrder.firstIndex(of: f) {
            focusedPath = focusOrder[(idx + 1) % focusOrder.count]
        } else {
            focusedPath = focusOrder[0]
        }
    }

    public func focusPrev() {
        guard !focusOrder.isEmpty else { return }
        expandedPickerPath = nil
        if let f = focusedPath, let idx = focusOrder.firstIndex(of: f) {
            focusedPath = focusOrder[(idx - 1 + focusOrder.count) % focusOrder.count]
        } else {
            focusedPath = focusOrder[0]
        }
    }

    public func activateFocused() {
        guard let f = focusedPath, let id = focusActivation[f] else { return }
        _invokeAction(id)
    }

    public func focusedActionRawID() -> Int? {
        guard let f = focusedPath, let id = focusActivation[f] else { return nil }
        return id.raw
    }

    func _getState<Value>(seed: _StateSeed, path: [Int], initial: () -> Value) -> Value {
        let key = _stateKey(seed: seed, path: path)
        if let existing = state[key] as? Value {
            return existing
        }
        let v = initial()
        state[key] = v
        return v
    }

    func _setState<Value>(seed: _StateSeed, path: [Int], value: Value) {
        let key = _stateKey(seed: seed, path: path)
        state[key] = value
    }

    private func _stateKey(seed: _StateSeed, path: [Int]) -> String {
        // Keep this deterministic and stable across processes (avoid ObjectIdentifier / memory addresses).
        let p = path.map(String.init).joined(separator: ".")
        return "\(seed.fileID):\(seed.line):\(p)"
    }

    public func debugRender<V: View>(_ root: V, size: _Size, renderShapeGlyphs: Bool = true) -> DebugSnapshot {
        let runtime = self
        // Rebuild-only registries (actions/editors) should not accumulate across frames.
        runtime.nextActionID = 1
        runtime.actions.removeAll(keepingCapacity: true)
        runtime.textEditors.removeAll(keepingCapacity: true)
        runtime.focusOrder.removeAll(keepingCapacity: true)
        runtime.focusActivation.removeAll(keepingCapacity: true)
        runtime.focusBoolBindings.removeAll(keepingCapacity: true)
        runtime.navStackRoots.removeAll(keepingCapacity: true)
        runtime.overlays.removeAll(keepingCapacity: true)

        let ctx = _BuildContext(runtime: runtime, path: [], nextChildIndex: 0)
        var node = _BuildContext.withRuntime(runtime, path: []) {
            var local = ctx
            return _makeNode(root, &local)
        }

        if !runtime.overlays.isEmpty {
            // Overlays are always above the root.
            var local = ctx
            let overlayNodes: [_VNode] = runtime.overlays.map { entry in
                let current = _UIRuntime._currentEnvironment ?? runtime._baseEnvironment
                var next = current
                next.dismiss = DismissAction(entry.dismiss)
                next.presentationMode = PresentationMode(dismiss: entry.dismiss)
                return _UIRuntime.$_currentEnvironment.withValue(next) {
                    local.buildChild(entry.view)
                }
            }
            node = .zstack(children: [node] + overlayNodes)
        }

        // If nothing is focused yet, default focus to the first focusable control.
        // This prevents "no focus highlight until interaction" and makes keyboard UX predictable.
        if runtime.focusedPath == nil, let first = runtime.focusOrder.first {
            runtime._setFocus(path: first)
        }

        let laidOut = _DebugLayout.layout(
            node: node,
            in: _Rect(origin: _Point(x: 0, y: 0), size: size),
            renderShapeGlyphs: renderShapeGlyphs
        )
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
            scrollRegions: laidOut.scrollRegions,
            runtime: runtime
        )
    }
}

extension _UIRuntime {
    func _registerOverlay(view: AnyView, dismiss: @escaping () -> Void) {
        overlays.append(_OverlayEntry(view: view, dismiss: dismiss))
    }

    func _registerFocusBoolBinding(path: [Int], set: @escaping (Bool) -> Void) {
        focusBoolBindings[path] = set
    }
}

extension _UIRuntime {
    public func render<V: View>(_ root: V, size: _Size) -> RenderSnapshot {
        let runtime = self

        runtime.nextActionID = 1
        runtime.actions.removeAll(keepingCapacity: true)
        runtime.textEditors.removeAll(keepingCapacity: true)
        runtime.focusOrder.removeAll(keepingCapacity: true)
        runtime.focusActivation.removeAll(keepingCapacity: true)
        runtime.focusBoolBindings.removeAll(keepingCapacity: true)
        runtime.navStackRoots.removeAll(keepingCapacity: true)
        runtime.overlays.removeAll(keepingCapacity: true)

        let ctx = _BuildContext(runtime: runtime, path: [], nextChildIndex: 0)
        var node = _BuildContext.withRuntime(runtime, path: []) {
            var local = ctx
            return _makeNode(root, &local)
        }

        if !runtime.overlays.isEmpty {
            var local = ctx
            let overlayNodes: [_VNode] = runtime.overlays.map { entry in
                let current = _UIRuntime._currentEnvironment ?? runtime._baseEnvironment
                var next = current
                next.dismiss = DismissAction(entry.dismiss)
                next.presentationMode = PresentationMode(dismiss: entry.dismiss)
                return _UIRuntime.$_currentEnvironment.withValue(next) {
                    local.buildChild(entry.view)
                }
            }
            node = .zstack(children: [node] + overlayNodes)
        }

        if runtime.focusedPath == nil, let first = runtime.focusOrder.first {
            runtime._setFocus(path: first)
        }

        let laidOut = _RenderLayout.layout(node: node, size: size)
        let focusedRect: _Rect? = {
            guard let raw = focusedActionRawID() else { return nil }
            return laidOut.hitRegions.last(where: { $0.1.raw == raw })?.0
        }()
        return RenderSnapshot(
            size: size,
            ops: laidOut.ops,
            focusedRect: focusedRect,
            shapeRegions: laidOut.shapeRegions,
            hitRegions: laidOut.hitRegions,
            scrollRegions: laidOut.scrollRegions,
            runtime: runtime
        )
    }
}

extension _UIRuntime {
    func _registerNavStackRoot(path: [Int]) {
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

struct _ScrollRegion: Sendable {
    let rect: _Rect
    let path: [Int]
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
    let scrollRegions: [_ScrollRegion]
    let runtime: _UIRuntime

    public var text: String { lines.joined(separator: "\n") }

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
        guard let r = scrollRegions.last(where: { $0.rect.contains(p) }) else { return }
        runtime._scroll(path: r.path, deltaY: deltaY, maxOffset: r.maxOffsetY)
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
        let index = nextChildIndex
        nextChildIndex += 1

        var child = _BuildContext(runtime: runtime, path: path + [index], nextChildIndex: 0)
        return _BuildContext.withRuntime(runtime, path: child.path) {
            _makeNode(view, &child)
        }
    }
}
