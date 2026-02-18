import Foundation

public struct Text: View, _PrimitiveView {
    public typealias Body = Never
    public let content: String

    public init(_ content: String) {
        self.content = content
    }

    public init(_ image: Image) {
        // SwiftUI supports `Text(Image(...))` for inline symbols. Our renderer is text-based,
        // so approximate with the image's symbol name.
        self.content = image.name
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .text(content)
    }
}

public struct Image: View, _PrimitiveView {
    public typealias Body = Never

    let name: String

    public init(systemName: String) {
        self.name = systemName
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .image(name)
    }
}

public struct Spacer: View, _PrimitiveView {
    public typealias Body = Never
    public init() {}
    public init(minLength: CGFloat? = nil) { self.init() }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode { .spacer }
}

public struct Divider: View, _PrimitiveView {
    public typealias Body = Never
    public init() {}

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode { .divider }
}

public struct ScrollView<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let axes: Axis.Set
    let showsIndicators: Bool
    let content: Content
    let actionScopePath: [Int]

    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let controlPath = ctx.path
        let isFocused = runtime._isFocused(path: controlPath)

        // ScrollView is a container; it should not participate in tab focus order.
        // Wheel routing uses `scrollRegions` hit-testing and does not require focus.
        let id = runtime._registerAction({}, path: actionScopePath)

        let axis: _Axis = axes.contains(.horizontal) && !axes.contains(.vertical) ? .horizontal : .vertical
        let offset = runtime._getScrollOffset(path: controlPath)

        return .scrollView(
            id: id,
            path: controlPath,
            isFocused: isFocused,
            axis: axis,
            offset: offset,
            content: ctx.buildChild(content)
        )
    }
}

public struct ScrollViewProxy {
    let _scrollTo: (AnyHashable, Alignment?) -> Void

    public func scrollTo<ID: Hashable>(_ id: ID, anchor: Alignment? = nil) {
        _scrollTo(AnyHashable(id), anchor)
    }
}

public struct ScrollViewReader<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let content: (ScrollViewProxy) -> Content

    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // Stub: we don't yet track view ids -> scroll offsets. Provide a proxy that compiles.
        let proxy = ScrollViewProxy(_scrollTo: { _, _ in })
        return ctx.buildChild(content(proxy))
    }
}

public struct GeometryProxy: Sendable {
    public let size: CGSize
}

public struct GeometryReader<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let content: (GeometryProxy) -> Content

    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {
        self.content = content
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // SwiftUI's GeometryReader provides the proposed size of its container.
        // We approximate this with the current render size (terminal grid).
        let rs = _UIRuntime._currentRenderSize ?? _Size(width: 0, height: 0)
        let proxy = GeometryProxy(size: CGSize(width: CGFloat(rs.width), height: CGFloat(rs.height)))
        return ctx.buildChild(content(proxy))
    }
}

public struct ProgressView: View, _PrimitiveView {
    public typealias Body = Never

    let label: String?
    let value: Double?
    let total: Double

    public init() {
        self.label = nil
        self.value = nil
        self.total = 1.0
    }

    public init(_ title: String) {
        self.label = title
        self.value = nil
        self.total = 1.0
    }

    public init(value: Double?, total: Double = 1.0) {
        self.label = nil
        self.value = value
        self.total = total
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _ = ctx
        if let value {
            let denom = total == 0 ? 1 : total
            let pct = Swift.max(0, Swift.min(1, value / denom))
            let filled = Int((pct * 10).rounded())
            let bar = String(repeating: "#", count: filled) + String(repeating: "-", count: Swift.max(0, 10 - filled))
            return .text("[\(bar)] \(Int((pct * 100).rounded()))%")
        }

        let glyphs = ["-", "\\", "|", "/"]
        let tick = Int(Date().timeIntervalSinceReferenceDate * 8)
        let spinner = glyphs[tick % glyphs.count]
        let title = label ?? "Loading"
        return .text("\(spinner) \(title)")
    }
}

private struct _AnySelectionAdapter {
    let get: () -> AnyHashable?
    let set: (AnyHashable) -> Void
}

