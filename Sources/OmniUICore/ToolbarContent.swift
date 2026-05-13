public protocol ToolbarContent {
    func _toolbarView() -> AnyView
}

public extension ToolbarContent where Self: View {
    func _toolbarView() -> AnyView {
        AnyView(self)
    }
}

public struct AnyToolbarContent: View, ToolbarContent, _PrimitiveView {
    public typealias Body = Never

    let content: AnyView

    public init<C: View & ToolbarContent>(_ content: C) {
        self.content = AnyView(content)
    }

    public init<V: View>(view: V) {
        self.content = AnyView(view)
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.buildChild(content)
    }

    public func _toolbarView() -> AnyView {
        AnyView(self)
    }
}

@resultBuilder
public enum ToolbarContentBuilder {
    public static func buildExpression<C: View & ToolbarContent>(_ expression: C) -> AnyToolbarContent {
        AnyToolbarContent(expression)
    }

    public static func buildExpression<V: View>(_ expression: V) -> AnyToolbarContent {
        AnyToolbarContent(view: expression)
    }

    public static func buildBlock(_ components: AnyToolbarContent...) -> AnyToolbarContent {
        AnyToolbarContent(view: TupleView(components.map { AnyView($0) }))
    }

    public static func buildOptional(_ content: AnyToolbarContent?) -> AnyToolbarContent {
        content ?? AnyToolbarContent(view: EmptyView())
    }

    public static func buildEither(first content: AnyToolbarContent) -> AnyToolbarContent { content }
    public static func buildEither(second content: AnyToolbarContent) -> AnyToolbarContent { content }

    public static func buildArray(_ components: [AnyToolbarContent]) -> AnyToolbarContent {
        AnyToolbarContent(view: TupleView(components.map { AnyView($0) }))
    }
}
