import Foundation

public extension View {
    func font(_ font: Font?) -> some View { _Passthrough(self) }
    func foregroundStyle(_ color: Color) -> some View { _Style(content: AnyView(self), fg: color, bg: nil) }
    func foregroundColor(_ color: Color) -> some View { _Style(content: AnyView(self), fg: color, bg: nil) }
    func fontWeight(_ weight: Font.Weight?) -> some View {
        _ = weight
        return _Passthrough(self)
    }
    func multilineTextAlignment(_ alignment: TextAlignment) -> some View { _Passthrough(self) }
    func lineLimit(_ limit: Int?) -> some View { _Passthrough(self) }
    func monospacedDigit() -> some View { _Passthrough(self) }
    func textSelection(_ selection: TextSelection) -> some View {
        _ = selection
        return _Passthrough(self)
    }
    func accentColor(_ color: Color?) -> some View {
        _ = color
        return _Passthrough(self)
    }
    func cornerRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius))
    }
    func shadow(color: Color, radius: CGFloat) -> some View {
        shadow(color: color, radius: radius, x: 0, y: 0)
    }
    func shadow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        _Shadow(content: AnyView(self), color: color, radius: radius, x: x, y: y)
    }
    func opacity(_ value: CGFloat) -> some View { _Passthrough(self) }
    func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        _ = x
        _ = y
        return _Passthrough(self)
    }
    func transition(_ t: AnyTransition) -> some View {
        _ = t
        return _Passthrough(self)
    }
    func ignoresSafeArea() -> some View { _Passthrough(self) }
    func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
        _ = style
        let kind: _ShapeKind = {
            if let rr = shape as? RoundedRectangle {
                return .roundedRectangle(cornerRadius: Int(rr.cornerRadius.rounded()))
            }
            if shape is Rectangle { return .rectangle }
            if shape is Circle { return .circle }
            if shape is Ellipse { return .ellipse }
            if shape is Capsule { return .capsule }
            if shape is Path { return .path }
            return .rectangle
        }()
        return _Clip(content: AnyView(self), kind: kind)
    }
    func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
        _ = shape
        _ = eoFill
        return _ContentShapeRect(content: AnyView(self))
    }
    func mask<M: View>(_ mask: M) -> some View { _Passthrough(self) }
    func labelsHidden() -> some View {
        _LabelsHidden(content: AnyView(self), hidden: true)
    }

    // Liquid Glass (compile-only stubs)
    func glassEffect() -> some View { _Passthrough(self) }
    func glassEffect(_ style: GlassEffect) -> some View { _Passthrough(self) }
    func glassEffect(in shape: GlassEffectShape) -> some View {
        _ = shape
        return _Passthrough(self)
    }

    func background<B: View>(_ background: B) -> some View { _Background(content: AnyView(self), background: AnyView(background)) }
    func background<B: View>(@ViewBuilder _ background: () -> B) -> some View {
        _Background(content: AnyView(self), background: AnyView(background()))
    }
    func background(_ color: Color) -> some View { _Style(content: AnyView(self), fg: nil, bg: color) }
    func background(_ material: Material) -> some View {
        // Terminal-friendly approximation.
        switch material.raw {
        case Material.ultraThinMaterial.raw:
            return AnyView(background(Color.gray.opacity(0.15)))
        case Material.regularMaterial.raw:
            return AnyView(background(Color.gray.opacity(0.25)))
        default:
            return AnyView(background(Color.gray.opacity(0.2)))
        }
    }
    func overlay<O: View>(_ overlay: O) -> some View { _Overlay(content: AnyView(self), overlay: AnyView(overlay)) }
    func overlay<O: View>(@ViewBuilder _ overlay: () -> O) -> some View {
        _Overlay(content: AnyView(self), overlay: AnyView(overlay()))
    }

    // MARK: SwiftUI API Surface (stubs/passthrough)
    func navigationTitle(_ title: String) -> some View { _Passthrough(self) }
    func navigationTitle(_ title: Text) -> some View { _Passthrough(self) }
    func navigationBarTitleDisplayMode(_ mode: Any = ()) -> some View { _Passthrough(self) }

    func onTapGesture(perform action: @escaping () -> Void) -> some View {
        _TapGesture(content: AnyView(self), count: 1, action: action, actionScopePath: _UIRuntime._currentPath ?? [])
    }

    func onTapGesture(count: Int, perform action: @escaping () -> Void) -> some View {
        _TapGesture(content: AnyView(self), count: count, action: action, actionScopePath: _UIRuntime._currentPath ?? [])
    }

    func allowsHitTesting(_ enabled: Bool) -> some View {
        _AllowsHitTesting(content: AnyView(self), enabled: enabled)
    }

    @ViewBuilder
    func preferredColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }

    func listStyle<S: ListStyle>(_ style: S) -> some View { _Passthrough(self) }
    func pickerStyle<S: PickerStyle>(_ style: S) -> some View { _Passthrough(self) }
    func buttonStyle<S: ButtonStyle>(_ style: S) -> some View { _Passthrough(self) }
    func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View { _Passthrough(self) }
    func toggleStyle<S: ToggleStyle>(_ style: S) -> some View { _Passthrough(self) }
    func labelStyle<S: LabelStyle>(_ style: S) -> some View { _Passthrough(self) }
    func scrollContentBackground(_ visibility: Visibility) -> some View { _Passthrough(self) }
    func listRowSeparator(_ visibility: Visibility) -> some View { _Passthrough(self) }
    func listRowBackground<B: View>(_ background: B?) -> some View {
        _ = background
        return _Passthrough(self)
    }
    func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View { _Passthrough(self) }
    func toolbar(_ any: Any = ()) -> some View { _Passthrough(self) }
    func toolbarBackground(_ any: Any = (), for: Any = ()) -> some View { _Passthrough(self) }
    func controlSize(_ size: ControlSize) -> some View { _Passthrough(self) }
    func modelContainer(_ any: Any) -> some View { _Passthrough(self) }
    func modelContainer(_ container: ModelContainer) -> some View {
        environment(\.modelContext, container.mainContext)
    }
    func modelContainer(for modelTypes: [Any.Type], inMemory: Bool = false) -> some View {
        // SwiftUI's SwiftData modifier is non-throwing; mirror that here.
        let container = (try? ModelContainer(for: modelTypes, inMemory: inMemory))
        if let container {
            return AnyView(environment(\.modelContext, container.mainContext))
        }
        return AnyView(self)
    }

    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> some View {
        _KeyboardShortcutBinder(content: AnyView(self), shortcut: KeyboardShortcut(key, modifiers: modifiers))
    }
    func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        _KeyboardShortcutBinder(content: AnyView(self), shortcut: shortcut)
    }
    func help(_ text: String) -> some View { _Passthrough(self) }
    func onExitCommand(perform action: @escaping () -> Void) -> some View {
        _ = action
        return _Passthrough(self)
    }

    func sheet<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        _Sheet(content: AnyView(self), isPresented: isPresented, onDismiss: nil, sheet: AnyView(content()))
    }
    func sheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)?, @ViewBuilder content: () -> Content) -> some View {
        _Sheet(content: AnyView(self), isPresented: isPresented, onDismiss: onDismiss, sheet: AnyView(content()))
    }
    func alert<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        _Alert(content: AnyView(self), isPresented: isPresented, alert: AnyView(content()))
    }

    func alert(isPresented: Binding<Bool>, content: @escaping () -> Alert) -> some View {
        _AlertFromType(content: AnyView(self), isPresented: isPresented, makeAlert: content)
    }

    func focused(_ isFocused: Binding<Bool>) -> some View {
        _FocusBoolBinder(content: AnyView(self), get: { isFocused.wrappedValue }, set: { isFocused.wrappedValue = $0 })
    }

    func focused(_ isFocused: Bool) -> some View {
        _FocusBoolValueBinder(content: AnyView(self), isFocused: isFocused)
    }

    func focused(_ isFocused: FocusState<Bool>.Binding) -> some View {
        _FocusBoolBinder(content: AnyView(self), get: { isFocused.wrappedValue }, set: { isFocused.wrappedValue = $0 })
    }

    func id<ID: Hashable>(_ id: ID) -> some View {
        _ = id
        return _Passthrough(self)
    }

    func onDelete(perform action: @escaping (IndexSet) -> Void) -> some View {
        _ = action
        return _Passthrough(self)
    }

    func onChange<V: Equatable>(of value: V, perform action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View {
        _OnChange(content: AnyView(self), value: value, action: action)
    }

    func task(priority: Any? = nil, _ action: @escaping () async -> Void) -> some View {
        _ = priority
        return _TaskBinder(content: AnyView(self), action: action)
    }

    func onSubmit(_ action: @escaping () -> Void) -> some View {
        _OnSubmitBinder(content: AnyView(self), action: action, actionScopePath: _UIRuntime._currentPath ?? [])
    }
    func submitLabel(_ label: SubmitLabel) -> some View { _Passthrough(self) }

    func keyboardType(_ type: UIKeyboardType) -> some View { _Passthrough(self) }
    func textInputAutocapitalization(_ style: TextInputAutocapitalization?) -> some View { _Passthrough(self) }
    func textContentType(_ type: UITextContentType?) -> some View { _Passthrough(self) }
    func disableAutocorrection(_ disable: Bool? = true) -> some View { _Passthrough(self) }

    func searchable(text: Binding<String>) -> some View { _Passthrough(self) }
    func refreshable(action: @escaping () async -> Void) -> some View { _Passthrough(self) }

    func disabled(_ disabled: Bool) -> some View { _Passthrough(self) }

    func hidden() -> some View {
        _Hidden(content: AnyView(self))
    }

    func quickLookPreview(_ url: Binding<URL?>) -> some View {
        _ = url
        return _Passthrough(self)
    }

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
        // Negative padding is used in some upstream SwiftUI views for fine visual tuning.
        // OmniUI's box model doesn't support negative extents safely, so clamp to zero.
        let amt = max(0, Int(length ?? 1))
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

    func padding(_ length: CGFloat) -> some View {
        padding(.all, length)
    }

    func onAppear(perform action: @escaping () -> Void) -> some View {
        _OnAppear(content: AnyView(self), action: action)
    }

    func safeAreaInset<Content: View>(edge: Edge, @ViewBuilder content: () -> Content) -> some View {
        _SafeAreaInset(base: AnyView(self), edge: edge, inset: AnyView(content()))
    }

    func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        _ = detents
        return _Passthrough(self)
    }

    func presentationDragIndicator(_ visibility: Visibility) -> some View {
        _ = visibility
        return _Passthrough(self)
    }
}

