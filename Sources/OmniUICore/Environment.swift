// Minimal SwiftUI-like environment system.
//
// This is intentionally small: enough for `@Environment`, `@EnvironmentObject`,
// and `.environmentObject(_)` to compile and work in our debug/notcurses renderers
// without relying on Combine or Apple-only frameworks.

import Foundation

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct EnvironmentValues: @unchecked Sendable {
    private var storage: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value {
        get { (storage[ObjectIdentifier(key)] as? K.Value) ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }

    // EnvironmentObject storage.
    mutating func _setObject<T: AnyObject>(_ value: T, as type: T.Type = T.self) {
        storage[ObjectIdentifier(type)] = value
    }

    func _getObject<T: AnyObject>(_ type: T.Type = T.self) -> T? {
        storage[ObjectIdentifier(type)] as? T
    }
}

@propertyWrapper
public struct Environment<Value> {
    private let keyPath: KeyPath<EnvironmentValues, Value>

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        let env = _UIRuntime._currentEnvironment ?? EnvironmentValues()
        return env[keyPath: keyPath]
    }
}

public enum ColorScheme: Sendable {
    case light
    case dark
}

public struct DismissAction: @unchecked Sendable {
    let _action: () -> Void
    public init(_ action: @escaping () -> Void = {}) { self._action = action }
    public func callAsFunction() { _action() }
}

public struct PresentationMode: @unchecked Sendable {
    let _dismiss: () -> Void
    public init(dismiss: @escaping () -> Void = {}) { self._dismiss = dismiss }
    public mutating func dismiss() { _dismiss() }
}

public struct OpenURLAction: @unchecked Sendable {
    public enum Result: Sendable {
        case handled
        case discarded
        case systemAction
    }

    let _open: (URL) -> Result
    public init(_ open: @escaping (URL) -> Result = { _ in .systemAction }) {
        self._open = open
    }

    @discardableResult
    public func callAsFunction(_ url: URL) -> Result {
        _open(url)
    }
}

private enum _ColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .dark
}

private enum _DismissKey: EnvironmentKey {
    static let defaultValue: DismissAction = DismissAction()
}

private enum _PresentationModeKey: EnvironmentKey {
    static let defaultValue: Binding<PresentationMode> = Binding(get: { PresentationMode() }, set: { _ in })
}

private enum _ModelContextKey: EnvironmentKey {
    static let defaultValue: ModelContext = ModelContext()
}

private enum _OpenURLKey: EnvironmentKey {
    static let defaultValue: OpenURLAction = OpenURLAction()
}

public enum _FormStyleKind: Hashable, Sendable {
    case automatic
    case grouped
}

private enum _TintColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

private enum _FormStyleKey: EnvironmentKey {
    static let defaultValue: _FormStyleKind = .automatic
}

private enum _NavigationTitleKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

public extension EnvironmentValues {
    var colorScheme: ColorScheme {
        get { self[_ColorSchemeKey.self] }
        set { self[_ColorSchemeKey.self] = newValue }
    }

    var dismiss: DismissAction {
        get { self[_DismissKey.self] }
        set { self[_DismissKey.self] = newValue }
    }

    var presentationMode: Binding<PresentationMode> {
        get { self[_PresentationModeKey.self] }
        set { self[_PresentationModeKey.self] = newValue }
    }

    var modelContext: ModelContext {
        get { self[_ModelContextKey.self] }
        set { self[_ModelContextKey.self] = newValue }
    }

    var openURL: OpenURLAction {
        get { self[_OpenURLKey.self] }
        set { self[_OpenURLKey.self] = newValue }
    }

    var tint: Color? {
        get { self[_TintColorKey.self] }
        set { self[_TintColorKey.self] = newValue }
    }

    var formStyleKind: _FormStyleKind {
        get { self[_FormStyleKey.self] }
        set { self[_FormStyleKey.self] = newValue }
    }

    var navigationTitle: String? {
        get { self[_NavigationTitleKey.self] }
        set { self[_NavigationTitleKey.self] = newValue }
    }
}

public extension View {
    func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        _EnvironmentValueProvider(content: AnyView(self), keyPath: keyPath, value: value)
    }

    func environmentObject<T: AnyObject>(_ object: T) -> some View {
        _EnvironmentObjectProvider(object: object, content: AnyView(self))
    }

    func onOpenURL(perform action: @escaping (URL) -> Void) -> some View {
        environment(\.openURL, OpenURLAction({ url in action(url); return .handled }))
    }
}

struct _EnvironmentValueProvider<V>: View, _PrimitiveView {
    public typealias Body = Never

    let content: AnyView
    let keyPath: WritableKeyPath<EnvironmentValues, V>
    let value: V

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let current = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment
        var next = current
        next[keyPath: keyPath] = value
        return _UIRuntime.$_currentEnvironment.withValue(next) {
            ctx.buildChild(content)
        }
    }
}

struct _EnvironmentObjectProvider<T: AnyObject>: View, _PrimitiveView {
    public typealias Body = Never
    let object: T
    let content: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let current = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment
        var next = current
        next._setObject(object)
        return _UIRuntime.$_currentEnvironment.withValue(next) {
            ctx.buildChild(content)
        }
    }
}