public struct List<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    private let content: Content
    private let selection: _AnySelectionAdapter?
    private let actionScopePath: [Int]

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = nil
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.selection = _AnySelectionAdapter(
            get: { AnyHashable(selection.wrappedValue) },
            set: { any in
                if let typed = any.base as? SelectionValue {
                    selection.wrappedValue = typed
                }
            }
        )
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<SelectionValue?>,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.selection = _AnySelectionAdapter(
            get: { selection.wrappedValue.map(AnyHashable.init) },
            set: { any in
                selection.wrappedValue = any.base as? SelectionValue
            }
        )
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.content = ForEach(data, id: id, content: rowContent)
        self.selection = nil
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Data.Element: Identifiable, Content == ForEach<Data, Data.Element.ID, RowContent> {
        self.content = ForEach(data, content: rowContent)
        self.selection = nil
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        children: KeyPath<Data.Element, Data?>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Data.Element: Identifiable, Content == ForEach<Data, Data.Element.ID, RowContent> {
        _ = children
        // Stub: hierarchical list rendering not implemented yet; render only the root nodes.
        self.content = ForEach(data, content: rowContent)
        self.selection = nil
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let controlPath = ctx.path
        let isFocused = runtime._isFocused(path: controlPath)
        let id = runtime._registerAction({}, path: actionScopePath)
        let offset = runtime._getScrollOffset(path: controlPath)

        let rows = _flatten(ctx.buildChild(content))
        let selected = selection?.get()
        var rowIndex = 0

        let renderedRows: [_VNode] = rows.map { row in
            guard
                let selection,
                case .tagged(let value, let label) = row
            else { return row }

            let path = controlPath + [10_000 + rowIndex]
            rowIndex += 1
            let actionID = runtime._registerAction({
                runtime._setFocus(path: path)
                selection.set(value)
            }, path: actionScopePath)
            runtime._registerFocusable(path: path, activate: actionID)

            var rowLabel = label
            if selected == value {
                let tint = (_UIRuntime._currentEnvironment ?? runtime._baseEnvironment).tint ?? .accentColor
                rowLabel = .style(fg: tint, bg: nil, child: rowLabel)
            }
            return .button(id: actionID, isFocused: runtime._isFocused(path: path), label: rowLabel)
        }

        return .scrollView(
            id: id,
            path: controlPath,
            isFocused: isFocused,
            axis: .vertical,
            offset: offset,
            content: .stack(axis: .vertical, spacing: 0, children: renderedRows)
        )
    }
}

public struct Form<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let env = _UIRuntime._currentEnvironment ?? ctx.runtime._baseEnvironment
        let isGrouped = env.formStyleKind == .grouped

        if isGrouped {
            return ctx.buildChild(
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) { content }
                        .padding(1)
                        .background(Color.gray.opacity(0.08))
                }
            )
        }

        return ctx.buildChild(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(1)
            }
        )
    }
}

public struct GridItem: Hashable, Sendable {
    public enum Size: Hashable, Sendable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }

    public var size: Size
    public var spacing: CGFloat?

    public init(_ size: Size, spacing: CGFloat? = nil) {
        self.size = size
        self.spacing = spacing
    }
}

public struct LazyVGrid<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let columns: [GridItem]
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content

    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _ = alignment
        let items = _flatten(ctx.buildChild(content))
        guard !items.isEmpty else { return .empty }

        let gap = Swift.max(0, Int((spacing ?? 1).rounded()))
        let availableWidth = (_UIRuntime._currentRenderSize ?? _Size(width: 80, height: 0)).width
        let columnsCount = _gridColumnCount(columns, availableWidth: availableWidth, spacing: gap)

        guard columnsCount > 1 else {
            return .stack(axis: .vertical, spacing: gap, children: items)
        }

        var rows: [_VNode] = []
        rows.reserveCapacity((items.count + columnsCount - 1) / columnsCount)

        var index = 0
        while index < items.count {
            let end = Swift.min(index + columnsCount, items.count)
            let row = Array(items[index..<end])
            rows.append(.stack(axis: .horizontal, spacing: gap, children: row))
            index = end
        }

        return .stack(axis: .vertical, spacing: gap, children: rows)
    }
}

private func _gridColumnCount(_ columns: [GridItem], availableWidth: Int, spacing: Int) -> Int {
    guard let first = columns.first else { return 1 }

    switch first.size {
    case .adaptive(let minimum, _):
        let minCell = Swift.max(1, Int((minimum / 8).rounded()))
        let stride = Swift.max(1, minCell + spacing)
        return Swift.max(1, availableWidth / stride)
    default:
        return Swift.max(1, columns.count)
    }
}

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let data: Data
    let id: KeyPath<Data.Element, ID>
    let content: (Data.Element) -> Content

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.id = id
        self.content = content
    }

    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) where Data.Element: Identifiable, ID == Data.Element.ID {
        self.data = data
        self.id = \.id
        self.content = content
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // NOTE: We currently don't incorporate `id` into the build-path (path is `[Int]`).
        // This preserves call-site compatibility, but state may "move" if data is reordered.
        var nodes: [_VNode] = []
        nodes.reserveCapacity(data.count)
        for element in data {
            _ = element[keyPath: id] // keep the id "used" (and future-proof for stable identity work)
            nodes.append(ctx.buildChild(content(element)))
        }
        return .group(nodes)
    }
}

