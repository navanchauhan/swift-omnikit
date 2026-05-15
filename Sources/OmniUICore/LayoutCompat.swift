import Foundation

public struct ProposedViewSize: Sendable {
    public var width: CGFloat?
    public var height: CGFloat?

    public init(width: CGFloat? = nil, height: CGFloat? = nil) {
        self.width = width
        self.height = height
    }

    public static let unspecified = ProposedViewSize()
}

public struct LayoutSubview: Sendable {
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        _ = proposal
        return CGSize(width: 0, height: 0)
    }

    public func place(at point: CGPoint, proposal: ProposedViewSize) {
        _ = point
        _ = proposal
    }
}

public typealias LayoutSubviews = [LayoutSubview]

public protocol Layout: View where Body == Never {
    typealias Subviews = LayoutSubviews
}

public extension Layout {
    var body: Never { fatalError("Primitive layouts have no body") }

    func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        _LayoutContainer(layout: self, content: content())
    }
}

struct _LayoutContainer<L: Layout, Content: View>: View {
    typealias Body = Never

    let layout: L
    let content: Content
}

extension _LayoutContainer: _PrimitiveView {
    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let child = OmniUICore._makeNode(content, &ctx)
        let spacing = _layoutSpacing(from: layout)
        return .flowLayout(
            horizontalSpacing: spacing.horizontal,
            verticalSpacing: spacing.vertical,
            children: _layoutChildren(from: child)
        )
    }
}

private func _layoutChildren(from node: _VNode) -> [_VNode] {
    if case .group(let children) = node {
        return children
    }
    return [node]
}

private func _layoutSpacing(from layout: Any) -> (horizontal: Int, vertical: Int) {
    var horizontal = 8
    var vertical = 8
    for child in Mirror(reflecting: layout).children {
        guard let label = child.label else { continue }
        if label == "horizontalSpacing", let value = _spacingInt(child.value) {
            horizontal = value
        } else if label == "verticalSpacing", let value = _spacingInt(child.value) {
            vertical = value
        } else if label == "spacing", let value = _spacingInt(child.value) {
            horizontal = value
            vertical = value
        }
    }
    return (horizontal, vertical)
}

private func _spacingInt(_ value: Any) -> Int? {
    if let cgFloat = value as? CGFloat { return Int(cgFloat.rounded()) }
    if let double = value as? Double { return Int(double.rounded()) }
    if let int = value as? Int { return int }
    return nil
}
