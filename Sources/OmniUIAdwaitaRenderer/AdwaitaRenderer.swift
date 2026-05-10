import CAdwaita
import Foundation
import OmniUICore

private let adwaitaCommandActionOffset = 1_000_000
private let adwaitaSettingsActionOffset = 2_000_000

public enum OmniUIAdwaitaRendererError: Error {
    case unableToCreateApplication
    case unableToCreateNode(String)
}

public final class AdwaitaApp<Root: View>: @unchecked Sendable {
    private let appID: String
    private let title: String
    private let root: @MainActor () -> Root
    private let settings: (@MainActor () -> AnyView)?
    private let commands: (@MainActor () -> AnyView)?
    private let runtime = _UIRuntime()
    private let settingsRuntime = _UIRuntime()
    private let commandRuntime = _UIRuntime()
    private let size: _Size

    public init(
        appID: String = "dev.omnikit.KitchenSinkAdwaita",
        title: String = "OmniUI Adwaita",
        size: _Size = _Size(width: 120, height: 42),
        settings: (@MainActor () -> AnyView)? = nil,
        commands: (@MainActor () -> AnyView)? = nil,
        @ViewBuilder root: @escaping @MainActor () -> Root
    ) {
        self.appID = appID
        self.title = title
        self.size = size
        self.settings = settings
        self.commands = commands
        self.root = root
    }

    @MainActor
    public func run() async throws {
        let box = Unmanaged.passRetained(CallbackBox(runtime: runtime, settingsRuntime: settingsRuntime, commandRuntime: commandRuntime, rerender: {}))
        var cApp: OpaquePointer?
        let callback: omni_adw_action_callback = { actionID, context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            let rawID = Int(actionID)
            if rawID >= adwaitaSettingsActionOffset {
                box.settingsRuntime.invokeActionByRawID(rawID - adwaitaSettingsActionOffset)
            } else if rawID >= adwaitaCommandActionOffset {
                box.commandRuntime.invokeActionByRawID(rawID - adwaitaCommandActionOffset)
            } else {
                box.runtime.invokeActionByRawID(rawID)
            }
            box.rerender()
        }
        let textCallback: omni_adw_text_callback = { actionID, text, context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            let rawID = Int(actionID)
            let next = text.map(String.init(cString:)) ?? ""
            if rawID >= adwaitaSettingsActionOffset {
                let settingsRawID = rawID - adwaitaSettingsActionOffset
                if let timestamp = TimeInterval(next), box.settingsRuntime.setDateForRawActionID(settingsRawID, timestamp: timestamp) {
                    box.rerender()
                    return
                }
                let previous = box.textValuesByActionID[rawID] ?? ""
                box.settingsRuntime.replaceTextForRawActionID(settingsRawID, previous: previous, next: next)
                box.textValuesByActionID[rawID] = next
                box.rerender()
                return
            }
            if let timestamp = TimeInterval(next), box.runtime.setDateForRawActionID(rawID, timestamp: timestamp) {
                box.rerender()
                return
            }
            let previous = box.textValuesByActionID[rawID] ?? ""
            box.runtime.replaceTextForRawActionID(rawID, previous: previous, next: next)
            box.textValuesByActionID[rawID] = next
            box.rerender()
        }
        let keyCallback: omni_adw_key_callback = { actionID, keyKind, codepoint, context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            let rawID = Int(actionID)
            if rawID >= adwaitaSettingsActionOffset {
                box.settingsRuntime.handleNativeKeyForRawActionID(rawID - adwaitaSettingsActionOffset, keyKind: Int(keyKind), codepoint: codepoint)
            } else {
                box.runtime.handleNativeKeyForRawActionID(rawID, keyKind: Int(keyKind), codepoint: codepoint)
            }
            box.rerender()
        }
        let focusCallback: omni_adw_focus_callback = { actionID, context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            let rawID = Int(actionID)
            let changed: Bool
            if rawID >= adwaitaSettingsActionOffset {
                changed = box.settingsRuntime.focusByRawActionID(rawID - adwaitaSettingsActionOffset)
            } else {
                changed = box.runtime.focusByRawActionID(rawID)
            }
            if changed {
                box.rerender()
            }
        }

        cApp = omni_adw_app_new(appID, title, callback, textCallback, keyCallback, focusCallback, box.toOpaque())
        guard let cApp else {
            box.release()
            throw OmniUIAdwaitaRendererError.unableToCreateApplication
        }
        let windowSize = nativeWindowSize(for: size)
        let renderSize = semanticRenderSize(for: size)
        omni_adw_app_set_default_size(cApp, Int32(windowSize.width), Int32(windowSize.height))
        if let settings {
            let snapshot = settingsRuntime.semanticSnapshot(settings(), size: renderSize)
            let settingsRoot = AdwaitaNodeBuilder.offsetActionIDs(in: snapshot.root, by: adwaitaSettingsActionOffset)
            if let node = AdwaitaNodeBuilder.build(settingsRoot) {
                omni_adw_app_set_settings(cApp, node)
            }
        }
        if let commands {
            let snapshot = commandRuntime.semanticSnapshot(commands(), size: renderSize)
            let commandRoot = AdwaitaNodeBuilder.offsetActionIDs(in: snapshot.root, by: adwaitaCommandActionOffset)
            if let node = AdwaitaNodeBuilder.build(commandRoot) {
                omni_adw_app_set_commands(cApp, node)
            }
        }
        defer {
            omni_adw_app_free(cApp)
            box.release()
        }

        let rerender: @MainActor () -> Void = { [runtime, root, renderSize] in
            let snapshot = runtime.semanticSnapshot(root(), size: renderSize)
            let presentation = AdwaitaPresentationExtractor.extract(from: snapshot.root)
            let displaySnapshot = SemanticSnapshot(
                root: presentation.root,
                size: snapshot.size,
                focusedActionID: snapshot.focusedActionID,
                activeMenu: snapshot.activeMenu,
                activePicker: snapshot.activePicker,
                activeTextField: snapshot.activeTextField
            )
            AdwaitaSemanticDumper.dumpIfRequested(displaySnapshot.root)
            if let headerEntry = AdwaitaHeaderEntry.extract(from: displaySnapshot.root) {
                omni_adw_app_set_header_entry(cApp, headerEntry.placeholder, headerEntry.text, Int32(headerEntry.actionID))
            }
            let callbackBox = box.takeUnretainedValue()
            let changes = callbackBox.previousSnapshot.map {
                SemanticDiff.changes(from: $0, to: displaySnapshot)
            } ?? []
            callbackBox.lastChanges = changes
            callbackBox.textValuesByActionID = AdwaitaNodeBuilder.textValues(in: displaySnapshot.root)
            if changes.isEmpty, callbackBox.previousSnapshot != nil {
                syncNativePresentation(presentation.modal, app: cApp)
                callbackBox.previousSnapshot = displaySnapshot
                return
            }
            if !changes.isEmpty, AdwaitaNodeBuilder.applyLeafUpdates(changes: changes, snapshot: displaySnapshot, app: cApp) {
                syncNativePresentation(presentation.modal, app: cApp)
                callbackBox.previousSnapshot = displaySnapshot
                return
            }
            if
                !changes.isEmpty,
                let previousSnapshot = callbackBox.previousSnapshot,
                AdwaitaNodeBuilder.applyStructuralReplacement(
                    changes: changes,
                    previous: previousSnapshot.root,
                    next: displaySnapshot.root,
                    focusedActionID: displaySnapshot.focusedActionID,
                    app: cApp
                )
            {
                syncNativePresentation(presentation.modal, app: cApp)
                callbackBox.previousSnapshot = displaySnapshot
                return
            }
            guard let node = AdwaitaNodeBuilder.build(displaySnapshot.root) else { return }
            omni_adw_app_set_root_focused(cApp, node, Int32(displaySnapshot.focusedActionID ?? 0))
            syncNativePresentation(presentation.modal, app: cApp)
            callbackBox.previousSnapshot = displaySnapshot
        }
        box.takeUnretainedValue().rerender = { Task { @MainActor in rerender() } }
        rerender()
        let observationRenderLoop = Task { @MainActor [runtime, renderSize] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000)
                if runtime.needsRender(size: renderSize) {
                    rerender()
                }
            }
        }
        defer {
            observationRenderLoop.cancel()
        }

        let argc: Int32 = 0
        _ = omni_adw_app_run(cApp, argc, nil)
    }
}