public struct NavigationStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let stackPath = ctx.path
        runtime._registerNavStackRoot(path: stackPath)
        let depth = runtime._navDepth(stackPath: stackPath)

        let top: AnyView? = runtime._navTop(stackPath: stackPath)

        if depth == 0 {
            // Root: render content normally (no chrome).
            return ctx.buildChild(content)
        }

        // Pushed destinations should be able to dismiss (pop) via `@Environment(\.dismiss)`.
        let current = _UIRuntime._currentEnvironment ?? runtime._baseEnvironment
        var next = current
        next.dismiss = DismissAction { runtime._navPop(stackPath: stackPath) }
        let mode = PresentationMode(dismiss: { runtime._navPop(stackPath: stackPath) })
        next.presentationMode = Binding(get: { mode }, set: { _ in })

        // Pushed: show a back button and render the pushed destination "full screen" within this stack.
        return .stack(axis: .vertical, spacing: 1, children: _flatten(.group([
            ctx.buildChild(
                HStack(spacing: 1) {
                    Button("Back") { runtime._navPop(stackPath: stackPath) }
                    Spacer()
                }
            ),
            _UIRuntime.$_currentEnvironment.withValue(next) {
                top.map { ctx.buildChild($0) } ?? ctx.buildChild(content)
            },
        ])))
    }
}

public struct NavigationLink<Label: View, Destination: View>: View, _PrimitiveView {
    public typealias Body = Never

    let destination: () -> Destination
    let label: Label
    let actionScopePath: [Int]
    let stackPath: [Int]

    public init(destination: @escaping () -> Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
        self.actionScopePath = _UIRuntime._currentPath ?? []
        self.stackPath = _UIRuntime._currentPath ?? []
    }

    public init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.destination = { destination }
        self.label = label()
        self.actionScopePath = _UIRuntime._currentPath ?? []
        self.stackPath = _UIRuntime._currentPath ?? []
    }

    public init(_ title: String, destination: @escaping () -> Destination) where Label == Text {
        self.destination = destination
        self.label = Text(title)
        self.actionScopePath = _UIRuntime._currentPath ?? []
        self.stackPath = _UIRuntime._currentPath ?? []
    }

    public init(_ title: String, destination: Destination) where Label == Text {
        self.destination = { destination }
        self.label = Text(title)
        self.actionScopePath = _UIRuntime._currentPath ?? []
        self.stackPath = _UIRuntime._currentPath ?? []
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        guard let stackPath = ctx.runtime._nearestNavStackRoot(from: ctx.path) else {
            // Render as a button that does nothing if not inside a NavigationStack.
            let runtime = ctx.runtime
            let controlPath = ctx.path
            let isFocused = runtime._isFocused(path: controlPath)
            let id = runtime._registerAction({ runtime._setFocus(path: controlPath) }, path: actionScopePath)
            runtime._registerFocusable(path: controlPath, activate: id)
            return .button(id: id, isFocused: isFocused, label: ctx.buildChild(label))
        }
        let runtime = ctx.runtime
        let controlPath = ctx.path
        let isFocused = runtime._isFocused(path: controlPath)
        let id = runtime._registerAction({
            runtime._setFocus(path: controlPath)
            runtime._navPush(stackPath: stackPath, view: AnyView(destination()))
        }, path: actionScopePath)
        runtime._registerFocusable(path: controlPath, activate: id)
        return .button(id: id, isFocused: isFocused, label: ctx.buildChild(label))
    }
}

public enum NavigationSplitViewVisibility: Hashable, Sendable {
    case automatic
    case all
    case doubleColumn
    case detailOnly
}

public struct NavigationSplitView<Sidebar: View, Detail: View>: View {
    public typealias Body = AnyView

    let columnVisibility: Binding<NavigationSplitViewVisibility>
    let sidebar: Sidebar
    let detail: Detail

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility> = Binding(get: { .automatic }, set: { _ in }),
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.columnVisibility = columnVisibility
        self.sidebar = sidebar()
        self.detail = detail()
    }

    @ViewBuilder
    private var composed: some View {
        switch columnVisibility.wrappedValue {
        case .detailOnly:
            detail
        case .automatic:
            // Terminal renderers don't support adaptive split metrics yet.
            // Default to detail so primary content remains visible.
            detail
        default:
            HStack(spacing: 1) {
                sidebar
                detail
            }
        }
    }

    public var body: AnyView { AnyView(composed) }
}

private struct _TabItemLabelTag: Hashable {
    let text: String
}

private struct _TabEntry {
    let value: AnyHashable?
    let label: String
    let content: _VNode
}

