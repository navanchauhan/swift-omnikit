import Foundation

public struct SemanticSnapshot: Sendable {
    public let root: SemanticNode
    public let size: _Size
    public let focusedActionID: Int?
    public let activeMenu: _MenuInfo?
    public let activePicker: _PickerInfo?
    public let activeTextField: _TextFieldInfo?

    public init(
        root: SemanticNode,
        size: _Size,
        focusedActionID: Int?,
        activeMenu: _MenuInfo?,
        activePicker: _PickerInfo?,
        activeTextField: _TextFieldInfo?
    ) {
        self.root = root
        self.size = size
        self.focusedActionID = focusedActionID
        self.activeMenu = activeMenu
        self.activePicker = activePicker
        self.activeTextField = activeTextField
    }
}

public struct SemanticNode: Sendable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case empty
        case group
        case text(String)
        case image(String)
        case stack(axis: SemanticAxis, spacing: Int)
        case zstack
        case spacer
        case scroll(axis: SemanticAxis, actionID: Int, offset: Int)
        case button(actionID: Int, isFocused: Bool)
        case toggle(actionID: Int, isFocused: Bool, isOn: Bool)
        case textField(actionID: Int, placeholder: String, text: String, cursor: Int, isFocused: Bool, isSecure: Bool)
        case textEditor(actionID: Int, text: String, cursor: Int, isFocused: Bool)
        case menu(actionID: Int, title: String, value: String, isExpanded: Bool)
        case disabledButton(label: String)
        case disabledToggle(label: String, isOn: Bool)
        case disabledTextField(placeholder: String, text: String, isSecure: Bool)
        case disabledMenu(title: String, value: String)
        case progress(label: String, fraction: Double?)
        case slider(label: String, value: Double, lowerBound: Double, upperBound: Double, step: Double?, decrementActionID: Int?, incrementActionID: Int?)
        case stepper(label: String, value: Double?, decrementActionID: Int?, incrementActionID: Int?)
        case datePicker(label: String, value: String, timestamp: Double, setActionID: Int?, decrementActionID: Int?, incrementActionID: Int?)
        case segmentedControl(title: String, selectedIndex: Int)
        case divider
        case drawingIsland(SemanticDrawingKind)
        case container(SemanticContainerRole)
        case modifier(SemanticModifier)
    }

    public let id: String
    public let kind: Kind
    public let children: [SemanticNode]

    public init(id: String, kind: Kind, children: [SemanticNode] = []) {
        self.id = id
        self.kind = kind
        self.children = children
    }
}

public struct SemanticChange: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case inserted
        case removed
        case updated
        case childrenReordered
    }

    public let id: String
    public let kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

public enum SemanticDiff {
    public static func changes(from previous: SemanticSnapshot, to next: SemanticSnapshot) -> [SemanticChange] {
        changes(from: previous.root, to: next.root)
    }

    public static func changes(from previous: SemanticNode, to next: SemanticNode) -> [SemanticChange] {
        var previousByID: [String: SemanticNode] = [:]
        var nextByID: [String: SemanticNode] = [:]
        index(previous, into: &previousByID)
        index(next, into: &nextByID)

        let previousIDs = Set(previousByID.keys)
        let nextIDs = Set(nextByID.keys)

        var changes: [SemanticChange] = []
        for id in nextIDs.subtracting(previousIDs).sorted() {
            changes.append(SemanticChange(id: id, kind: .inserted))
        }
        for id in previousIDs.subtracting(nextIDs).sorted() {
            changes.append(SemanticChange(id: id, kind: .removed))
        }
        for id in previousIDs.intersection(nextIDs).sorted() {
            guard let previousNode = previousByID[id], let nextNode = nextByID[id] else { continue }
            if previousNode.kind != nextNode.kind {
                changes.append(SemanticChange(id: id, kind: .updated))
            } else if previousNode.children.map(\.id) != nextNode.children.map(\.id) {
                changes.append(SemanticChange(id: id, kind: .childrenReordered))
            }
        }
        return changes
    }

    private static func index(_ node: SemanticNode, into nodes: inout [String: SemanticNode]) {
        nodes[node.id] = node
        for child in node.children {
            index(child, into: &nodes)
        }
    }
}

public enum SemanticAxis: Sendable, Equatable {
    case horizontal
    case vertical
}

public enum SemanticDrawingKind: Sendable, Equatable {
    case shape(String, fill: String?, stroke: String?)
    case gradient
    case canvas
}

public enum SemanticContainerRole: String, Sendable, Equatable {
    case form
    case list
    case lazyVStack
    case navigationStack
    case navigationSplitView
}