private struct _Hidden: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // Still build the subtree so it can register actions/shortcuts, but don't render it.
        _ = ctx.buildChild(content)
        return .empty
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

public struct Alert {
    public struct Button {
        enum Kind {
            case `default`
            case cancel
            case destructive
        }

        let kind: Kind
        let label: Text
        let action: (() -> Void)?

        private init(kind: Kind, label: Text, action: (() -> Void)?) {
            self.kind = kind
            self.label = label
            self.action = action
        }

        public static func `default`(_ label: Text, action: (() -> Void)? = nil) -> Button {
            Button(kind: .default, label: label, action: action)
        }

        public static func cancel(_ label: Text, action: (() -> Void)? = nil) -> Button {
            Button(kind: .cancel, label: label, action: action)
        }

        public static func destructive(_ label: Text, action: (() -> Void)? = nil) -> Button {
            Button(kind: .destructive, label: label, action: action)
        }
    }

    public let title: Text
    public let message: Text?
    public let dismissButton: Button?

    public init(title: Text, message: Text? = nil, dismissButton: Button? = nil) {
        self.title = title
        self.message = message
        self.dismissButton = dismissButton
    }
}

private struct _AlertFromType: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let isPresented: Binding<Bool>
    let makeAlert: () -> Alert

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        if isPresented.wrappedValue {
            let alert = makeAlert()

            let dismiss = {
                if isPresented.wrappedValue {
                    isPresented.wrappedValue = false
                }
            }

            let button = alert.dismissButton ?? .default(Text("OK"), action: nil)
            let messageView: AnyView = alert.message.map(AnyView.init) ?? AnyView(EmptyView())
            ctx.runtime._registerOverlay(view: AnyView(
                ZStack {
                    Color.gray.opacity(0.35)
                    VStack(spacing: 1) {
                        VStack(spacing: 1) {
                            alert.title
                            messageView
                        }
                        HStack(spacing: 1) {
                            Spacer()
                            Button(button.label.content) {
                                dismiss()
                                button.action?()
                            }
                        }
                    }
                    .padding(1)
                }
            ), dismiss: dismiss)
        }
        return ctx.buildChild(content)
    }
}