@MainActor
private enum AdwaitaSemanticDumper {
    private static var didDump = false

    static func dumpIfRequested(_ root: SemanticNode) {
        guard ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_DUMP_SEMANTIC"] == "1", !didDump else {
            return
        }
        didDump = true
        write("OMNIUI_ADWAITA_SEMANTIC_BEGIN")
        dump(root, depth: 0)
        write("OMNIUI_ADWAITA_SEMANTIC_END")
    }

    private static func dump(_ node: SemanticNode, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        write("\(indent)\(node.id) \(String(describing: node.kind))")
        for child in node.children {
            dump(child, depth: depth + 1)
        }
    }

    private static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

private struct AdwaitaHeaderEntry {
    let placeholder: String
    let text: String
    let actionID: Int

    static func extract(from root: SemanticNode) -> AdwaitaHeaderEntry? {
        if case .modifier(.accessibilityIdentifier("url-field")) = root.kind {
            return firstTextField(in: root)
        }
        for child in root.children {
            if let entry = extract(from: child) {
                return entry
            }
        }
        return nil
    }

    private static func firstTextField(in node: SemanticNode) -> AdwaitaHeaderEntry? {
        if case .textField(let actionID, let placeholder, let text, _, _, _) = node.kind {
            return AdwaitaHeaderEntry(placeholder: placeholder, text: text, actionID: actionID)
        }
        for child in node.children {
            if let entry = firstTextField(in: child) {
                return entry
            }
        }
        return nil
    }
}

public extension AdwaitaApp where Root == AnyView {
    @MainActor
    convenience init<S: Scene>(
        appID: String = "dev.omnikit.KitchenSinkAdwaita",
        title: String = "OmniUI Adwaita",
        size: _Size = _Size(width: 120, height: 42),
        scene: S
    ) {
        let resolvedSize = _scenePreferredSize(scene).map {
            _Size(width: max(1, Int($0.width.rounded())), height: max(1, Int($0.height.rounded())))
        } ?? size
        let sceneSettings = _sceneSettingsView(scene)
        let sceneCommands = _sceneCommandsView(scene)
        let settingsProvider: (@MainActor () -> AnyView)?
        if let sceneSettings {
            settingsProvider = { sceneSettings }
        } else {
            settingsProvider = nil
        }
        let commandsProvider: (@MainActor () -> AnyView)?
        if let sceneCommands {
            commandsProvider = { sceneCommands }
        } else {
            commandsProvider = nil
        }
        self.init(
            appID: appID,
            title: title,
            size: resolvedSize,
            settings: settingsProvider,
            commands: commandsProvider
        ) {
            _sceneRootView(scene) ?? AnyView(Text("Empty Scene"))
        }
    }

    @MainActor
    convenience init<A: App>(
        appID: String = "dev.omnikit.KitchenSinkAdwaita",
        title: String = "OmniUI Adwaita",
        size: _Size = _Size(width: 120, height: 42),
        _ appType: A.Type
    ) {
        self.init(appID: appID, title: title, size: size, scene: A.init().body)
    }
}

private func nativeWindowSize(for size: _Size) -> (width: Int, height: Int) {
    let width = size.width <= 240 ? size.width * 9 : size.width
    let height = size.height <= 120 ? size.height * 18 : size.height
    return (max(320, width), max(240, height))
}

private func semanticRenderSize(for size: _Size) -> _Size {
    _Size(
        width: size.width > 240 ? max(1, size.width / 9) : size.width,
        height: size.height > 120 ? max(1, size.height / 18) : size.height
    )
}

public extension App {
    @MainActor
    static func adwaitaMain(
        appID: String = "dev.omnikit.OmniUIAdwaita",
        title: String = "OmniUI Adwaita",
        size: _Size = _Size(width: 120, height: 42)
    ) async throws {
        try await AdwaitaApp(appID: appID, title: title, size: size, Self.self).run()
    }
}

private final class CallbackBox: @unchecked Sendable {
    let runtime: _UIRuntime
    let settingsRuntime: _UIRuntime
    let commandRuntime: _UIRuntime
    var rerender: @Sendable () -> Void
    var textValuesByActionID: [Int: String] = [:]
    var previousSnapshot: SemanticSnapshot?
    var lastChanges: [SemanticChange] = []