public enum SemanticModifier: Sendable, Equatable {
    case foreground(String)
    case background(String)
    case frame(width: Int?, height: Int?, minWidth: Int?, maxWidth: Int?, minHeight: Int?, maxHeight: Int?)
    case padding(top: Int, leading: Int, bottom: Int, trailing: Int)
    case opacity(Double)
    case offset(x: Int, y: Int)
    case clip(String)
    case shadow(color: String, radius: Int, x: Int, y: Int)
    case badge(String)
    case glass(String)
    case crt(String)
    case accessibilityLabel(String)
    case accessibilityIdentifier(String)
    case noOp(String)
}

enum _DisabledControlRole: Hashable {
    case button
    case toggle(isOn: Bool)
    case textField(placeholder: String, text: String, isSecure: Bool)
    case menu(title: String, value: String)
}

enum SemanticLowerer {
    static func lower(_ node: _VNode, path: String = "0") -> SemanticNode {
        switch node {
        case .empty:
            return SemanticNode(id: path, kind: .empty)
        case .group(let children):
            return SemanticNode(id: path, kind: .group, children: lower(children, path: path))
        case .text(let text), .truncatedText(let text, _):
            return SemanticNode(id: path, kind: .text(text))
        case .styledText(let segments):
            return SemanticNode(id: path, kind: .text(segments.map(\.content).joined()))
        case .image(let name):
            return SemanticNode(id: path, kind: .image(name))
        case .stack(let axis, let spacing, let children):
            return SemanticNode(id: path, kind: .stack(axis: axis.semantic, spacing: spacing), children: lower(children, path: path))
        case .zstack(let children):
            return SemanticNode(id: path, kind: .zstack, children: lower(children, path: path))
        case .spacer:
            return SemanticNode(id: path, kind: .spacer)
        case .button(let id, let focused, let label):
            return SemanticNode(id: path, kind: .button(actionID: id.raw, isFocused: focused), children: [lower(label, path: path + ".label")])
        case .tapTarget(let id, let child), .gestureTarget(let id, let child):
            return SemanticNode(id: path, kind: .button(actionID: id.raw, isFocused: false), children: [lower(child, path: path + ".label")])
        case .toggle(let id, let focused, let isOn, let label):
            return SemanticNode(id: path, kind: .toggle(actionID: id.raw, isFocused: focused, isOn: isOn), children: [lower(label, path: path + ".label")])
        case .textField(let id, let placeholder, let text, let cursor, let focused, let isSecure, _):
            return SemanticNode(id: path, kind: .textField(actionID: id.raw, placeholder: placeholder, text: text, cursor: cursor, isFocused: focused, isSecure: isSecure))
        case .scrollView(let id, _, _, let axis, let offset, let content):
            return SemanticNode(id: path, kind: .scroll(axis: axis.semantic, actionID: id.raw, offset: offset), children: [lower(content, path: path + ".content")])
        case .menu(let id, _, let expanded, let title, let value, let items):
            let itemNodes = items.enumerated().map { idx, item in
                SemanticNode(id: "\(path).item\(idx)", kind: .button(actionID: item.id.raw, isFocused: item.isFocused), children: [
                    SemanticNode(id: "\(path).item\(idx).label", kind: .text(item.label))
                ])
            }
            return SemanticNode(id: path, kind: .menu(actionID: id.raw, title: title, value: value, isExpanded: expanded), children: itemNodes)
        case .tagged(let value, let child):
            if let role = value.base as? _DisabledControlRole {
                let lowered = lower(child, path: path + ".content")
                let label = disabledControlLabel(in: lowered)
                switch role {
                case .button:
                    return SemanticNode(id: path, kind: .disabledButton(label: label), children: [lowered])
                case .toggle(let isOn):
                    return SemanticNode(id: path, kind: .disabledToggle(label: label, isOn: isOn), children: [lowered])
                case .textField(let placeholder, let text, let isSecure):
                    return SemanticNode(id: path, kind: .disabledTextField(placeholder: placeholder, text: text, isSecure: isSecure), children: [lowered])
                case .menu(let title, let value):
                    return SemanticNode(id: path, kind: .disabledMenu(title: title, value: value), children: [lowered])
                }
            }
            if let role = value.base as? _SemanticRole, let semanticRole = SemanticContainerRole(rawValue: role.rawValue) {
                return SemanticNode(id: path, kind: .container(semanticRole), children: [lower(child, path: path + ".content")])
            }
            if let label = value.base as? _AccessibilityLabel {
                return SemanticNode(id: path, kind: .modifier(.accessibilityLabel(label.value)), children: [lower(child, path: path + ".content")])
            }
            if let identifier = value.base as? _AccessibilityIdentifier {
                return SemanticNode(id: path, kind: .modifier(.accessibilityIdentifier(identifier.value)), children: [lower(child, path: path + ".content")])
            }
            if let segmented = value.base as? _SegmentedPickerRole {
                return SemanticNode(id: path, kind: .segmentedControl(title: segmented.title, selectedIndex: segmented.selectedIndex), children: [lower(child, path: path + ".content")])
            }
            if let role = value.base as? _TextInputRole, role == .textEditor {
                let lowered = lower(child, path: path + ".content")
                if case .textField(let actionID, _, let text, let cursor, let isFocused, _) = lowered.kind {
                    return SemanticNode(id: path, kind: .textEditor(actionID: actionID, text: text, cursor: cursor, isFocused: isFocused))
                }
                return SemanticNode(id: path, kind: .modifier(.noOp("textEditor")), children: [lowered])
            }
            if let progress = value.base as? _ProgressRole {
                return SemanticNode(id: path, kind: .progress(label: progress.label, fraction: progress.fraction), children: [lower(child, path: path + ".content")])
            }
            if let slider = value.base as? _SliderRole {
                let lowered = lower(child, path: path + ".content")
                let actions = firstActionIDs(in: lowered, limit: 2)
                return SemanticNode(
                    id: path,
                    kind: .slider(
                        label: slider.label,
                        value: slider.value,
                        lowerBound: slider.lowerBound,
                        upperBound: slider.upperBound,
                        step: slider.step,
                        decrementActionID: actions.first,
                        incrementActionID: actions.dropFirst().first
                    ),
                    children: [lowered]
                )
            }
            if let stepper = value.base as? _StepperRole {
                let lowered = lower(child, path: path + ".content")
                let actions = firstActionIDs(in: lowered, limit: 2)
                return SemanticNode(
                    id: path,
                    kind: .stepper(
                        label: stepper.label,
                        value: stepper.value,
                        decrementActionID: actions.first,
                        incrementActionID: actions.dropFirst().first
                    ),
                    children: [lowered]
                )
            }
            if let datePicker = value.base as? _DatePickerRole {
                let lowered = lower(child, path: path + ".content")
                let actions = firstActionIDs(in: lowered, limit: 2)
                return SemanticNode(
                    id: path,
                    kind: .datePicker(
                        label: datePicker.label,
                        value: datePicker.value,
                        timestamp: datePicker.timestamp,
                        setActionID: datePicker.setActionID,
                        decrementActionID: actions.first,
                        incrementActionID: actions.dropFirst().first
                    ),
                    children: [lowered]
                )
            }
            return lower(child, path: path + ".content")
        case .divider:
            return SemanticNode(id: path, kind: .divider)
        case .shape(let shape):
            return SemanticNode(
                id: path,
                kind: .drawingIsland(.shape(
                    shape.kind.semanticName,
                    fill: shape.fillColor?.rawValue,
                    stroke: shape.strokeColor?.rawValue
                ))
            )
        case .gradient:
            return SemanticNode(id: path, kind: .drawingIsland(.gradient))
        case .background(let child, let background):
            return SemanticNode(id: path, kind: .modifier(.background("native/adwaita")), children: [lower(background, path: path + ".background"), lower(child, path: path + ".content")])
        case .style(let fg, let bg, let child):
            let mod: SemanticModifier = fg.map { .foreground($0.rawValue) } ?? bg.map { .background($0.rawValue) } ?? .noOp("empty-style")
            return SemanticNode(id: path, kind: .modifier(mod), children: [lower(child, path: path + ".content")])
        case .frame(let w, let h, let minW, let maxW, let minH, let maxH, let child):
            return SemanticNode(id: path, kind: .modifier(.frame(width: w, height: h, minWidth: minW, maxWidth: maxW, minHeight: minH, maxHeight: maxH)), children: [lower(child, path: path + ".content")])
        case .edgePadding(let t, let l, let b, let r, let child):
            return SemanticNode(id: path, kind: .modifier(.padding(top: t, leading: l, bottom: b, trailing: r)), children: [lower(child, path: path + ".content")])
        case .opacity(let alpha, let child):
            return SemanticNode(id: path, kind: .modifier(.opacity(Double(alpha))), children: [lower(child, path: path + ".content")])
        case .offset(let x, let y, let child):
            return SemanticNode(id: path, kind: .modifier(.offset(x: x, y: y)), children: [lower(child, path: path + ".content")])
        case .clip(let kind, let child), .contentShapeRect(let kind, let child):
            return SemanticNode(id: path, kind: .modifier(.clip(kind.semanticName)), children: [lower(child, path: path + ".content")])
        case .shadow(let child, let color, let radius, let x, let y):
            return SemanticNode(id: path, kind: .modifier(.shadow(color: color.name, radius: radius, x: x, y: y)), children: [lower(child, path: path + ".content")])
        case .glass(let style, let shape, let child):
            let descriptor = shape.map { "\(style) in \($0)" } ?? style
            return SemanticNode(id: path, kind: .modifier(.glass(descriptor)), children: [lower(child, path: path + ".content")])
        case .crt(let style, let child):
            return SemanticNode(id: path, kind: .modifier(.crt(style)), children: [lower(child, path: path + ".content")])
        case .badge(let text, let child):
            return SemanticNode(id: path, kind: .modifier(.badge(text)), children: [lower(child, path: path + ".content")])
        case .overlay(let child, let overlay):
            return SemanticNode(id: path, kind: .zstack, children: [lower(child, path: path + ".content"), lower(overlay, path: path + ".overlay")])
        case .modalOverlay(_, _, _, let child):
            return SemanticNode(id: path, kind: .modifier(.background("adw-dialog")), children: [lower(child, path: path + ".content")])
        case .identified(let id, _, let child):
            let stablePath = "\(path)#\(semanticIDComponent(id))"
            var lowered = lower(child, path: stablePath)
            lowered = SemanticNode(id: stablePath, kind: lowered.kind, children: lowered.children)
            return lowered
        default:
            return SemanticNode(id: path, kind: .modifier(.noOp("unsupported")), children: unwrapChildren(node, path: path))
        }
    }