private struct _TapGesture: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let count: Int
    let action: () -> Void
    let actionScopePath: [Int]

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _ = count // multi-tap not modeled; retained for call-site compatibility.
        guard _UIRuntime._hitTestingEnabled else {
            return ctx.buildChild(content)
        }

        let runtime = ctx.runtime
        let controlPath = ctx.path
        let id = runtime._registerAction({
            runtime._setFocus(path: controlPath)
            action()
        }, path: actionScopePath)
        runtime._registerFocusable(path: controlPath, activate: id)
        return .tapTarget(id: id, child: ctx.buildChild(content))
    }
}

private struct _AllowsHitTesting: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let enabled: Bool

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _UIRuntime.$_hitTestingEnabled.withValue(enabled) {
            ctx.buildChild(content)
        }
    }
}

private struct _SafeAreaInset: View, _PrimitiveView {
    typealias Body = Never

    let base: AnyView
    let edge: Edge
    let inset: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        switch edge {
        case .top:
            return ctx.buildChild(VStack(spacing: 0) { inset; base })
        case .bottom:
            return ctx.buildChild(VStack(spacing: 0) { base; inset })
        case .leading:
            return ctx.buildChild(HStack(spacing: 0) { inset; base })
        case .trailing:
            return ctx.buildChild(HStack(spacing: 0) { base; inset })
        }
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
    let get: () -> Bool
    let set: (Bool) -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let captureID = runtime._beginFocusCapture()
        let node = _UIRuntime.$_currentFocusCaptureID.withValue(captureID) {
            ctx.buildChild(content)
        }
        guard let focusPath = runtime._endFocusCapture(captureID) else {
            return node
        }