    init(runtime: _UIRuntime, settingsRuntime: _UIRuntime, commandRuntime: _UIRuntime, rerender: @escaping @Sendable () -> Void) {
        self.runtime = runtime
        self.settingsRuntime = settingsRuntime
        self.commandRuntime = commandRuntime
        self.rerender = rerender
    }
}

private struct AdwaitaPresentation {
    var root: SemanticNode
    var modal: SemanticNode?
}

private enum AdwaitaPresentationExtractor {
    static func extract(from root: SemanticNode) -> AdwaitaPresentation {
        var modal: SemanticNode?
        let cleaned = stripPresentation(from: root, modal: &modal)
        return AdwaitaPresentation(root: cleaned ?? SemanticNode(id: root.id, kind: .empty), modal: modal)
    }

    private static func stripPresentation(from node: SemanticNode, modal: inout SemanticNode?) -> SemanticNode? {
        if isAdwaitaDialog(node) {
            modal = nativeDialogContent(from: node)
            return nil
        }

        let children = node.children.compactMap { stripPresentation(from: $0, modal: &modal) }
        if node.kind == .zstack, children.count == 1 {
            return children[0]
        }
        return SemanticNode(id: node.id, kind: node.kind, children: children)
    }

    private static func isAdwaitaDialog(_ node: SemanticNode) -> Bool {
        if case .modifier(.background("adw-dialog")) = node.kind {
            return true
        }
        return false
    }

    private static func nativeDialogContent(from node: SemanticNode) -> SemanticNode {
        guard case .modifier(.background("adw-dialog")) = node.kind else {
            return node
        }
        return node
    }
}

private func syncNativePresentation(_ modal: SemanticNode?, app: OpaquePointer?) {
    guard let app else { return }
    guard let modal else {
        omni_adw_app_dismiss_modal(app)
        return
    }
    guard let node = AdwaitaNodeBuilder.build(modal) else {
        omni_adw_app_dismiss_modal(app)
        return
    }
    omni_adw_app_present_modal(app, node, "Presentation")
}

public enum AdwaitaSemanticCoverage {
    public static let supported: [String] = [
        "App", "Scene", "WindowGroup", "Settings", "commands",
        "@State", "@Binding", "@Environment", "@AppStorage", "@FocusState", "@Namespace", "@Bindable",
        "SwiftData @Query", "modelContainer", "modelContext",
        "NavigationStack", "NavigationSplitView", "VStack", "HStack", "ZStack",
        "Form", "List", "ScrollView", "ScrollViewReader", "LazyVStack", "GeometryReader",
        "Text", "Image", "Button", "Toggle", "TextField", "SecureField", "TextEditor", "ProgressView", "Slider", "Stepper", "DatePicker", "Picker", "Menu",
        "Toolbar", "Sheet", "Alert", "layout/style/input/accessibility modifiers",
        "Canvas", "Path", "Shape", "Gradient drawing islands",
        "Liquid Glass and CRT native-style approximations",
    ]

    public static let approximations: [String] = [
        "Canvas/Path/shapes/gradients lower to GTK drawing islands when no native widget exists.",
        "Liquid Glass maps to libadwaita card/header styling; CRT effects are documented no-op CSS classes.",
        "Arbitrary SwiftUI animation curves are reconciled by rebuilding native widgets after state actions.",
    ]
}

public struct AdwaitaNativeLeafUpdate: Sendable, Equatable {
    public enum Kind: Int32, Sendable, Equatable {
        case text = 0
        case button = 1
        case toggle = 2
        case textField = 3
        case textEditor = 4
        case dropdown = 5
        case progress = 6
        case slider = 7
        case stepper = 8
        case datePicker = 9
        case scroll = 10
    }

    public let id: String
    public let kind: Kind
    public let text: String
    public let active: Bool

    public init(id: String, kind: Kind, text: String, active: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.active = active
    }
}

public struct AdwaitaNativeSubtreeReplacement: Sendable, Equatable {
    public let id: String
    public let node: SemanticNode

    public init(id: String, node: SemanticNode) {
        self.id = id
        self.node = node
    }

    public static func == (lhs: AdwaitaNativeSubtreeReplacement, rhs: AdwaitaNativeSubtreeReplacement) -> Bool {
        lhs.id == rhs.id &&
            lhs.node.id == rhs.node.id &&
            lhs.node.kind == rhs.node.kind &&
            lhs.node.children.map(\.id) == rhs.node.children.map(\.id)
    }
}

public enum AdwaitaReconciliation {
    public static func leafUpdates(changes: [SemanticChange], snapshot: SemanticSnapshot) -> [AdwaitaNativeLeafUpdate]? {
        leafUpdates(changes: changes, root: snapshot.root)
    }

    public static func leafUpdates(changes: [SemanticChange], root: SemanticNode) -> [AdwaitaNativeLeafUpdate]? {
        let nodes = nodesByID(in: root)
        var updates: [AdwaitaNativeLeafUpdate] = []
        for change in changes {
            guard change.kind == .updated, let node = nodes[change.id], let update = nativeLeafUpdate(for: node) else {
                return nil
            }
            updates.append(update)
        }
        return updates
    }

    public static func subtreeReplacement(changes: [SemanticChange], previous: SemanticNode, next: SemanticNode) -> AdwaitaNativeSubtreeReplacement? {
        guard !changes.isEmpty else { return nil }
        if leafUpdates(changes: changes, root: next) != nil {
            return nil
        }

        let previousNodes = nodesByID(in: previous)
        let nextNodes = nodesByID(in: next)
        let candidateIDs = Set(changes.compactMap { replacementCandidateID(for: $0) })
        guard let candidateID = replacementAncestor(in: candidateIDs, previousNodes: previousNodes, nextNodes: nextNodes) else { return nil }
        guard let nextNode = nextNodes[candidateID] else { return nil }
        return AdwaitaNativeSubtreeReplacement(id: candidateID, node: nextNode)
    }