    private static func semanticIDComponent(_ id: AnyHashable) -> String {
        let raw = String(describing: id.base)
        let allowed = raw.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        return String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func disabledControlLabel(in node: SemanticNode) -> String {
        let text = flattenedText(in: node)
            .replacingOccurrences(of: "[x]", with: "")
            .replacingOccurrences(of: "[ ]", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Disabled" : text
    }

    private static func flattenedText(in node: SemanticNode) -> String {
        var parts: [String] = []
        func visit(_ current: SemanticNode) {
            if case .text(let value) = current.kind, !value.isEmpty {
                parts.append(value)
            }
            if case .image(let value) = current.kind {
                parts.append(SFSymbolMap.unicode(for: value) ?? value)
            }
            for child in current.children {
                visit(child)
            }
        }
        visit(node)
        return parts.joined(separator: " ")
    }

    private static func firstActionIDs(in node: SemanticNode, limit: Int) -> [Int] {
        var ids: [Int] = []
        func visit(_ current: SemanticNode) {
            guard ids.count < limit else { return }
            switch current.kind {
            case .button(let actionID, _), .toggle(let actionID, _, _):
                ids.append(actionID)
            case .menu(let actionID, _, _, _):
                ids.append(actionID)
            default:
                break
            }
            for child in current.children {
                visit(child)
            }
        }
        visit(node)
        return ids
    }

    private static func lower(_ children: [_VNode], path: String) -> [SemanticNode] {
        children.enumerated().map { lower($0.element, path: "\(path).\($0.offset)") }
    }

    private static func unwrapChildren(_ node: _VNode, path: String) -> [SemanticNode] {
        switch node {
        case .identified(_, _, let child), .onDelete(_, _, let child), .tagged(_, let child), .hover(_, let child),
             .fixedSize(_, _, let child), .layoutPriority(_, let child), .aspectRatio(_, _, let child),
             .alignmentGuide(_, _, let child), .preferenceNode(_, let child), .rotationEffect(_, let child),
             .textCase(_, let child), .blur(_, let child), .anchorPreference(_, _, _, let child),
             .geometryReaderProxy(_, let child), .textStyled(_, let child), .elevated(_, let child):
            return [lower(child, path: path + ".content")]
        case .viewThatFits(_, let children):
            return lower(children, path: path)
        case .swipeActions(_, _, let actions, let child):
            return [lower(child, path: path + ".content")] + lower(actions, path: path + ".actions")
        case .spacer:
            return [SemanticNode(id: path, kind: .spacer)]
        default:
            return []
        }
    }
}

private extension _Axis {
    var semantic: SemanticAxis { self == .horizontal ? .horizontal : .vertical }
}

private extension _ShapeKind {
    var semanticName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .roundedRectangle: return "roundedRectangle"
        case .circle: return "circle"
        case .ellipse: return "ellipse"
        case .capsule: return "capsule"
        case .path: return "path"
        }
    }
}