        runtime._registerFocusBoolBinding(path: focusPath, set: set)

        let wantsFocus = get()
        let isFocused = runtime._isFocused(path: focusPath)
        if wantsFocus && !isFocused {
            runtime._setFocus(path: focusPath)
        } else if !wantsFocus && isFocused {
            runtime._setFocus(path: nil)
        }

        return node
    }
}

private struct _FocusBoolValueBinder: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let isFocused: Bool

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let captureID = runtime._beginFocusCapture()
        let node = _UIRuntime.$_currentFocusCaptureID.withValue(captureID) {
            ctx.buildChild(content)
        }
        guard let focusPath = runtime._endFocusCapture(captureID) else {
            return node
        }

        let currentlyFocused = runtime._isFocused(path: focusPath)
        if isFocused && !currentlyFocused {
            runtime._setFocus(path: focusPath)
        } else if !isFocused && currentlyFocused {
            runtime._setFocus(path: nil)
        }

        return node
    }
}

private struct _OnSubmitBinder: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let action: () -> Void
    let actionScopePath: [Int]

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let captureID = runtime._beginFocusCapture()
        let node = _UIRuntime.$_currentFocusCaptureID.withValue(captureID) {
            ctx.buildChild(content)
        }
        if let focusPath = runtime._endFocusCapture(captureID) {
            runtime._registerSubmitHandler(controlPath: focusPath, actionScopePath: actionScopePath, action: action)
        }
        return node
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

private struct _Shadow: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .shadow(
            child: ctx.buildChild(content),
            color: color,
            radius: max(0, Int(radius.rounded())),
            x: Int(x.rounded()),
            y: Int(y.rounded())
        )
    }
}

private struct _Clip: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let kind: _ShapeKind

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .clip(kind: kind, child: ctx.buildChild(content))
    }
}

private struct _ContentShapeRect: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .contentShapeRect(child: ctx.buildChild(content))
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

private struct _LabelsHidden: View, _PrimitiveView {
    typealias Body = Never
    let content: AnyView
    let hidden: Bool

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _UIRuntime.$_labelsHidden.withValue(hidden) {
            ctx.buildChild(content)
        }
    }
}

private struct _KeyboardShortcutBinder: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let shortcut: KeyboardShortcut

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let captureID = runtime._beginFocusCapture()
        let node = _UIRuntime.$_currentFocusCaptureID.withValue(captureID) {
            ctx.buildChild(content)
        }
        if let focusPath = runtime._endFocusCapture(captureID) {
            runtime._registerKeyboardShortcut(shortcut, forFocusablePath: focusPath)
        }
        return node
    }
}

// MARK: Keyboard shortcuts

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
public struct _Passthrough: View, _PrimitiveView {
    public typealias Body = Never

    // Type-erase immediately to avoid exponential generic growth in large `body` expressions.
    let content: AnyView

    public init<V: View>(_ content: V) { self.content = AnyView(content) }

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

private struct _TaskBinder: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let action: () async -> Void

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.runtime._registerTask(path: ctx.path, action: action)
        return ctx.buildChild(content)
    }
}
