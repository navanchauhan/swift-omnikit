public enum ToolbarItemPlacement: Hashable, Sendable {
    case automatic
    case cancellationAction
    case confirmationAction
    case topBarLeading
    case topBarTrailing
    case navigationBarLeading
    case navigationBarTrailing
    case bottomBar
    case principal
}

public struct ToolbarItem<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    public let placement: ToolbarItemPlacement
    let content: Content

    public init(placement: ToolbarItemPlacement, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // OmniUI does not currently model toolbars; this is a compile-surface shim.
        ctx.buildChild(content)
    }
}

public struct EditButton: View, _PrimitiveView {
    public typealias Body = Never
    public init() {}

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // Stub: OmniUI doesn't currently support edit mode.
        ctx.buildChild(Button("Edit") {})
    }
}

