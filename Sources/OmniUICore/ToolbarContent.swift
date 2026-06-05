@MainActor
public protocol ToolbarContent {
    associatedtype _ToolbarBody: ToolbarContent = Never
    @preconcurrency @MainActor @ToolbarContentBuilder var body: _ToolbarBody { get }
    func _toolbarView() -> AnyView
}

extension Never: ToolbarContent {
    public typealias _ToolbarBody = Never

    public func _toolbarView() -> AnyView {
        AnyView(EmptyView())
    }
}

@MainActor
public extension ToolbarContent where _ToolbarBody: ToolbarContent {
    func _toolbarView() -> AnyView {
        body._toolbarView()
    }
}

@MainActor
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

    public init<C: ToolbarContent>(toolbarContent content: C) {
        self.content = content._toolbarView()
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
@MainActor
public enum ToolbarContentBuilder {
    public static func buildExpression<C: ToolbarContent>(_ expression: C) -> AnyToolbarContent {
        AnyToolbarContent(toolbarContent: expression)
    }

    @_disfavoredOverload
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

    public static func buildLimitedAvailability(_ component: AnyToolbarContent) -> AnyToolbarContent {
        component
    }
}
