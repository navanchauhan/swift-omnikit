public extension View {
    func font(_ font: Font?) -> some View { _Passthrough(self) }
    func foregroundStyle(_ color: Color) -> some View { _Passthrough(self) }
    func foregroundColor(_ color: Color) -> some View { _Passthrough(self) }
    func multilineTextAlignment(_ alignment: TextAlignment) -> some View { _Passthrough(self) }
    func lineLimit(_ limit: Int?) -> some View { _Passthrough(self) }
    func cornerRadius(_ radius: CGFloat) -> some View { _Passthrough(self) }
    func shadow(color: Color, radius: CGFloat) -> some View { _Passthrough(self) }
    func opacity(_ value: CGFloat) -> some View { _Passthrough(self) }
    func ignoresSafeArea() -> some View { _Passthrough(self) }
    func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View { _Passthrough(self) }
    func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View { _Passthrough(self) }
    func mask<M: View>(_ mask: M) -> some View { _Passthrough(self) }

    func background<B: View>(_ background: B) -> some View { _Passthrough(self) }
    func overlay<O: View>(_ overlay: O) -> some View { _Passthrough(self) }

    // MARK: SwiftUI API Surface (stubs/passthrough)
    func navigationTitle(_ title: String) -> some View { _Passthrough(self) }
    func navigationTitle(_ title: Text) -> some View { _Passthrough(self) }

    func listStyle<S>(_ style: S) -> some View { _Passthrough(self) }
    func pickerStyle<S>(_ style: S) -> some View { _Passthrough(self) }
    func buttonStyle<S>(_ style: S) -> some View { _Passthrough(self) }
    func textFieldStyle<S>(_ style: S) -> some View { _Passthrough(self) }
    func toggleStyle<S>(_ style: S) -> some View { _Passthrough(self) }

    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> some View { _Passthrough(self) }
    func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View { _Passthrough(self) }
    func help(_ text: String) -> some View { _Passthrough(self) }

    func sheet<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View { _Passthrough(self) }
    func sheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)?, @ViewBuilder content: () -> Content) -> some View { _Passthrough(self) }
    func alert(isPresented: Binding<Bool>, @ViewBuilder content: () -> some View) -> some View { _Passthrough(self) }

    func focused(_ isFocused: Binding<Bool>) -> some View { _Passthrough(self) }

    func onChange<V: Equatable>(of value: V, perform action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View {
        _OnChange(content: AnyView(self), value: value, action: action)
    }

    func frame(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        _Passthrough(self)
    }

    func frame(
        minWidth: CGFloat? = nil,
        idealWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        idealHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        _Passthrough(self)
    }

    func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        // Only `Int` padding is currently implemented in the debug layout; keep API compatibility.
        if let length {
            return AnyView(Padding(amount: Int(length), content: AnyView(self)))
        }
        return AnyView(Padding(amount: 1, content: AnyView(self)))
    }

    func onAppear(perform action: @escaping () -> Void) -> some View {
        _OnAppear(content: AnyView(self), action: action)
    }
}

// MARK: Stubs for SwiftUI style/shortcut types
public struct PlainListStyle: Hashable, Sendable { public init() {} }
public struct RoundedBorderTextFieldStyle: Hashable, Sendable { public init() {} }
public struct PlainButtonStyle: Hashable, Sendable { public init() {} }
public struct PrimaryFillButtonStyle: Hashable, Sendable { public init() {} }

public struct KeyboardShortcut: Hashable, Sendable {
    public var key: KeyEquivalent
    public var modifiers: EventModifiers
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let cancelAction = KeyboardShortcut(.escape)
    public static let defaultAction = KeyboardShortcut(.return)
}

public struct KeyEquivalent: Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(stringLiteral value: StringLiteralType) { self.rawValue = value }

    public static let escape: KeyEquivalent = "\u{001B}"
    public static let `return`: KeyEquivalent = "\n"
}

public struct EventModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = EventModifiers(rawValue: 1 << 0)
    public static let shift = EventModifiers(rawValue: 1 << 1)
    public static let option = EventModifiers(rawValue: 1 << 2)
    public static let control = EventModifiers(rawValue: 1 << 3)
}

/// Used for API compatibility: modifiers that we don't yet model in the node tree.
public struct _Passthrough<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let content: Content

    public init(_ content: Content) { self.content = content }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.buildChild(content)
    }
}

public struct _OnAppear: View, _PrimitiveView {
    public typealias Body = Never

    let content: AnyView
    let action: () -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // Extremely small behavior: fire on every render for now.
        // TODO: fire once per identity path.
        action()
        return ctx.buildChild(content)
    }
}

public struct _OnChange<V: Equatable>: View, _PrimitiveView {
    public typealias Body = Never

    let content: AnyView
    let value: V
    let action: (_ oldValue: V, _ newValue: V) -> Void

    @State private var last: V? = nil

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        if let prev = last, prev != value {
            action(prev, value)
        }
        last = value
        return ctx.buildChild(content)
    }
}