    private static func replacementAncestor(
        in candidateIDs: Set<String>,
        previousNodes: [String: SemanticNode],
        nextNodes: [String: SemanticNode]
    ) -> String? {
        let existingCandidates = candidateIDs.filter { previousNodes[$0] != nil && nextNodes[$0] != nil }
        let sorted = existingCandidates.sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs < rhs }
            return lhs.count < rhs.count
        }
        return sorted.first { candidate in
            candidateIDs.allSatisfy { id in
                id == candidate || id.hasPrefix(candidate + ".")
            }
        }
    }

    private static func replacementCandidateID(for change: SemanticChange) -> String? {
        switch change.kind {
        case .childrenReordered:
            return change.id
        case .updated:
            return change.id
        case .inserted, .removed:
            return parentID(of: change.id)
        }
    }

    private static func parentID(of id: String) -> String? {
        if let dot = id.lastIndex(of: ".") {
            let parent = String(id[..<dot])
            return parent.isEmpty ? nil : parent
        }
        return nil
    }

    private static func nodesByID(in root: SemanticNode) -> [String: SemanticNode] {
        var nodes: [String: SemanticNode] = [:]
        func visit(_ node: SemanticNode) {
            nodes[node.id] = node
            for child in node.children {
                visit(child)
            }
        }
        visit(root)
        return nodes
    }

    private static func nativeLeafUpdate(for node: SemanticNode) -> AdwaitaNativeLeafUpdate? {
        switch node.kind {
        case .text(let text), .image(let text):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .text, text: text)
        case .button:
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .button, text: accessibleLabel(for: node))
        case .toggle(_, _, let isOn):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .toggle, text: accessibleLabel(for: node), active: isOn)
        case .textField(_, _, let text, _, _, _):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .textField, text: text)
        case .textEditor(_, let text, _, _):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .textEditor, text: text)
        case .menu(_, let title, let value, _):
            if menuItems(in: node).isEmpty {
                return AdwaitaNativeLeafUpdate(id: node.id, kind: .button, text: value.isEmpty ? title : "\(title): \(value)")
            }
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .dropdown, text: value)
        case .progress(let label, let fraction):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .progress, text: progressUpdateText(label: label, fraction: fraction))
        case .slider(let label, let value, _, _, _, _, _):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .slider, text: "\(value)\n\(label)")
        case .stepper(let label, let value, _, _):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .stepper, text: "\(value ?? 0)\n\(label)")
        case .datePicker(let label, let value, let timestamp, _, _, _):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .datePicker, text: "\(timestamp)\n\(value)\n\(label)")
        case .scroll(_, _, let offset):
            return AdwaitaNativeLeafUpdate(id: node.id, kind: .scroll, text: "\(offset)")
        default:
            return nil
        }
    }

    fileprivate static func accessibleLabel(for node: SemanticNode) -> String {
        if let label = explicitAccessibilityLabel(in: node) {
            return label
        }
        if case .disabledButton(let label) = node.kind, !label.isEmpty {
            return label
        }
        if case .disabledToggle(let label, _) = node.kind, !label.isEmpty {
            return label
        }
        if case .text(let text) = node.kind, !text.isEmpty {
            return text
        }
        if case .image(let text) = node.kind {
            return SFSymbolMap.unicode(for: text) ?? text
        }
        let collected = accessibilityText(in: node)
        if !collected.isEmpty {
            return collected
        }
        return "Action"
    }

    fileprivate static func accessibilityText(in node: SemanticNode) -> String {
        var parts: [String] = []
        collectAccessibilityText(in: node, into: &parts)
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func collectAccessibilityText(in node: SemanticNode, into parts: inout [String]) {
        switch node.kind {
        case .text(let text):
            parts.append(text)
        case .image(let text):
            parts.append(SFSymbolMap.unicode(for: text) ?? text)
        case .disabledButton(let label), .disabledTextField(_, let label, _):
            parts.append(label)
        case .disabledToggle(let label, _), .disabledMenu(let label, _):
            parts.append(label)
        case .spacer, .empty, .divider, .drawingIsland:
            break
        default:
            break
        }
        for child in node.children {
            collectAccessibilityText(in: child, into: &parts)
        }
    }

    private static func explicitAccessibilityLabel(in node: SemanticNode) -> String? {
        if case .modifier(.accessibilityLabel(let label)) = node.kind, !label.isEmpty {
            return label
        }
        for child in node.children {
            if let label = explicitAccessibilityLabel(in: child) {
                return label
            }
        }
        return nil
    }

    fileprivate static func menuItems(in node: SemanticNode) -> [(label: String, actionID: Int)] {
        node.children.compactMap { child in
            guard case .button(let actionID, _) = child.kind else { return nil }
            return (accessibleLabel(for: child), actionID)
        }
    }

    fileprivate static func progressUpdateText(label: String, fraction: Double?) -> String {
        let clamped = max(0, min(1, fraction ?? 0))
        let prefix = label.isEmpty ? "Progress" : label
        let display = fraction.map { "\(prefix) \(Int((max(0, min(1, $0)) * 100).rounded()))%" } ?? prefix
        return "\(clamped)\n\(display)"
    }
}

enum AdwaitaNodeBuilder {
    private enum BuildContext: Equatable {
        case normal
        case sidebar
    }

    static func offsetActionIDs(in node: SemanticNode, by offset: Int) -> SemanticNode {
        let kind: SemanticNode.Kind
        switch node.kind {
        case .scroll(let axis, let actionID, let offsetValue):
            kind = .scroll(axis: axis, actionID: actionID + offset, offset: offsetValue)
        case .button(let actionID, let isFocused):
            kind = .button(actionID: actionID + offset, isFocused: isFocused)
        case .toggle(let actionID, let isFocused, let isOn):
            kind = .toggle(actionID: actionID + offset, isFocused: isFocused, isOn: isOn)
        case .textField(let actionID, let placeholder, let text, let cursor, let isFocused, let isSecure):
            kind = .textField(actionID: actionID + offset, placeholder: placeholder, text: text, cursor: cursor, isFocused: isFocused, isSecure: isSecure)
        case .textEditor(let actionID, let text, let cursor, let isFocused):
            kind = .textEditor(actionID: actionID + offset, text: text, cursor: cursor, isFocused: isFocused)
        case .menu(let actionID, let title, let value, let isExpanded):
            kind = .menu(actionID: actionID + offset, title: title, value: value, isExpanded: isExpanded)
        case .slider(let label, let value, let lowerBound, let upperBound, let step, let decrementActionID, let incrementActionID):
            kind = .slider(
                label: label,
                value: value,
                lowerBound: lowerBound,
                upperBound: upperBound,
                step: step,
                decrementActionID: decrementActionID.map { $0 + offset },
                incrementActionID: incrementActionID.map { $0 + offset }
            )
        case .stepper(let label, let value, let decrementActionID, let incrementActionID):
            kind = .stepper(
                label: label,
                value: value,
                decrementActionID: decrementActionID.map { $0 + offset },
                incrementActionID: incrementActionID.map { $0 + offset }
            )
        case .datePicker(let label, let value, let timestamp, let setActionID, let decrementActionID, let incrementActionID):
            kind = .datePicker(
                label: label,
                value: value,
                timestamp: timestamp,
                setActionID: setActionID.map { $0 + offset },
                decrementActionID: decrementActionID.map { $0 + offset },
                incrementActionID: incrementActionID.map { $0 + offset }
            )
        default:
            kind = node.kind
        }
        return SemanticNode(
            id: node.id,
            kind: kind,
            children: node.children.map { offsetActionIDs(in: $0, by: offset) }
        )
    }

