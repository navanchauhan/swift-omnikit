public struct Text: View, _PrimitiveView {
    public typealias Body = Never
    public let content: String

    public init(_ content: String) {
        self.content = content
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

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode { .spacer }
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

        // Click-to-focus so scroll wheels can be routed predictably.
        let id = runtime._registerAction({ runtime._setFocus(path: controlPath) }, path: actionScopePath)
        runtime._registerFocusable(path: controlPath, activate: id)

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

public struct List<Content: View>: View, _PrimitiveView {
    public typealias Body = Never

    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.content = ForEach(data, id: id, content: rowContent)
    }

    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Data.Element: Identifiable, Content == ForEach<Data, Data.Element.ID, RowContent> {
        self.content = ForEach(data, content: rowContent)
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // Minimal: List is a ScrollView + VStack.
        ctx.buildChild(
            ScrollView {
                VStack(spacing: 0) { content }
            }
        )
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

        return .stack(
            axis: .vertical,
            spacing: 1,
            children: _flatten(
                .group([
                    depth > 0
                        ? ctx.buildChild(
                            HStack(spacing: 1) {
                                Button("Back") { runtime._navPop(stackPath: stackPath) }
                                Text("Navigation (\(depth))")
                                Spacer()
                            }
                          )
                        : ctx.buildChild(Text("Navigation")),
                    top.map { ctx.buildChild($0) } ?? ctx.buildChild(content),
                ])
            )
        )
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

    public init(_ title: String, destination: @escaping () -> Destination) where Label == Text {
        self.destination = destination
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

public struct ZStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
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

public struct VStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let spacing: Int
    public let content: Content

    public init(spacing: Int = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let child = ctx.buildChild(content)
        return .stack(axis: .vertical, spacing: spacing, children: _flatten(child))
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

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let child = ctx.buildChild(content)
        return .stack(axis: .horizontal, spacing: spacing, children: _flatten(child))
    }
}

public struct Button<Label: View>: View, _PrimitiveView {
    public typealias Body = Never

    let action: () -> Void
    let actionScopePath: [Int]
    let label: Label

    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.actionScopePath = _UIRuntime._currentPath ?? []
        self.label = label()
    }

    public init(_ title: String, action: @escaping () -> Void) where Label == Text {
        self.action = action
        self.actionScopePath = _UIRuntime._currentPath ?? []
        self.label = Text(title)
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let controlPath = ctx.path
        let isFocused = runtime._isFocused(path: controlPath)
        let id = runtime._registerAction({
            runtime._setFocus(path: controlPath)
            action()
        }, path: actionScopePath)
        runtime._registerFocusable(path: controlPath, activate: id)
        let labelNode = ctx.buildChild(label)
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

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let controlPath = ctx.path
        let isFocused = runtime._isFocused(path: controlPath)

        // Focus action (no-op if already focused).
        let id = runtime._registerAction({ runtime._setFocus(path: controlPath) }, path: actionScopePath)
        runtime._registerFocusable(path: controlPath, activate: id)

        // Keyboard handler. Keep it intentionally small for now.
        runtime._registerTextEditor(path: controlPath, _TextEditor(handle: { codepoint in
            // Backspace (ASCII 8, also synthesized NCKEY_BACKSPACE maps there via notcurses).
            if codepoint == 8 {
                if !text.wrappedValue.isEmpty { text.wrappedValue.removeLast() }
                return
            }
            // Basic printable range.
            guard let scalar = UnicodeScalar(codepoint), scalar.isASCII else { return }
            let v = scalar.value
            guard v >= 32 && v != 127 else { return }
            text.wrappedValue.append(Character(scalar))
        }))

        return .textField(
            id: id,
            placeholder: placeholder,
            text: text.wrappedValue,
            isFocused: isFocused
        )
    }
}

public struct Picker<SelectionValue: Hashable>: View, _PrimitiveView {
    public typealias Body = Never

    let selection: Binding<SelectionValue>
    let title: String
    let options: [(SelectionValue, String)]
    let actionScopePath: [Int]

    public init(_ title: String, selection: Binding<SelectionValue>, options: [(SelectionValue, String)]) {
        self.title = title
        self.selection = selection
        self.options = options
        self.actionScopePath = _UIRuntime._currentPath ?? []
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let runtime = ctx.runtime
        let controlPath = ctx.path

        let values = options.map { $0.0 }
        let labelsText = options.map { $0.1 }
        let selectedIndex = values.firstIndex(of: selection.wrappedValue) ?? 0
        let isExpanded = runtime._isPickerExpanded(path: controlPath)

        // Paths for focusability inside the picker: header is 0, options are 1...N.
        let headerPath = controlPath + [0]

        // Header button.
        let valueText = (selectedIndex < labelsText.count) ? labelsText[selectedIndex] : String(describing: selection.wrappedValue)
        let headerIsFocused = runtime._isFocused(path: headerPath)
        let toggleExpandedID = runtime._registerAction({
            runtime._setFocus(path: headerPath)
            if runtime._isPickerExpanded(path: controlPath) {
                runtime._closePicker(path: controlPath)
            } else {
                runtime._openPicker(path: controlPath)
                let preferred = min(max(0, selectedIndex), max(0, values.count - 1))
                runtime._setFocus(path: controlPath + [1 + preferred])
            }
        }, path: actionScopePath)
        runtime._registerFocusable(path: headerPath, activate: toggleExpandedID)

        // Dropdown options as buttons beneath.
        var items: [(id: _ActionID, isSelected: Bool, isFocused: Bool, label: String)] = []
        if isExpanded {
            items.reserveCapacity(values.count)
            for (idx, value) in values.enumerated() {
                let optionPath = controlPath + [1 + idx]
                let optionIsFocused = runtime._isFocused(path: optionPath)
                let optionID = runtime._registerAction({
                    runtime._setFocus(path: optionPath)
                    selection.wrappedValue = value
                    runtime._closePicker(path: controlPath)
                    runtime._setFocus(path: headerPath)
                }, path: actionScopePath)
                runtime._registerFocusable(path: optionPath, activate: optionID)
                items.append((id: optionID, isSelected: value == selection.wrappedValue, isFocused: optionIsFocused, label: labelsText[idx]))
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

// (Tag extraction support will be reintroduced once we replace the recursive VNode tagging approach.)

public extension View {
    func padding(_ amount: Int = 1) -> some View {
        Padding(amount: amount, content: AnyView(self))
    }
}

public struct Padding: View, _PrimitiveView {
    public typealias Body = Never
    let amount: Int
    let content: AnyView

    init(amount: Int, content: AnyView) {
        self.amount = amount
        self.content = content
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .padding(amount, ctx.buildChild(content))
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