public struct TabView<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    private let content: Content
    private let selection: _AnySelectionAdapter?
    private let actionScopePath: [Int]
    @State private var localSelectionIndex: Int = 0

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = nil
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    public init<SelectionValue: Hashable>(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = _AnySelectionAdapter(
            get: { AnyHashable(selection.wrappedValue) },
            set: { any in
                if let typed = any.base as? SelectionValue {
                    selection.wrappedValue = typed
                }
            }
        )
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    public init<SelectionValue: Hashable>(selection: Binding<SelectionValue?>, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = _AnySelectionAdapter(
            get: { selection.wrappedValue.map(AnyHashable.init) },
            set: { any in
                selection.wrappedValue = any.base as? SelectionValue
            }
        )
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let source = ctx.buildChild(content)
        let tabs = _collectTabEntries(from: source)
        guard !tabs.isEmpty else { return source }

        let selectedValue = selection?.get()
        let resolvedIndex: Int = {
            if let selectedValue, let idx = tabs.firstIndex(where: { $0.value == selectedValue }) {
                return idx
            }
            return Swift.min(Swift.max(0, localSelectionIndex), tabs.count - 1)
        }()

        if let selectedValue = tabs[resolvedIndex].value, selection?.get() != selectedValue {
            selection?.set(selectedValue)
        }

        var tabButtons: [_VNode] = []
        tabButtons.reserveCapacity(tabs.count)
        let tint = (_UIRuntime._currentEnvironment ?? runtime._baseEnvironment).tint ?? .accentColor

        for (idx, tab) in tabs.enumerated() {
            let path = ctx.path + [20_000 + idx]
            let actionID = runtime._registerAction({
                runtime._setFocus(path: path)
                if let value = tab.value {
                    selection?.set(value)
                } else {
                    localSelectionIndex = idx
                }
            }, path: actionScopePath)
            runtime._registerFocusable(path: path, activate: actionID)

            let title = idx == resolvedIndex ? "[\(tab.label)]" : tab.label
            let labelNode: _VNode = idx == resolvedIndex
                ? .style(fg: tint, bg: nil, child: .text(title))
                : .text(title)
            tabButtons.append(.button(id: actionID, isFocused: runtime._isFocused(path: path), label: labelNode))
        }

        return .stack(axis: .vertical, spacing: 1, children: [
            .stack(axis: .horizontal, spacing: 1, children: tabButtons),
            tabs[resolvedIndex].content,
        ])
    }
}

private func _collectTabEntries(from node: _VNode) -> [_TabEntry] {
    let topLevel = _flatten(node)
    var entries: [_TabEntry] = []
    entries.reserveCapacity(topLevel.count)

    for child in topLevel {
        if case .tagged(let value, let labelNode) = child {
            let extracted = _stripTabItemLabel(from: labelNode)
            entries.append(_TabEntry(
                value: value,
                label: extracted.label ?? String(describing: value),
                content: extracted.content
            ))
            continue
        }

        let extracted = _stripTabItemLabel(from: child)
        if let label = extracted.label {
            entries.append(_TabEntry(value: nil, label: label, content: extracted.content))
        } else {
            entries.append(_TabEntry(value: nil, label: "Tab", content: child))
        }
    }

    return entries
}

private func _stripTabItemLabel(from node: _VNode) -> (content: _VNode, label: String?) {
    switch node {
    case .overlay(let child, let overlay):
        if case .tagged(let v, _) = overlay, let tag = v.base as? _TabItemLabelTag {
            return (child, tag.text)
        }
        return (node, nil)
    default:
        return (node, nil)
    }
}

public extension View {
    func tabItem<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        _TabItem(content: AnyView(self), label: AnyView(label()))
    }
}

private struct _TabItem: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let label: AnyView

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let childNode = ctx.buildChild(content)
        let labelText = _menuLabelText(from: ctx.buildChild(label))
        return .overlay(
            child: childNode,
            overlay: .tagged(value: AnyHashable(_TabItemLabelTag(text: labelText)), label: .empty)
        )
    }
}

public struct ZStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let alignment: Alignment
    public let content: Content

    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // Keep ZStack as a single node so parent stacks don't flatten it into siblings.
        let child = ctx.buildChild(content)
        return .zstack(children: _flatten(child))
    }
}

public struct Group<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.buildChild(content)
    }
}

public struct GroupBox<Label: View, Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let label: Label
    let content: Content

    public init(@ViewBuilder content: () -> Content) where Label == EmptyView {
        self.label = EmptyView()
        self.content = content()
    }

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.buildChild(
            VStack(alignment: .leading, spacing: 1) {
                label
                content
            }
            .padding(1)
        )
    }
}

public struct LabeledContent: View, _PrimitiveView {
    public typealias Body = Never

    let label: String
    let value: String

    public init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.buildChild(
            HStack(spacing: 1) {
                Text(label)
                Spacer()
                Text(value)
            }
        )
    }
}

public struct ContentUnavailableView<Description: View>: View, _PrimitiveView {
    public typealias Body = Never