    static func textValues(in node: SemanticNode) -> [Int: String] {
        var values: [Int: String] = [:]
        collectTextValues(in: node, into: &values)
        return values
    }

    static func build(_ node: SemanticNode) -> OpaquePointer? {
        build(node, context: .normal)
    }

    private static func build(_ node: SemanticNode, context: BuildContext) -> OpaquePointer? {
        let built: OpaquePointer?
        var metadataID = node.id
        switch node.kind {
        case .empty:
            built = omni_adw_box_new(1, 0)
        case .group:
            built = container(vertical: true, spacing: 6, children: node.children, context: context)
        case .zstack:
            built = container(vertical: true, spacing: 6, children: visibleChildren(forOverlayChildren: node.children), context: context)
        case .spacer:
            built = omni_adw_box_new(1, 0)
        case .stack(let axis, let spacing):
            built = container(vertical: axis == .vertical, spacing: Int32(spacing), children: node.children, context: context)
        case .text(let text):
            built = omni_adw_text_new(text)
        case .image(let text):
            built = omni_adw_text_new(SFSymbolMap.unicode(for: text) ?? text)
        case .button(let actionID, _):
            built = omni_adw_button_new(accessibleLabel(for: node), Int32(actionID))
        case .toggle(let actionID, _, let isOn):
            built = omni_adw_toggle_new(accessibleLabel(for: node), isOn ? 1 : 0, Int32(actionID))
        case .textField(let actionID, let placeholder, let text, _, _, let isSecure):
            built = isSecure
                ? omni_adw_secure_entry_new(placeholder, text, Int32(actionID))
                : omni_adw_entry_new(placeholder, text, Int32(actionID))
        case .textEditor(let actionID, let text, _, _):
            built = omni_adw_text_view_new(text, Int32(actionID))
        case .menu(let actionID, let title, let value, _):
            let items = menuItems(in: node)
            if items.isEmpty {
                built = omni_adw_button_new(value.isEmpty ? title : "\(title): \(value)", Int32(actionID))
            } else {
                var ids = items.map { Int32($0.actionID) }
                built = items.map(\.label).withCStringArray { labels in
                    ids.withUnsafeMutableBufferPointer { idBuffer in
                        omni_adw_dropdown_new(title, value, labels, idBuffer.baseAddress, Int32(items.count))
                    }
                }
            }
        case .disabledButton(let label):
            built = omni_adw_button_new(label, 0)
            if let built {
                omni_adw_node_set_sensitive(built, 0)
            }
        case .disabledToggle(let label, let isOn):
            built = omni_adw_toggle_new(label, isOn ? 1 : 0, 0)
            if let built {
                omni_adw_node_set_sensitive(built, 0)
            }
        case .disabledTextField(let placeholder, let text, let isSecure):
            built = isSecure
                ? omni_adw_secure_entry_new(placeholder, text, 0)
                : omni_adw_entry_new(placeholder, text, 0)
            if let built {
                omni_adw_node_set_sensitive(built, 0)
            }
        case .disabledMenu(let title, let value):
            built = omni_adw_button_new(value.isEmpty ? title : "\(title): \(value)", 0)
            if let built {
                omni_adw_node_set_sensitive(built, 0)
            }
        case .progress(let label, let fraction):
            built = omni_adw_progress_new(progressLabel(label: label, fraction: fraction), max(0, min(1, fraction ?? 0)))
        case .slider(let label, let value, let lowerBound, let upperBound, let step, let decrementActionID, let incrementActionID):
            guard let parent = omni_adw_box_new(1, 4) else { return nil }
            if let scale = omni_adw_scale_new(label.isEmpty ? "Slider" : label, value, lowerBound, upperBound, step ?? 0, Int32(decrementActionID ?? 0), Int32(incrementActionID ?? 0)) {
                omni_adw_node_set_metadata(scale, node.id, label.isEmpty ? "Slider" : label)
                omni_adw_node_append(parent, scale)
            }
            for child in node.children {
                if let built = build(child, context: context) {
                    omni_adw_node_append(parent, built)
                }
            }
            built = parent
            metadataID = "\(node.id).container"
        case .stepper(let label, let value, let decrementActionID, let incrementActionID):
            guard let parent = omni_adw_box_new(1, 4) else { return nil }
            if let spin = omni_adw_spin_new(label.isEmpty ? "Stepper" : label, value ?? 0, Int32(decrementActionID ?? 0), Int32(incrementActionID ?? 0)) {
                omni_adw_node_set_metadata(spin, node.id, label.isEmpty ? "Stepper" : label)
                omni_adw_node_append(parent, spin)
            }
            for child in node.children {
                if let built = build(child, context: context) {
                    omni_adw_node_append(parent, built)
                }
            }
            built = parent
            metadataID = "\(node.id).container"
        case .datePicker(let label, let value, let timestamp, let setActionID, let decrementActionID, let incrementActionID):
            guard let parent = omni_adw_box_new(1, 4) else { return nil }
            if let date = omni_adw_date_new(label.isEmpty ? "Date" : label, value, timestamp, Int32(setActionID ?? 0), Int32(decrementActionID ?? 0), Int32(incrementActionID ?? 0)) {
                omni_adw_node_set_metadata(date, node.id, label.isEmpty ? "Date" : label)
                omni_adw_node_append(parent, date)
            }
            for child in node.children {
                if let built = build(child, context: context) {
                    omni_adw_node_append(parent, built)
                }
            }
            built = parent
            metadataID = "\(node.id).container"
        case .scroll(let axis, _, let offset):
            guard let scroll = omni_adw_scroll_new(axis == .vertical ? 1 : 0, Double(offset)) else { return nil }
            if let child = container(vertical: true, spacing: 6, children: node.children, context: context) {
                omni_adw_node_append(scroll, child)
            }
            built = scroll
        case .divider:
            built = omni_adw_separator_new()
        case .drawingIsland(let kind):
            built = omni_adw_drawing_new("OmniUI \(kind)")
        case .container(let role):
            built = semanticContainer(role, children: node.children, context: context)
        case .modifier(let modifier):
            if case .accessibilityIdentifier(let identifier) = modifier, !identifier.isEmpty {
                metadataID = identifier
            }
            built = modifiedContainer(modifier, children: node.children, context: context)
        }
        if let built {
            omni_adw_node_set_metadata(built, metadataID, metadataLabel(for: node))
        }
        return built
    }

