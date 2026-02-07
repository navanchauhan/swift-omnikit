public final class _UIRuntime: @unchecked Sendable {
    /// Build-time ambient runtime. Set by `_BuildContext.withRuntime`.
    @TaskLocal static var _current: _UIRuntime?

    /// A traversal path to disambiguate state keys for repeated view instances.
    @TaskLocal static var _currentPath: [Int]?

    private var nextActionID: Int = 1
    private var actions: [_ActionID: (path: [Int], action: () -> Void)] = [:]

    private var state: [String: Any] = [:]

    private var focusedPath: [Int]? = nil
    private var textEditors: [[Int]: _TextEditor] = [:]
    private var focusOrder: [[Int]] = []
    private var focusActivation: [[Int]: _ActionID] = [:]

    private var expandedPickerPath: [Int]? = nil

    public init() {}

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
        // When a picker is expanded, it owns the keyboard.
        if expandedPickerPath != nil { return }
        guard let p = focusedPath, let editor = textEditors[p] else { return }
        editor.handle(codepoint)
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

    public func debugRender<V: View>(_ root: V, size: _Size) -> DebugSnapshot {
        let runtime = self
        // Rebuild-only registries (actions/editors) should not accumulate across frames.
        runtime.nextActionID = 1
        runtime.actions.removeAll(keepingCapacity: true)
        runtime.textEditors.removeAll(keepingCapacity: true)
        runtime.focusOrder.removeAll(keepingCapacity: true)
        runtime.focusActivation.removeAll(keepingCapacity: true)

        let ctx = _BuildContext(runtime: runtime, path: [], nextChildIndex: 0)
        let node = _BuildContext.withRuntime(runtime, path: []) {
            var local = ctx
            return _makeNode(root, &local)
        }

        let laidOut = _DebugLayout.layout(node: node, in: _Rect(origin: _Point(x: 0, y: 0), size: size))
        return DebugSnapshot(size: size, lines: laidOut.lines, hitRegions: laidOut.hitRegions, runtime: runtime)
    }
}

struct _TextEditor {
    let handle: (UInt32) -> Void
}

public struct DebugSnapshot: Sendable {
    public let size: _Size
    public let lines: [String]

    let hitRegions: [(_Rect, _ActionID)]
    let runtime: _UIRuntime

    public var text: String { lines.joined(separator: "\n") }

    /// Emulate a mouse click at a coordinate in the last rendered snapshot.
    public func click(x: Int, y: Int) {
        let p = _Point(x: x, y: y)
        guard let (_, id) = hitRegions.first(where: { $0.0.contains(p) }) else { return }
        runtime._invokeAction(id)
    }

    /// Emulate typing into the currently-focused `TextField` (if any).
    public func type(_ s: String) {
        for scalar in s.unicodeScalars {
            runtime._handleKeyPress(scalar.value)
        }
    }

    public func backspace() {
        runtime._handleKeyPress(8)
    }
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
        _UIRuntime.$_current.withValue(runtime, operation: {
            _UIRuntime.$_currentPath.withValue(path, operation: body)
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