    let title: String
    let systemImage: String
    let description: Description

    public init(_ title: String, systemImage: String, description: Description) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.buildChild(
            VStack(spacing: 1) {
                Image(systemName: systemImage)
                Text(title)
                description
            }
            .padding(1)
        )
    }
}

public struct Section<Parent: View, Content: View, Footer: View>: View, _PrimitiveView {
    public typealias Body = Never

    let header: Parent
    let content: Content
    let footer: Footer

    public init(@ViewBuilder content: () -> Content) where Parent == EmptyView, Footer == EmptyView {
        self.header = EmptyView()
        self.content = content()
        self.footer = EmptyView()
    }

    public init(header: Parent, @ViewBuilder content: () -> Content) where Footer == EmptyView {
        self.header = header
        self.content = content()
        self.footer = EmptyView()
    }

    public init(header: Parent, footer: Footer, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
        self.footer = footer
    }

    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) where Footer == EmptyView {
        self.header = header()
        self.content = content()
        self.footer = EmptyView()
    }

    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent, @ViewBuilder footer: () -> Footer) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        ctx.buildChild(
            VStack(spacing: 0) {
                header
                content
                footer
            }
        )
    }
}

public struct Table<Data: RandomAccessCollection, ID: Hashable, RowContent: View>: View, _PrimitiveView {
    public typealias Body = Never

    let data: Data
    let id: KeyPath<Data.Element, ID>
    let rowContent: (Data.Element) -> RowContent

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) {
        self.data = data
        self.id = id
        self.rowContent = rowContent
    }

    public init(_ data: Data, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Data.Element: Identifiable, ID == Data.Element.ID {
        self.data = data
        self.id = \.id
        self.rowContent = rowContent
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // Placeholder: render as a List-style scrollable set of rows.
        ctx.buildChild(
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(data, id: id, content: rowContent)
                }
            }
        )
    }
}

public struct VStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let spacing: Int
    public let content: Content

    public init(spacing: Int = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        let s = Int(spacing ?? 0)
        self.spacing = s
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let child = ctx.buildChild(content)
        return .stack(axis: .vertical, spacing: spacing, children: _flatten(child))
    }
}

public struct LazyVStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // We don't currently implement laziness/virtualization; render as a regular VStack.
        ctx.buildChild(VStack(alignment: alignment, spacing: spacing) { content })
    }
}

public struct HStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let spacing: Int
    public let content: Content

    public init(spacing: Int = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        let s = Int(spacing ?? 0)
        self.spacing = s
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let child = ctx.buildChild(content)
        return .stack(axis: .horizontal, spacing: spacing, children: _flatten(child))
    }
}

public enum ButtonRole: Hashable, Sendable {
    case destructive
    case cancel
}

public struct Button<Label: View>: View, _PrimitiveView {
    public typealias Body = Never

    let action: () -> Void
    let actionScopePath: [Int]
    let role: ButtonRole?
    let label: Label

    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.actionScopePath = _UIRuntime._currentPath ?? []
        self.role = nil
        self.label = label()
    }

    public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.actionScopePath = _UIRuntime._currentPath ?? []
        self.role = role
        self.label = label()
    }

    public init(_ title: String, action: @escaping () -> Void) where Label == Text {
        self.action = action
        self.actionScopePath = _UIRuntime._currentPath ?? []
        self.role = nil
        self.label = Text(title)
    }

    public init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) where Label == Text {
        self.action = action
        self.actionScopePath = _UIRuntime._currentPath ?? []
        self.role = role
        self.label = Text(title)
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime

        if let captureID = _UIRuntime._currentMenuCaptureID {
            let labelNode = ctx.buildChild(label)
            let text = _menuLabelText(from: labelNode)
            runtime._registerMenuCaptureItem(
                _UIRuntime._MenuCaptureItem(label: text, actionScopePath: actionScopePath, action: action),
                captureID: captureID
            )
            return .empty
        }

        guard _UIRuntime._hitTestingEnabled else {
            return ctx.buildChild(label)
        }

        let controlPath = ctx.path
        let isFocused = runtime._isFocused(path: controlPath)
        let id = runtime._registerAction({
            runtime._setFocus(path: controlPath)
            action()
        }, path: actionScopePath)
        runtime._registerFocusable(path: controlPath, activate: id)
        var labelNode = ctx.buildChild(label)
        if role == .destructive {
            labelNode = .style(fg: .red, bg: nil, child: labelNode)
        }
        return .button(id: id, isFocused: isFocused, label: labelNode)
    }
}

public struct Label<Title: View, Icon: View>: View, _PrimitiveView {
    public typealias Body = Never