    static func applyLeafUpdates(changes: [SemanticChange], snapshot: SemanticSnapshot, app: OpaquePointer?) -> Bool {
        guard let app else { return false }
        guard let updates = AdwaitaReconciliation.leafUpdates(changes: changes, snapshot: snapshot) else { return false }
        for update in updates {
            let applied = omni_adw_app_update_node(app, update.id, update.kind.rawValue, update.text, update.active ? 1 : 0)
            if applied == 0 {
                return false
            }
        }
        return true
    }

    static func applyStructuralReplacement(
        changes: [SemanticChange],
        previous: SemanticNode,
        next: SemanticNode,
        focusedActionID: Int?,
        app: OpaquePointer?
    ) -> Bool {
        guard let app else { return false }
        guard
            let replacement = AdwaitaReconciliation.subtreeReplacement(changes: changes, previous: previous, next: next),
            let node = build(replacement.node)
        else { return false }
        return omni_adw_app_replace_node(app, replacement.id, node, Int32(focusedActionID ?? 0)) != 0
    }

    private static func collectTextValues(in node: SemanticNode, into values: inout [Int: String]) {
        if case .textField(let actionID, _, let text, _, _, _) = node.kind {
            values[actionID] = text
        }
        if case .textEditor(let actionID, let text, _, _) = node.kind {
            values[actionID] = text
        }
        for child in node.children {
            collectTextValues(in: child, into: &values)
        }
    }

    private static func menuItems(in node: SemanticNode) -> [(label: String, actionID: Int)] {
        AdwaitaReconciliation.menuItems(in: node)
    }

    private static func container(vertical: Bool, spacing: Int32, children: [SemanticNode], context: BuildContext) -> OpaquePointer? {
        guard let parent = omni_adw_box_new(vertical ? 1 : 0, spacing) else { return nil }
        for child in children {
            let built: OpaquePointer?
            if case .spacer = child.kind {
                built = omni_adw_box_new(vertical ? 1 : 0, 0)
            } else {
                built = build(child, context: context)
            }
            if let built {
                omni_adw_node_append(parent, built)
            }
        }
        return parent
    }

    private static func modifiedContainer(_ modifier: SemanticModifier, children: [SemanticNode], context: BuildContext) -> OpaquePointer? {
        func primaryContent() -> OpaquePointer? {
            if let content = children.first(where: { $0.id.hasSuffix(".content") }) {
                return build(content, context: context)
            }
            if children.count == 2 {
                switch modifier {
                case .background:
                    return build(visibleChildren(forOverlayChildren: children).first ?? children[1], context: context)
                default:
                    break
                }
            }
            if let child = children.last {
                return build(child, context: context)
            }
            return nil
        }

        let css: String
        switch modifier {
        case .background("adw-dialog"):
            css = "card adw-dialog"
        case .foreground, .background, .shadow, .glass, .crt, .clip, .accessibilityLabel, .noOp:
            return primaryContent()
        case .badge:
            css = "accent"
        case .accessibilityIdentifier:
            if children.count == 1, let child = children.first {
                return build(child, context: context)
            }
            return container(vertical: true, spacing: 0, children: children, context: context)
        case .frame, .padding, .opacity, .offset:
            if let node = primaryContent() {
                applyLayoutModifier(modifier, to: node)
                return node
            }
            css = ""
        }
        guard let parent = omni_adw_frame_new(css, 0) else { return nil }
        applyLayoutModifier(modifier, to: parent)
        for child in children {
            if let built = build(child, context: context) {
                omni_adw_node_append(parent, built)
            }
        }
        return parent
    }

    private static func visibleChildren(forOverlayChildren children: [SemanticNode]) -> [SemanticNode] {
        if let content = children.first(where: { $0.id.hasSuffix(".content") }) {
            return [content]
        }
        let nonDecorative = children.filter { !isDecorativeDrawing($0) }
        return nonDecorative.isEmpty ? children : nonDecorative
    }

    private static func isDecorativeDrawing(_ node: SemanticNode) -> Bool {
        switch node.kind {
        case .drawingIsland:
            return true
        case .modifier(.background), .modifier(.shadow), .modifier(.glass), .modifier(.crt), .modifier(.opacity), .modifier(.offset):
            return node.children.allSatisfy(isDecorativeDrawing)
        case .group, .zstack, .stack:
            return !node.children.isEmpty && node.children.allSatisfy(isDecorativeDrawing)
        default:
            return false
        }
    }

