public extension View {
    func font(_ font: Font?) -> some View { _Passthrough(self) }
    func foregroundStyle(_ color: Color) -> some View { _Style(content: AnyView(self), fg: color, bg: nil) }
    func foregroundColor(_ color: Color) -> some View { _Style(content: AnyView(self), fg: color, bg: nil) }
    func multilineTextAlignment(_ alignment: TextAlignment) -> some View { _Passthrough(self) }
    func lineLimit(_ limit: Int?) -> some View { _Passthrough(self) }
    func cornerRadius(_ radius: CGFloat) -> some View { _Passthrough(self) }
    func shadow(color: Color, radius: CGFloat) -> some View { _Passthrough(self) }
    func shadow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View { _Passthrough(self) }
    func opacity(_ value: CGFloat) -> some View { _Passthrough(self) }
    func ignoresSafeArea() -> some View { _Passthrough(self) }
    func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View { _Passthrough(self) }
    func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View { _Passthrough(self) }
    func mask<M: View>(_ mask: M) -> some View { _Passthrough(self) }

    func background<B: View>(_ background: B) -> some View { _Background(content: AnyView(self), background: AnyView(background)) }
    func background(_ color: Color) -> some View { _Style(content: AnyView(self), fg: nil, bg: color) }
    func background(_ material: Material) -> some View { _Passthrough(self) }
    func overlay<O: View>(_ overlay: O) -> some View { _Overlay(content: AnyView(self), overlay: AnyView(overlay)) }

    // MARK: SwiftUI API Surface (stubs/passthrough)
    func navigationTitle(_ title: String) -> some View { _Passthrough(self) }
    func navigationTitle(_ title: Text) -> some View { _Passthrough(self) }
    func navigationBarTitleDisplayMode(_ mode: Any = ()) -> some View { _Passthrough(self) }

    func listStyle<S>(_ style: S) -> some View { _Passthrough(self) }
    func pickerStyle<S>(_ style: S) -> some View { _Passthrough(self) }
    func buttonStyle<S>(_ style: S) -> some View { _Passthrough(self) }
    func textFieldStyle<S>(_ style: S) -> some View { _Passthrough(self) }
    func toggleStyle<S>(_ style: S) -> some View { _Passthrough(self) }
    func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View { _Passthrough(self) }
    func toolbar(_ any: Any = ()) -> some View { _Passthrough(self) }
    func toolbarBackground(_ any: Any = (), for: Any = ()) -> some View { _Passthrough(self) }
    func modelContainer(_ any: Any) -> some View { _Passthrough(self) }

    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> some View { _Passthrough(self) }
    func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View { _Passthrough(self) }
    func help(_ text: String) -> some View { _Passthrough(self) }

    func sheet<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        _Sheet(content: AnyView(self), isPresented: isPresented, onDismiss: nil, sheet: AnyView(content()))
    }
    func sheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)?, @ViewBuilder content: () -> Content) -> some View {
        _Sheet(content: AnyView(self), isPresented: isPresented, onDismiss: onDismiss, sheet: AnyView(content()))
    }
    func alert<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        _Alert(content: AnyView(self), isPresented: isPresented, alert: AnyView(content()))
    }

    func focused(_ isFocused: Binding<Bool>) -> some View { _Passthrough(self) }
    func focused(_ isFocused: FocusState<Bool>.Binding) -> some View {
        _FocusBoolBinder(content: AnyView(self), binding: isFocused)
    }

    func onChange<V: Equatable>(of value: V, perform action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View {
        _OnChange(content: AnyView(self), value: value, action: action)
    }

    func task(priority: Any? = nil, _ action: @escaping () async -> Void) -> some View {
        // Stub: retained for API compatibility (iGopherBrowser uses this).
        // A real implementation should be lifecycle-aware and cancellation-safe.
        _Passthrough(self)
    }

    func onSubmit(_ action: @escaping () -> Void) -> some View { _Passthrough(self) }
    func submitLabel(_ label: SubmitLabel) -> some View { _Passthrough(self) }

    func searchable(text: Binding<String>) -> some View { _Passthrough(self) }
    func refreshable(action: @escaping () async -> Void) -> some View { _Passthrough(self) }

    func disabled(_ disabled: Bool) -> some View { _Passthrough(self) }

    func frame(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        _Frame(
            content: AnyView(self),
            width: width,
            height: height,
            minWidth: nil,
            maxWidth: nil,
            minHeight: nil,
            maxHeight: nil
        )
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
        _Frame(
            content: AnyView(self),
            width: idealWidth,
            height: idealHeight,
            minWidth: minWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
    }

    func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        let amt = Int(length ?? 1)
        let t = edges.contains(.top) || edges == .all || edges.contains(.vertical)
        let b = edges.contains(.bottom) || edges == .all || edges.contains(.vertical)
        let l = edges.contains(.leading) || edges == .all || edges.contains(.horizontal)
        let r = edges.contains(.trailing) || edges == .all || edges.contains(.horizontal)
        return AnyView(_EdgePadding(
            content: AnyView(self),
            top: t ? amt : 0,
            leading: l ? amt : 0,
            bottom: b ? amt : 0,
            trailing: r ? amt : 0
        ))
    }

    func onAppear(perform action: @escaping () -> Void) -> some View {
        _OnAppear(content: AnyView(self), action: action)
    }
}

