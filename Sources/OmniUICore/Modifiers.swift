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