    private static func applyLayoutModifier(_ modifier: SemanticModifier, to node: OpaquePointer) {
        let cellWidth = 1
        let cellHeight = 1
        let marginUnit = 1
        switch modifier {
        case .frame(let width, let height, let minWidth, _, let minHeight, _):
            omni_adw_node_apply_layout(
                node,
                scaled(width, by: cellWidth),
                scaled(height, by: cellHeight),
                scaled(minWidth, by: cellWidth),
                scaled(minHeight, by: cellHeight),
                -1, -1, -1, -1,
                -1
            )
        case .padding(let top, let leading, let bottom, let trailing):
            omni_adw_node_apply_layout(
                node,
                -1, -1, -1, -1,
                Int32(max(0, top * marginUnit)),
                Int32(max(0, leading * marginUnit)),
                Int32(max(0, bottom * marginUnit)),
                Int32(max(0, trailing * marginUnit)),
                -1
            )
        case .opacity(let alpha):
            omni_adw_node_apply_layout(node, -1, -1, -1, -1, -1, -1, -1, -1, max(0, min(1, alpha)))
        case .offset(let x, let y):
            omni_adw_node_apply_layout(
                node,
                -1, -1, -1, -1,
                Int32(max(0, y * marginUnit)),
                Int32(max(0, x * marginUnit)),
                -1, -1,
                -1
            )
        default:
            break
        }
    }

    private static func scaled(_ value: Int?, by scale: Int) -> Int32 {
        guard let value, value > 0 else { return -1 }
        return Int32(value * scale)
    }

    private static func semanticContainer(_ role: SemanticContainerRole, children: [SemanticNode], context: BuildContext) -> OpaquePointer? {
        if role == .form {
            guard let parent = omni_adw_form_new() else { return nil }
            for child in formRows(from: children) {
                if let built = build(child, context: context) {
                    omni_adw_node_append(parent, built)
                }
            }
            return parent
        }

        if role == .list {
            if isEmptyListContent(children) {
                return omni_adw_box_new(1, 0)
            }
            if let simpleList = simpleListRows(from: children) {
                var ids = simpleList.rows.map { Int32($0.actionID ?? 0) }
                let labels = simpleList.rows.map(\.label)
                var depths = simpleList.rows.map { Int32($0.depth) }
                let list = labels.withCStringArray { labelPointers in
                    ids.withUnsafeMutableBufferPointer { idBuffer in
                        depths.withUnsafeMutableBufferPointer { depthBuffer in
                            if context == .sidebar {
                                omni_adw_sidebar_list_new(labelPointers, idBuffer.baseAddress, depthBuffer.baseAddress, Int32(simpleList.rows.count))
                            } else if simpleList.rows.count >= 128 {
                                omni_adw_string_list_new(labelPointers, idBuffer.baseAddress, Int32(simpleList.rows.count))
                            } else {
                                omni_adw_plain_list_new(labelPointers, idBuffer.baseAddress, Int32(simpleList.rows.count))
                            }
                        }
                    }
                }
                guard let list else { return nil }
                if let scroll = simpleList.scroll {
                    return wrapInScroll(list, axis: scroll.axis, offset: scroll.offset)
                }
                return wrapInScroll(list, axis: .vertical, offset: 0)
            }
            guard let parent = omni_adw_list_new() else { return nil }
            for child in children {
                if let built = build(child, context: context) {
                    omni_adw_node_append(parent, built)
                }
            }
            return wrapInScroll(parent, axis: .vertical, offset: 0)
        }

        if role == .navigationSplitView {
            return navigationSplitContainer(children: children)
        }

        let css: String
        let spacing: Int32
        switch role {
        case .form:
            css = "card"
            spacing = 8
        case .list:
            css = "boxed-list"
            spacing = 0
        case .navigationSplitView:
            css = "navigation-view"
            spacing = 8
        case .navigationStack:
            css = "navigation-view"
            spacing = 6
        case .lazyVStack:
            css = "view"
            spacing = 6
        }
        guard let parent = omni_adw_frame_new(css, spacing) else { return nil }
        for child in children {
            if let built = build(child, context: context) {
                omni_adw_node_append(parent, built)
            }
        }
        return parent
    }

    private static func wrapInScroll(_ child: OpaquePointer, axis: SemanticAxis, offset: Int) -> OpaquePointer? {
        guard let scrollNode = omni_adw_scroll_new(axis == .vertical ? 1 : 0, Double(offset)) else {
            return child
        }
        omni_adw_node_append(scrollNode, child)
        return scrollNode
    }

    private struct SimpleList {
        let rows: [(label: String, actionID: Int?, depth: Int)]
        let scroll: (axis: SemanticAxis, offset: Int)?
    }

    private static func simpleListRows(from children: [SemanticNode]) -> SimpleList? {
        guard children.count == 1, let scroll = children.first, case .scroll(let axis, _, let offset) = scroll.kind else {
            guard let rows = simpleRows(in: children) else { return nil }
            return SimpleList(rows: rows, scroll: nil)
        }
        guard let rows = simpleRows(in: scroll.children) else { return nil }
        return SimpleList(rows: rows, scroll: (axis: axis, offset: offset))
    }

    private static func simpleRows(in nodes: [SemanticNode]) -> [(label: String, actionID: Int?, depth: Int)]? {
        var rows: [(label: String, actionID: Int?, depth: Int)] = []

        func contentChildren(of node: SemanticNode) -> [SemanticNode] {
            node.children.filter { child in
                switch child.kind {
                case .empty, .spacer, .divider, .drawingIsland:
                    return false
                default:
                    return true
                }
            }
        }

        func rowLabel(from node: SemanticNode) -> String {
            let label = accessibleLabel(for: node).trimmingCharacters(in: .whitespacesAndNewlines)
            return label == "Action" ? "" : label
        }

        func leadingWhitespaceDepth(in node: SemanticNode) -> Int {
            switch node.kind {
            case .text(let text):
                guard text.allSatisfy({ $0 == " " || $0 == "\t" }) else { return 0 }
                return max(0, text.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2)
            case .button, .stack(axis: .horizontal, _), .modifier, .group:
                return node.children.map(leadingWhitespaceDepth(in:)).max() ?? 0
            default:
                return 0
            }
        }

        func firstButtonActionID(in node: SemanticNode) -> Int? {
            if case .button(let actionID, _) = node.kind {
                return actionID
            }
            for child in node.children {
                if let actionID = firstButtonActionID(in: child) {
                    return actionID
                }
            }
            return nil
        }

        func appendRows(from node: SemanticNode) -> Bool {
            switch node.kind {
            case .scroll:
                for child in contentChildren(of: node) {
                    if !appendRows(from: child) { return false }
                }
                return true
            case .container(.list):
                return false
            case .stack(axis: .vertical, _), .group, .container(.lazyVStack):
                for child in node.children {
                    if !appendRows(from: child) { return false }
                }
                return true
            case .modifier:
                let children = contentChildren(of: node)
                guard !children.isEmpty else { return true }
                if children.count == 1, let child = children.first {
                    return appendRows(from: child)
                }
                for child in children {
                    if !appendRows(from: child) { return false }
                }
                return true
            case .divider, .empty, .spacer, .drawingIsland:
                return true
            case .text(let text):
                rows.append((label: text, actionID: nil, depth: 0))
                return true
            case .button(let actionID, _):
                let label = rowLabel(from: node)
                if label.isEmpty { return false }
                rows.append((label: label, actionID: actionID, depth: leadingWhitespaceDepth(in: node)))
                return true
            case .stack(axis: .horizontal, _), .zstack:
                let label = rowLabel(from: node)
                if label.isEmpty { return false }
                rows.append((label: label, actionID: firstButtonActionID(in: node), depth: leadingWhitespaceDepth(in: node)))
                return true
            default:
                return false
            }
        }

        for node in nodes {
            if !appendRows(from: node) { return nil }
        }
        return rows.isEmpty ? nil : rows
    }