    let title: Title
    let icon: Icon

    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }

    public init(_ title: String, systemImage: String) where Title == Text, Icon == Image {
        self.title = Text(title)
        self.icon = Image(systemName: systemImage)
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let iconNode = ctx.buildChild(icon)
        let titleNode = ctx.buildChild(title)
        return .stack(axis: .horizontal, spacing: 1, children: [iconNode, titleNode])
    }
}

public struct Toggle<Label: View>: View, _PrimitiveView {
    public typealias Body = Never

    let isOn: Binding<Bool>
    let label: Label
    let actionScopePath: [Int]

    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self.isOn = isOn
        self.label = label()
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    public init(_ title: String, isOn: Binding<Bool>) where Label == Text {
        self.isOn = isOn
        self.label = Text(title)
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let controlPath = ctx.path
        let isFocused = runtime._isFocused(path: controlPath)
        let id = runtime._registerAction({
            runtime._setFocus(path: controlPath)
            isOn.wrappedValue.toggle()
        }, path: actionScopePath)
        runtime._registerFocusable(path: controlPath, activate: id)
        let labelNode = ctx.buildChild(label)
        return .toggle(id: id, isFocused: isFocused, isOn: isOn.wrappedValue, label: labelNode)
    }
}

public struct TextField: View, _PrimitiveView {
    public typealias Body = Never

    let placeholder: String
    let text: Binding<String>
    let actionScopePath: [Int]

    public init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self.text = text
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    public init(_ placeholder: String, text: Binding<String>, prompt: Text?) {
        self.placeholder = prompt?.content ?? placeholder
        self.text = text
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let controlPath = ctx.path
        let isFocused = runtime._isFocused(path: controlPath)
        var cursor = runtime._getTextCursor(path: controlPath)

        // Focus action (place cursor at end if this field hasn't been edited yet).
        let id = runtime._registerAction({
            runtime._ensureTextCursorAtEndIfUnset(path: controlPath, text: text.wrappedValue)
            runtime._setFocus(path: controlPath)
        }, path: actionScopePath)
        runtime._registerFocusable(path: controlPath, activate: id)

        // Keyboard handler. Keep it intentionally small for now.
        runtime._registerTextEditor(path: controlPath, _TextEditor(handle: { ev in
            // Cursor in scalar space (works for ASCII and most simple scalars; not grapheme-perfect).
            var scalars = Array(text.wrappedValue.unicodeScalars)
            cursor = min(max(0, cursor), scalars.count)

            func save() {
                text.wrappedValue = String(String.UnicodeScalarView(scalars))
                runtime._setTextCursor(path: controlPath, cursor)
            }

            switch ev {
            case .left:
                cursor = max(0, cursor - 1)
                runtime._setTextCursor(path: controlPath, cursor)
            case .right:
                cursor = min(scalars.count, cursor + 1)
                runtime._setTextCursor(path: controlPath, cursor)
            case .home:
                cursor = 0
                runtime._setTextCursor(path: controlPath, cursor)
            case .end:
                cursor = scalars.count
                runtime._setTextCursor(path: controlPath, cursor)
            case .killToEnd:
                guard cursor < scalars.count else { return }
                scalars.removeSubrange(cursor..<scalars.count)
                save()
            case .backspace:
                guard cursor > 0, !scalars.isEmpty else { return }
                scalars.remove(at: cursor - 1)
                cursor -= 1
                save()
            case .delete:
                guard cursor < scalars.count else { return }
                scalars.remove(at: cursor)
                save()
            case .char(let codepoint):
                guard let scalar = UnicodeScalar(codepoint) else { return }
                let v = scalar.value
                guard v >= 32 && v != 127 else { return }
                scalars.insert(scalar, at: cursor)
                cursor += 1
                save()
            }
        }))

        return .textField(
            id: id,
            placeholder: placeholder,
            text: text.wrappedValue,
            cursor: runtime._getTextCursor(path: controlPath),
            isFocused: isFocused
        )
    }
}

public struct SecureField: View, _PrimitiveView {
    public typealias Body = Never

    let placeholder: String
    let text: Binding<String>

    public init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self.text = text
    }

    public init(_ placeholder: String, text: Binding<String>, prompt: Text?) {
        self.placeholder = prompt?.content ?? placeholder
        self.text = text
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let node = ctx.buildChild(TextField(placeholder, text: text))
        if case .textField(let id, let placeholder, _, let cursor, let isFocused) = node {
            let masked = String(repeating: "•", count: text.wrappedValue.count)
            return .textField(id: id, placeholder: placeholder, text: masked, cursor: cursor, isFocused: isFocused)
        }
        return node
    }
}

public struct Picker<SelectionValue: Hashable>: View, _PrimitiveView {
    public typealias Body = Never

    let selection: Binding<SelectionValue>
    let title: String
    let options: [(SelectionValue, String)]?
    let content: AnyView?
    let actionScopePath: [Int]

