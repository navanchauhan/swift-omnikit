import Foundation

// MARK: - Grid

/// A container view that arranges its children in a grid, using `GridRow` to define rows.
/// Each `GridRow` distributes its children across columns. Non-`GridRow` children span all columns.
public struct Grid<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let alignment: Alignment
    let horizontalSpacing: CGFloat?
    let verticalSpacing: CGFloat?
    let content: Content

    public init(
        alignment: Alignment = .center,
        horizontalSpacing: CGFloat? = nil,
        verticalSpacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let childNode = ctx.buildChild(content)
        let topChildren = _flatten(childNode)

        guard !topChildren.isEmpty else { return .empty }

        let hGap = Swift.max(0, Int((horizontalSpacing ?? 1).rounded()))
        let vGap = Swift.max(0, Int((verticalSpacing ?? 0).rounded()))

        // Build each entry as a row node.
        // GridRow children are tagged with _GridRowTag and get laid out horizontally.
        // Non-GridRow children span all columns (rendered as-is).
        var rowNodes: [_VNode] = []
        for child in topChildren {
            if case .tagged(let tag, let inner) = child, tag.base is _GridRowTag {
                let cells = _flatten(inner)
                rowNodes.append(.stack(axis: .horizontal, spacing: hGap, children: cells))
            } else {
                rowNodes.append(child)
            }
        }

        return .stack(axis: .vertical, spacing: vGap, children: rowNodes)
    }
}

// MARK: - GridRow

/// Represents a single row inside a `Grid`. Its children become individual cells.
public struct GridRow<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let inner = ctx.buildChild(content)
        return .tagged(value: AnyHashable(_GridRowTag()), label: inner)
    }
}

/// Internal tag to identify GridRow nodes during Grid layout.
struct _GridRowTag: Hashable {}

// MARK: - gridCellColumns modifier

public extension View {
    /// Tells the parent `Grid` that this cell should span the given number of columns.
    /// Currently a hint stored as padding metadata; the Grid layout uses equal-width columns.
    func gridCellColumns(_ count: Int) -> some View {
        _GridCellSpan(content: AnyView(self), span: count)
    }
}

private struct _GridCellSpan: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let span: Int

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // For now, render the content as-is. A future enhancement could communicate
        // the span to the Grid layout algorithm via a tagged node.
        ctx.buildChild(content)
    }
}