public enum SubmitLabel: Hashable, Sendable {
    case done
    case go
    case search
    case send
    case next
    case `return`
}

private struct _Sheet: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let sheet: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        if isPresented.wrappedValue {
            let dismiss = {
                if isPresented.wrappedValue {
                    isPresented.wrappedValue = false
                    onDismiss?()
                }
            }
            ctx.runtime._registerOverlay(view: AnyView(
                ZStack {
                    // Dim background.
                    Color.gray.opacity(0.35)
                    VStack(spacing: 1) {
                        HStack(spacing: 1) {
                            Text("Sheet")
                            Spacer()
                            Button("Close") { dismiss() }
                        }
                        sheet
                    }
                    .padding(1)
                }
            ), dismiss: dismiss)
        }
        return ctx.buildChild(content)
    }
}

private struct _Alert: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let isPresented: Binding<Bool>
    let alert: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        if isPresented.wrappedValue {
            let dismiss = {
                if isPresented.wrappedValue {
                    isPresented.wrappedValue = false
                }
            }
            ctx.runtime._registerOverlay(view: AnyView(
                ZStack {
                    Color.gray.opacity(0.35)
                    VStack(spacing: 1) {
                        alert
                        HStack(spacing: 1) {
                            Spacer()
                            Button("OK") { dismiss() }
                        }
                    }
                    .padding(1)
                }
            ), dismiss: dismiss)
        }
        return ctx.buildChild(content)
    }
}

private struct _Frame: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let width: CGFloat?
    let height: CGFloat?
    let minWidth: CGFloat?
    let maxWidth: CGFloat?
    let minHeight: CGFloat?
    let maxHeight: CGFloat?

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        func toInt(_ v: CGFloat?) -> Int? {
            guard let v else { return nil }
            if v.isInfinite { return Int.max }
            return max(0, Int(v.rounded()))
        }
        return .frame(
            width: toInt(width),
            height: toInt(height),
            minWidth: toInt(minWidth),
            maxWidth: toInt(maxWidth),
            minHeight: toInt(minHeight),
            maxHeight: toInt(maxHeight),
            child: ctx.buildChild(content)
        )
    }
}

private struct _EdgePadding: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let top: Int
    let leading: Int
    let bottom: Int
    let trailing: Int

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .edgePadding(top: top, leading: leading, bottom: bottom, trailing: trailing, child: ctx.buildChild(content))
    }
}

private struct _FocusBoolBinder: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let binding: FocusState<Bool>.Binding

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let p = ctx.path
        runtime._registerFocusBoolBinding(path: p, set: { binding.wrappedValue = $0 })
        // Programmatic focus: if the binding is already true and nothing is focused yet,
        // move focus here.
        if binding.wrappedValue, runtime.focusedActionRawID() == nil {
            runtime._setFocus(path: p)
        }
        return ctx.buildChild(content)
    }
}

private struct _Style: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let fg: Color?
    let bg: Color?

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .style(fg: fg, bg: bg, child: ctx.buildChild(content))
    }
}

private struct _Background: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let background: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .background(child: ctx.buildChild(content), background: ctx.buildChild(background))
    }
}

private struct _Overlay: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let overlay: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .overlay(child: ctx.buildChild(content), overlay: ctx.buildChild(overlay))
    }
}

// MARK: Stubs for SwiftUI style/shortcut types
public struct PlainListStyle: Hashable, Sendable { public init() {} }
public struct RoundedBorderTextFieldStyle: Hashable, Sendable { public init() {} }
public struct PlainButtonStyle: Hashable, Sendable { public init() {} }
public struct PrimaryFillButtonStyle: Hashable, Sendable { public init() {} }

public enum ListStyle {
    public static var plain: PlainListStyle { PlainListStyle() }
    public static var sidebar: PlainListStyle { PlainListStyle() }
}

public enum PickerStyle {
    public struct Segmented: Hashable, Sendable { public init() {} }
    public struct Menu: Hashable, Sendable { public init() {} }
    public static var segmented: Segmented { Segmented() }
    public static var menu: Menu { Menu() }
}

public enum ToggleStyle {
    public struct Switch: Hashable, Sendable { public init() {} }
    public static var `switch`: Switch { Switch() }
}

public enum ButtonStyle {
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
    public static var bordered: PlainButtonStyle { PlainButtonStyle() }
    public static var borderedProminent: PlainButtonStyle { PlainButtonStyle() }
    public static var liquidGlass: PlainButtonStyle { PlainButtonStyle() }
}

public enum TextFieldStyle {
    public static var plain: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() }
    public static var roundedBorder: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() }
}

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

// MARK: Tagged options (Picker)
public extension View {
    func tag<V: Hashable>(_ value: V) -> some View {
        _Tag(content: AnyView(self), value: AnyHashable(value))
    }
}

private struct _Tag: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let value: AnyHashable

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .tagged(value: value, label: ctx.buildChild(content))
    }
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