    public init(_ title: String, selection: Binding<SelectionValue>, options: [(SelectionValue, String)]) {
        self.title = title
        self.selection = selection
        self.options = options
        self.content = nil
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    public init<Content: View>(_ title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.selection = selection
        self.options = nil
        self.content = AnyView(content())
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let controlPath = ctx.path

        let values: [SelectionValue]
        let labelsText: [String]
        if let options = options {
            values = options.map { $0.0 }
            labelsText = options.map { $0.1 }
        } else if let content {
            let node = ctx.buildChild(content)
            let collected = _collectTaggedPickerOptions(node: node, valueType: SelectionValue.self)
            values = collected.values
            labelsText = collected.labels
        } else {
            values = []
            labelsText = []
        }

        let safeValues = values.isEmpty ? [selection.wrappedValue] : values
        let safeLabels = labelsText.isEmpty ? [String(describing: selection.wrappedValue)] : labelsText
        let selectedIndex = safeValues.firstIndex(of: selection.wrappedValue) ?? 0
        let isExpanded = runtime._isPickerExpanded(path: controlPath)

        // Paths for focusability inside the picker: header is 0, options are 1...N.
        let headerPath = controlPath + [0]

        // Header button.
        let valueText = (selectedIndex < safeLabels.count) ? safeLabels[selectedIndex] : String(describing: selection.wrappedValue)
        let headerIsFocused = runtime._isFocused(path: headerPath)
        let toggleExpandedID = runtime._registerAction({
            runtime._setFocus(path: headerPath)
            if runtime._isPickerExpanded(path: controlPath) {
                runtime._closePicker(path: controlPath)
            } else {
                runtime._openPicker(path: controlPath)
                let preferred = min(max(0, selectedIndex), max(0, safeValues.count - 1))
                runtime._setFocus(path: controlPath + [1 + preferred])
            }
        }, path: actionScopePath)
        runtime._registerFocusable(path: headerPath, activate: toggleExpandedID)

        // Dropdown options as buttons beneath.
        var items: [(id: _ActionID, isSelected: Bool, isFocused: Bool, label: String)] = []
        if isExpanded {
            items.reserveCapacity(safeValues.count)
            for (idx, value) in safeValues.enumerated() {
                let optionPath = controlPath + [1 + idx]
                let optionIsFocused = runtime._isFocused(path: optionPath)
                let optionID = runtime._registerAction({
                    runtime._setFocus(path: optionPath)
                    selection.wrappedValue = value
                    runtime._closePicker(path: controlPath)
                    runtime._setFocus(path: headerPath)
                }, path: actionScopePath)
                runtime._registerFocusable(path: optionPath, activate: optionID)
                let label = (idx < safeLabels.count) ? safeLabels[idx] : String(describing: value)
                items.append((id: optionID, isSelected: value == selection.wrappedValue, isFocused: optionIsFocused, label: label))
            }
        }

        return .menu(
            id: toggleExpandedID,
            isFocused: headerIsFocused,
            isExpanded: isExpanded,
            title: title,
            value: valueText,
            items: items
        )
    }
}

public struct Menu<Content: View, Label: View>: View, _PrimitiveView {
    public typealias Body = Never

    let content: Content
    let label: Label
    let actionScopePath: [Int]

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        guard _UIRuntime._hitTestingEnabled else {
            return ctx.buildChild(label)
        }

        let runtime = ctx.runtime
        let controlPath = ctx.path
        let isExpanded = runtime._isPickerExpanded(path: controlPath)

        // Paths for focusability: header is 0, items are 1...N.
        let headerPath = controlPath + [0]
        let headerIsFocused = runtime._isFocused(path: headerPath)

        let labelText: String = {
            var childCtx = _BuildContext(runtime: runtime, path: headerPath, nextChildIndex: 0)
            let node = _BuildContext.withRuntime(runtime, path: childCtx.path) {
                OmniUICore._makeNode(label, &childCtx)
            }
            let t = _menuLabelText(from: node)
            return t.isEmpty ? "Menu" : t
        }()

        let toggleExpandedID = runtime._registerAction({
            runtime._setFocus(path: headerPath)
            if runtime._isPickerExpanded(path: controlPath) {
                runtime._closePicker(path: controlPath)
            } else {
                runtime._openPicker(path: controlPath)
                runtime._setFocus(path: controlPath + [1])
            }
        }, path: actionScopePath)
        runtime._registerFocusable(path: headerPath, activate: toggleExpandedID)