    private static func isEmptyListContent(_ nodes: [SemanticNode]) -> Bool {
        nodes.allSatisfy(isEmptyListNode)
    }

    private static func isEmptyListNode(_ node: SemanticNode) -> Bool {
        switch node.kind {
        case .empty, .divider:
            return true
        case .group, .zstack, .stack, .scroll, .modifier:
            return node.children.allSatisfy(isEmptyListNode)
        case .container(.lazyVStack), .container(.list):
            return node.children.allSatisfy(isEmptyListNode)
        default:
            return false
        }
    }

    private static func formRows(from children: [SemanticNode]) -> [SemanticNode] {
        guard children.count == 1, let first = children.first else { return children }
        switch first.kind {
        case .stack(axis: .vertical, _), .group:
            return first.children
        case .modifier, .scroll:
            return formRows(from: first.children)
        default:
            return children
        }
    }

    private static func navigationSplitContainer(children: [SemanticNode]) -> OpaquePointer? {
        guard let parent = omni_adw_split_new() else { return nil }
        guard let columns = navigationSplitColumns(from: children) else {
            for child in children {
                if let built = build(child, context: .normal) {
                    omni_adw_node_append(parent, built)
                }
            }
            return parent
        }

        if let sidebar = build(columns.sidebar, context: .sidebar) {
            omni_adw_node_append(parent, sidebar)
        }
        if let detail = container(vertical: true, spacing: 6, children: columns.detail, context: .normal) {
            omni_adw_node_append(parent, detail)
        }
        return parent
    }

    private static func navigationSplitColumns(from children: [SemanticNode]) -> (sidebar: SemanticNode, detail: [SemanticNode])? {
        guard children.count == 1, let splitRoot = children.first else { return nil }
        guard case .stack(let axis, _) = splitRoot.kind, axis == .horizontal else { return nil }
        let meaningfulChildren = splitRoot.children.filter { child in
            if case .text("│") = child.kind {
                return false
            }
            return true
        }
        guard let sidebar = meaningfulChildren.first else { return nil }
        let detail = Array(meaningfulChildren.dropFirst())
        guard !detail.isEmpty else { return nil }
        return (sidebar, detail)
    }

    private static func metadataLabel(for node: SemanticNode) -> String {
        switch node.kind {
        case .text(let text), .image(let text):
            return text
        case .button, .toggle:
            return accessibleLabel(for: node)
        case .textField(_, let placeholder, let text, _, _, let isSecure):
            if isSecure {
                return text.isEmpty ? placeholder : String(repeating: "•", count: text.count)
            }
            return text.isEmpty ? placeholder : text
        case .textEditor(_, let text, _, _):
            return text.isEmpty ? "Text editor" : text
        case .menu(_, let title, let value, _):
            return value.isEmpty ? title : "\(title): \(value)"
        case .disabledButton(let label):
            return label
        case .disabledToggle(let label, _):
            return label
        case .disabledTextField(let placeholder, let text, let isSecure):
            if isSecure {
                return text.isEmpty ? placeholder : String(repeating: "•", count: text.count)
            }
            return text.isEmpty ? placeholder : text
        case .disabledMenu(let title, let value):
            return value.isEmpty ? title : "\(title): \(value)"
        case .progress(let label, let fraction):
            return progressLabel(label: label, fraction: fraction)
        case .slider(let label, let value, _, _, _, _, _):
            return label.isEmpty ? "Slider \(value)" : "\(label) \(value)"
        case .stepper(let label, let value, _, _):
            let prefix = label.isEmpty ? "Stepper" : label
            return value.map { "\(prefix) \($0)" } ?? prefix
        case .datePicker(let label, let value, _, _, _, _):
            let prefix = label.isEmpty ? "Date" : label
            return "\(prefix): \(value)"
        case .drawingIsland(let kind):
            return "OmniUI \(kind)"
        case .container(let role):
            return role.rawValue
        case .modifier(let modifier):
            if case .accessibilityLabel(let label) = modifier {
                return label
            }
            if case .accessibilityIdentifier(let identifier) = modifier {
                return identifier
            }
            return String(describing: modifier)
        case .scroll(let axis, _, _):
            return axis == .vertical ? "vertical scroll view" : "horizontal scroll view"
        default:
            return accessibleLabel(for: node)
        }
    }

    private static func accessibleLabel(for node: SemanticNode) -> String {
        AdwaitaReconciliation.accessibleLabel(for: node)
    }

    private static func progressLabel(label: String, fraction: Double?) -> String {
        let prefix = label.isEmpty ? "Progress" : label
        guard let fraction else { return prefix }
        return "\(prefix) \(Int((max(0, min(1, fraction)) * 100).rounded()))%"
    }
}

private extension Array where Element == String {
    func withCStringArray<R>(_ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> R) -> R {
        let cStrings = map { strdup($0) }
        var pointers = cStrings.map { pointer -> UnsafePointer<CChar>? in
            guard let pointer else { return nil }
            return UnsafePointer(pointer)
        }
        defer {
            for pointer in cStrings {
                free(pointer)
            }
        }
        return pointers.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress)
        }
    }
}