        var items: [(id: _ActionID, isSelected: Bool, isFocused: Bool, label: String)] = []
        if isExpanded {
            // Collect nested Buttons into a list of menu items.
            let captureID = runtime._beginMenuCapture()
            _UIRuntime.$_currentMenuCaptureID.withValue(captureID) {
                var contentCtx = _BuildContext(runtime: runtime, path: controlPath + [1], nextChildIndex: 0)
                _ = _BuildContext.withRuntime(runtime, path: contentCtx.path) {
                    OmniUICore._makeNode(content, &contentCtx)
                }
            }
            let captured = runtime._endMenuCapture(captureID)

            items.reserveCapacity(captured.count)
            for (idx, entry) in captured.enumerated() {
                let optionPath = controlPath + [1 + idx]
                let optionIsFocused = runtime._isFocused(path: optionPath)
                let optionID = runtime._registerAction({
                    runtime._setFocus(path: optionPath)
                    runtime._closePicker(path: controlPath)
                    runtime._setFocus(path: headerPath)
                    entry.action()
                }, path: entry.actionScopePath)
                runtime._registerFocusable(path: optionPath, activate: optionID)
                items.append((id: optionID, isSelected: false, isFocused: optionIsFocused, label: entry.label))
            }
        }

        return .menu(
            id: toggleExpandedID,
            isFocused: headerIsFocused,
            isExpanded: isExpanded,
            title: "",
            value: labelText,
            items: items
        )
    }
}

private func _collectTaggedPickerOptions<T: Hashable>(node: _VNode, valueType: T.Type) -> (values: [T], labels: [String]) {
    var values: [T] = []
    var labels: [String] = []

    func labelText(_ n: _VNode) -> String? {
        switch n {
        case .text(let s):
            return s
        case .textStyled(_, let child):
            return labelText(child)
        case .style(_, _, let child):
            return labelText(child)
        case .contentShapeRect(let child):
            return labelText(child)
        case .clip(_, let child):
            return labelText(child)
        case .shadow(let child, _, _, _, _):
            return labelText(child)
        case .group(let nodes):
            // Prefer first text we find.
            for c in nodes {
                if let t = labelText(c) { return t }
            }
            return nil
        case .stack(_, _, let children):
            for c in children {
                if let t = labelText(c) { return t }
            }
            return nil
        case .zstack(let children):
            for c in children {
                if let t = labelText(c) { return t }
            }
            return nil
        default:
            return nil
        }
    }

    func walk(_ n: _VNode) {
        switch n {
        case .tagged(let v, let label):
            if let tv = v.base as? T {
                values.append(tv)
                labels.append(labelText(label) ?? String(describing: tv))
            }
        case .contentShapeRect(let child):
            walk(child)
        case .clip(_, let child):
            walk(child)
        case .shadow(let child, _, _, _, _):
            walk(child)
        case .group(let nodes):
            for c in nodes { walk(c) }
        case .stack(_, _, let children):
            for c in children { walk(c) }
        case .zstack(let children):
            for c in children { walk(c) }
        case .background(let child, let bg):
            // Picker content doesn't use this typically; but walk both to be safe.
            walk(bg)
            walk(child)
        case .overlay(let child, let ov):
            walk(child)
            walk(ov)
        case .textStyled(_, let child):
            walk(child)
        case .style(_, _, let child):
            walk(child)
        default:
            break
        }
    }

    walk(node)
    return (values, labels)
}

public extension View {
    func padding(_ amount: Int = 1) -> some View {
        _EdgePadding(content: AnyView(self), top: amount, leading: amount, bottom: amount, trailing: amount)
    }
}

// Int-based padding lives here for convenience; edge-based padding is implemented in `Modifiers.swift`.
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

func _flatten(_ node: _VNode) -> [_VNode] {
    switch node {
    case .empty:
        return []
    case .group(let nodes):
        return nodes.flatMap(_flatten)
    default:
        return [node]
    }
}

private func _menuLabelText(from node: _VNode) -> String {
    var parts: [String] = []

    func walk(_ n: _VNode) {
        switch n {
        case .text(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { parts.append(t) }
        case .image:
            // Ignore icon-only nodes; the renderers already handle images.
            break
        case .textStyled(_, let child):
            walk(child)
        case .style(_, _, let child):
            walk(child)
        case .contentShapeRect(let child):
            walk(child)
        case .clip(_, let child):
            walk(child)
        case .shadow(let child, _, _, _, _):
            walk(child)
        case .background(let child, _):
            walk(child)
        case .overlay(let child, _):
            walk(child)
        case .frame(_, _, _, _, _, _, let child):
            walk(child)
        case .edgePadding(_, _, _, _, let child):
            walk(child)
        case .tagged(_, let label):
            walk(label)
        case .group(let nodes):
            for c in nodes { walk(c) }
        case .stack(_, _, let children):
            for c in children { walk(c) }
        case .zstack(let children):
            for c in children { walk(c) }
        default:
            break
        }
    }

    walk(node)
    return parts.joined(separator: " ")
}
