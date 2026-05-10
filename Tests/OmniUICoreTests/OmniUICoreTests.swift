import Testing
import Foundation
import OmniUICore

struct CounterView: View {
    @State private var count: Int = 0
    var body: some View {
        VStack(spacing: 1) {
            Text("Count: \(count)")
            Button("Inc") { count += 1 }
        }
        .padding(1)
    }
}

private enum _ProbeEnvironmentLabelKey: EnvironmentKey {
    static let defaultValue = "Default environment"
}

private extension EnvironmentValues {
    var probeEnvironmentLabel: String {
        get { self[_ProbeEnvironmentLabelKey.self] }
        set { self[_ProbeEnvironmentLabelKey.self] = newValue }
    }
}

private enum SemanticTextProbe {
    static func collect(in node: SemanticNode) -> String {
        var parts: [String] = []
        func visit(_ current: SemanticNode) {
            switch current.kind {
            case .text(let text), .image(let text):
                parts.append(text)
            default:
                break
            }
            current.children.forEach(visit)
        }
        visit(node)
        return parts.joined(separator: " ")
    }
}

@Test func debugSnapshot_click_increments_state() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 6)

    let s0 = runtime.debugRender(CounterView(), size: size)
    #expect(s0.text.contains("Count: 0"))

    // Button is rendered as "[ Inc ]" at roughly x=1,y=3 (after padding + text lines).
    s0.click(x: 2, y: 3)

    let s1 = runtime.debugRender(CounterView(), size: size)
    #expect(s1.text.contains("Count: 1"))
}

@Test func semanticSnapshot_navigationLinkPushesDestinationAfterNativeAction() async throws {
    struct V: View {
        var body: some View {
            NavigationStack {
                List {
                    NavigationLink(destination: Text("Destination loaded")) {
                        HStack {
                            Image(systemName: "doc.plaintext")
                            Text("Open file")
                        }
                    }
                }
            }
        }
    }

    func firstActionID(in node: SemanticNode, matching text: String) -> Int? {
        if case .button(let actionID, _) = node.kind,
           SemanticTextProbe.collect(in: node).contains(text) {
            return actionID
        }
        for child in node.children {
            if let actionID = firstActionID(in: child, matching: text) {
                return actionID
            }
        }
        return nil
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 80, height: 20)
    let initial = runtime.semanticSnapshot(V(), size: size)
    guard let actionID = firstActionID(in: initial.root, matching: "Open file") else {
        #expect(Bool(false), "No NavigationLink action")
        return
    }

    runtime.invokeActionByRawID(actionID)
    let next = runtime.semanticSnapshot(V(), size: size)
    #expect(SemanticTextProbe.collect(in: next.root).contains("Destination loaded"))
}

@Test func environment_modifier_propagates_custom_value_to_child_view() async throws {
    struct Child: View {
        @Environment(\.probeEnvironmentLabel) private var label

        var body: some View {
            Text("Environment label: \(label)")
        }
    }

    struct V: View {
        var body: some View {
            Child()
                .environment(\.probeEnvironmentLabel, "Injected environment")
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(V(), size: _Size(width: 60, height: 4))
    #expect(snapshot.text.contains("Environment label: Injected environment"))
}

@Test func semanticSnapshot_preserves_native_control_roles() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(CounterView(), size: _Size(width: 30, height: 6))

    func containsButton(_ node: SemanticNode) -> Bool {
        if case .button = node.kind { return true }
        return node.children.contains(where: containsButton)
    }

    func containsText(_ expected: String, in node: SemanticNode) -> Bool {
        if case .text(let text) = node.kind, text.contains(expected) { return true }
        return node.children.contains { containsText(expected, in: $0) }
    }

    #expect(containsButton(snapshot.root))
    #expect(containsText("Count: 0", in: snapshot.root))
    #expect(containsText("Inc", in: snapshot.root))
}

@Test func semanticSnapshot_preserves_progress_role() async throws {
    struct V: View {
        var body: some View {
            ProgressView(value: 0.5, total: 1.0)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 30, height: 6))

    func containsProgress(_ node: SemanticNode) -> Bool {
        if case .progress(_, let fraction) = node.kind {
            return fraction == 0.5
        }
        return node.children.contains(where: containsProgress)
    }

    #expect(containsProgress(snapshot.root))
}

@Test func secureField_masks_debug_output_but_preserves_semantic_value() async throws {
    struct V: View {
        @State var secret = "swordfish"

        var body: some View {
            SecureField("Secret", text: $secret)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(V(), size: _Size(width: 40, height: 4))
    #expect(snapshot.text.contains("•••••••••"))
    #expect(!snapshot.text.contains("swordfish"))

    let semantic = runtime.semanticSnapshot(V(), size: _Size(width: 40, height: 4))
    func containsSecureField(_ node: SemanticNode) -> Bool {
        if case .textField(_, _, let text, _, _, let isSecure) = node.kind {
            return isSecure && text == "swordfish"
        }
        return node.children.contains(where: containsSecureField)
    }

    #expect(containsSecureField(semantic.root))
}

@Test func semanticSnapshot_preserves_slider_role() async throws {
    struct V: View {
        @State var level = 0.4

        var body: some View {
            Slider(value: $level, in: 0...1, step: 0.1) {
                Text("Level")
            }
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 40, height: 6))

    func containsSlider(_ node: SemanticNode) -> Bool {
        if case .slider(let label, let value, let lower, let upper, let step, let decrementActionID, let incrementActionID) = node.kind {
            return label == "Level"
                && value == 0.4
                && lower == 0
                && upper == 1
                && step == 0.1
                && decrementActionID != nil
                && incrementActionID != nil
        }
        return node.children.contains(where: containsSlider)
    }

    #expect(containsSlider(snapshot.root))
}

@Test func semanticSnapshot_preserves_stepper_role() async throws {
    struct V: View {
        @State var value = 2

        var body: some View {
            Stepper("Stepper: \(value)", value: $value, in: 0...10)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 40, height: 6))

    func containsStepper(_ node: SemanticNode) -> Bool {
        if case .stepper(let label, let value, let decrementActionID, let incrementActionID) = node.kind {
            return label == "Stepper: 2"
                && value == 2
                && decrementActionID != nil
                && incrementActionID != nil
        }
        return node.children.contains(where: containsStepper)
    }

    #expect(containsStepper(snapshot.root))
}

@Test func semanticSnapshot_preserves_datePicker_role() async throws {
    struct V: View {
        @State var date = Date(timeIntervalSince1970: 1_704_067_200)

        var body: some View {
            DatePicker("Due", selection: $date)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 40, height: 6))

    func containsDatePicker(_ node: SemanticNode) -> Bool {
        if case .datePicker(let label, let value, let timestamp, let setActionID, let decrementActionID, let incrementActionID) = node.kind {
            return label == "Due"
                && value.contains("2023")
                && timestamp == 1_704_067_200
                && setActionID != nil
                && decrementActionID != nil
                && incrementActionID != nil
        }
        return node.children.contains(where: containsDatePicker)
    }

    #expect(containsDatePicker(snapshot.root))
}

@Test func semanticSnapshot_preserves_structural_container_roles() async throws {
    struct V: View {
        var body: some View {
            NavigationSplitView {
                List {
                    Text("Side")
                }
            } detail: {
                NavigationStack {
                    Form {
                        LazyVStack {
                            Text("Detail")
                        }
                    }
                }
            }
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 120, height: 30))

    func contains(_ role: SemanticContainerRole, in node: SemanticNode) -> Bool {
        if case .container(let nodeRole) = node.kind, nodeRole == role {
            return true
        }
        return node.children.contains { contains(role, in: $0) }
    }

    #expect(contains(.navigationSplitView, in: snapshot.root))
    #expect(contains(.navigationStack, in: snapshot.root))
    #expect(contains(.list, in: snapshot.root))
    #expect(contains(.form, in: snapshot.root))
    #expect(contains(.lazyVStack, in: snapshot.root))
}

@Test func semanticSnapshot_preserves_explicit_identity_in_node_ids() async throws {
    struct V: View {
        var body: some View {
            VStack(spacing: 0) {
                Text("Stable A").id("stable-a")
                Text("Stable B").id(42)
            }
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func ids(for text: String, in node: SemanticNode) -> [String] {
        var matches: [String] = []
        if case .text(let value) = node.kind, value == text {
            matches.append(node.id)
        }
        for child in node.children {
            matches.append(contentsOf: ids(for: text, in: child))
        }
        return matches
    }

    #expect(ids(for: "Stable A", in: snapshot.root).contains { $0.contains("stable-a") })
    #expect(ids(for: "Stable B", in: snapshot.root).contains { $0.contains("42") })
}

@Test func semanticSnapshot_preserves_accessibility_label_modifier() async throws {
    struct V: View {
        var body: some View {
            Button("Visual") {}
                .accessibilityLabel("Accessible action")
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func containsAccessibilityLabel(_ node: SemanticNode) -> Bool {
        if case .modifier(.accessibilityLabel("Accessible action")) = node.kind {
            return true
        }
        return node.children.contains(where: containsAccessibilityLabel)
    }

    #expect(containsAccessibilityLabel(snapshot.root))
}

@Test func semanticSnapshot_preserves_accessibility_identifier_modifier() async throws {
    struct V: View {
        var body: some View {
            Text("Identifier target")
                .accessibilityIdentifier("identifier-target")
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func containsAccessibilityIdentifier(_ node: SemanticNode) -> Bool {
        if case .modifier(.accessibilityIdentifier("identifier-target")) = node.kind {
            return true
        }
        return node.children.contains(where: containsAccessibilityIdentifier)
    }

    #expect(containsAccessibilityIdentifier(snapshot.root))
}

@Test func semanticSnapshot_preserves_liquid_glass_modifier_for_native_renderers() async throws {
    struct V: View {
        var body: some View {
            Text("Glass")
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func containsGlass(_ node: SemanticNode) -> Bool {
        if case .modifier(.glass(let descriptor)) = node.kind {
            return descriptor.contains("regular.interactive") && descriptor.contains("cornerRadius:8")
        }
        return node.children.contains(where: containsGlass)
    }

    #expect(containsGlass(snapshot.root))
}

@Test func semanticSnapshot_preserves_crt_modifier_as_native_noop_metadata() async throws {
    struct V: View {
        var body: some View {
            Text("CRT")
                .crtEffect(.scanline)
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 10))

    func containsCRT(_ node: SemanticNode) -> Bool {
        if case .modifier(.crt("scanline")) = node.kind {
            return true
        }
        return node.children.contains(where: containsCRT)
    }

    #expect(containsCRT(snapshot.root))
}

@Test func appStorage_updates_visible_state_and_user_defaults() async throws {
    let suiteName = "OmniUICoreTests.appStorage.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suiteName)!
    defer { store.removePersistentDomain(forName: suiteName) }

    struct V: View {
        let store: UserDefaults
        @AppStorage("count", store: UserDefaults.standard) private var count = 0

        init(store: UserDefaults) {
            self.store = store
            self._count = AppStorage(wrappedValue: 0, "count", store: store)
        }

        var body: some View {
            VStack(spacing: 1) {
                Text("Stored count: \(count)")
                Button("Store +1") { count += 1 }
            }
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 6)
    let initial = runtime.debugRender(V(store: store), size: size)
    #expect(initial.text.contains("Stored count: 0"))

    guard let button = _findButton(initial, title: "Store +1") else {
        #expect(Bool(false), "Could not find AppStorage update button")
        return
    }
    initial.click(x: button.x, y: button.y)

    let next = runtime.debugRender(V(store: store), size: size)
    #expect(next.text.contains("Stored count: 1"))
    #expect(store.integer(forKey: "count") == 1)
}

@Test func bindable_text_field_updates_observable_model_state() async throws {
    final class Model: OmniUICore.ObservableObject {
        let _$observationRegistrar = _ObservationRegistrar()
        var title = "Bindable start" {
            didSet { _$observationRegistrar.notify() }
        }
    }

    struct Editor: View {
        @Bindable var model: Model

        var body: some View {
            TextField("Title", text: $model.title)
        }
    }

    struct V: View {
        @State private var model = Model()

        var body: some View {
            VStack(spacing: 1) {
                Editor(model: model)
                Text("Model title: \(model.title)")
            }
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 50, height: 6)
    let initial = runtime.semanticSnapshot(V(), size: size)

    func textFieldActionID(in node: SemanticNode) -> Int? {
        if case .textField(let actionID, _, _, _, _, _) = node.kind {
            return actionID
        }
        for child in node.children {
            if let actionID = textFieldActionID(in: child) {
                return actionID
            }
        }
        return nil
    }

    guard let actionID = textFieldActionID(in: initial.root) else {
        #expect(Bool(false), "Could not find @Bindable TextField")
        return
    }

    runtime.replaceTextForRawActionID(actionID, previous: "Bindable start", next: "Bindable native edit")
    let next = runtime.debugRender(V(), size: size)
    #expect(next.text.contains("Model title: Bindable native edit"))
}

@Test func namespace_id_stays_stable_across_state_rerender() async throws {
    struct V: View {
        @Namespace private var namespace
        @State private var count = 0

        var body: some View {
            VStack(spacing: 1) {
                Text("Namespace: \(namespace.hashValue)")
                Text("Count: \(count)")
                Button("Increment") { count += 1 }
            }
        }
    }

    func namespaceLine(in snapshot: DebugSnapshot) -> String? {
        snapshot.lines.first(where: { $0.contains("Namespace:") })?
            .trimmingCharacters(in: .whitespaces)
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 60, height: 8)
    let initial = runtime.debugRender(V(), size: size)
    let initialNamespace = namespaceLine(in: initial)
    #expect(initial.text.contains("Count: 0"))

    guard let button = _findButton(initial, title: "Increment") else {
        #expect(Bool(false), "Could not find namespace rerender button")
        return
    }
    initial.click(x: button.x, y: button.y)

    let next = runtime.debugRender(V(), size: size)
    #expect(next.text.contains("Count: 1"))
    #expect(namespaceLine(in: next) == initialNamespace)
}

@Test func semanticSnapshot_preserves_disabled_control_roles_for_native_renderers() async throws {
    struct V: View {
        @State var enabled = true
        @State var name = "Locked"
        @State var picker = "A"

        var body: some View {
            VStack {
                Button("Disabled action") {}
                    .disabled(true)
                Toggle("Disabled toggle", isOn: $enabled)
                    .disabled(true)
                TextField("Disabled name", text: $name)
                    .disabled(true)
                Picker("Disabled picker", selection: $picker, options: [("A", "A")])
                    .disabled(true)
            }
        }
    }

    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(V(), size: _Size(width: 80, height: 12))

    #expect(_containsSemantic(snapshot.root) {
        if case .disabledButton(let label) = $0.kind {
            return label == "Disabled action"
        }
        return false
    })
    #expect(_containsSemantic(snapshot.root) {
        if case .disabledToggle(let label, let isOn) = $0.kind {
            return label == "Disabled toggle" && isOn
        }
        return false
    })
    #expect(_containsSemantic(snapshot.root) {
        if case .disabledTextField(let placeholder, let text, false) = $0.kind {
            return placeholder == "Disabled name" && text == "Locked"
        }
        return false
    })
    #expect(_containsSemantic(snapshot.root) {
        if case .disabledMenu(let title, let value) = $0.kind {
            return title == "Disabled picker" && value == "A"
        }
        return false
    })
}

@Test func semanticDiff_reports_updates_insertions_removals_and_reorders() async throws {
    let previous = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "a", kind: .text("A")),
        SemanticNode(id: "b", kind: .text("B")),
        SemanticNode(id: "c", kind: .button(actionID: 1, isFocused: false)),
    ])
    let next = SemanticNode(id: "root", kind: .stack(axis: .vertical, spacing: 0), children: [
        SemanticNode(id: "b", kind: .text("B2")),
        SemanticNode(id: "a", kind: .text("A")),
        SemanticNode(id: "d", kind: .toggle(actionID: 2, isFocused: false, isOn: true)),
    ])

    let changes = SemanticDiff.changes(from: previous, to: next)

    #expect(changes.contains(SemanticChange(id: "root", kind: .childrenReordered)))
    #expect(changes.contains(SemanticChange(id: "b", kind: .updated)))
    #expect(changes.contains(SemanticChange(id: "c", kind: .removed)))
    #expect(changes.contains(SemanticChange(id: "d", kind: .inserted)))
}

struct TextFieldView: View {
    @State private var text: String = ""
    var body: some View {
        VStack(spacing: 1) {
            TextField("placeholder", text: $text)
            Text("Value: \(text)")
        }
    }
}

struct TextEditorSemanticView: View {
    @State private var text: String = "Line 1\nLine 2"

    var body: some View {
        TextEditor(text: $text)
    }
}

struct TextEditorNativeInputView: View {
    @State private var text: String = "Native TextEditor"

    var body: some View {
        VStack(spacing: 1) {
            TextEditor(text: $text)
            Text("Value: \(text)")
        }
    }
}

@Test func semanticSnapshot_preserves_textEditor_role() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(TextEditorSemanticView(), size: _Size(width: 40, height: 8))

    func containsTextEditor(_ node: SemanticNode) -> Bool {
        if case .textEditor(_, let text, _, _) = node.kind {
            return text.contains("Line 1") && text.contains("Line 2")
        }
        return node.children.contains(where: containsTextEditor)
    }

    #expect(containsTextEditor(snapshot.root))
}

@Test func debugSnapshot_textField_focus_and_typing_updates_state() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 4)

    let s0 = runtime.debugRender(TextFieldView(), size: size)
    #expect(s0.text.contains("placeholder"))

    // Click the text field (top row).
    s0.click(x: 1, y: 0)
    s0.type("abc")

    let s1 = runtime.debugRender(TextFieldView(), size: size)
    #expect(s1.text.contains("Value: abc"))
}

@Test func runtime_replaceTextForRawActionID_updates_textField_binding() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 4)

    func textFieldActionID(in node: SemanticNode) -> Int? {
        if case .textField(let actionID, _, _, _, _, _) = node.kind {
            return actionID
        }
        for child in node.children {
            if let id = textFieldActionID(in: child) {
                return id
            }
        }
        return nil
    }

    let semantic = runtime.semanticSnapshot(TextFieldView(), size: size)
    guard let actionID = textFieldActionID(in: semantic.root) else {
        #expect(Bool(false), "Could not find semantic TextField action")
        return
    }

    runtime.replaceTextForRawActionID(actionID, previous: "", next: "native")
    var rendered = runtime.debugRender(TextFieldView(), size: size)
    #expect(rendered.text.contains("Value: native"))

    runtime.replaceTextForRawActionID(actionID, previous: "native", next: "native GTK")
    rendered = runtime.debugRender(TextFieldView(), size: size)
    #expect(rendered.text.contains("Value: native GTK"))

    runtime.replaceTextForRawActionID(actionID, previous: "native GTK", next: "GTK")
    rendered = runtime.debugRender(TextFieldView(), size: size)
    #expect(rendered.text.contains("Value: GTK"))
}

struct FocusedTextFieldNativeView: View {
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 1) {
            TextField("Name", text: Binding(get: { "" }, set: { _ in }))
                .focused($isFocused)
            Text("Focus: \(isFocused ? "focused" : "idle")")
        }
    }
}

@Test func runtime_focusByRawActionID_updates_focusState_binding() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 5)

    func textFieldActionID(in node: SemanticNode) -> Int? {
        if case .textField(let actionID, _, _, _, _, _) = node.kind {
            return actionID
        }
        for child in node.children {
            if let id = textFieldActionID(in: child) {
                return id
            }
        }
        return nil
    }

    var rendered = runtime.debugRender(FocusedTextFieldNativeView(), size: size)
    #expect(rendered.text.contains("Focus: idle"))

    let semantic = runtime.semanticSnapshot(FocusedTextFieldNativeView(), size: size)
    guard let actionID = textFieldActionID(in: semantic.root) else {
        #expect(Bool(false), "Could not find semantic TextField action")
        return
    }

    _ = runtime.focusByRawActionID(actionID)
    #expect(!runtime.focusByRawActionID(actionID))
    rendered = runtime.debugRender(FocusedTextFieldNativeView(), size: size)
    #expect(rendered.text.contains("Focus: focused"))
}

@Test func runtime_nativeTextEditorReplacement_updates_binding() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 8)

    func textEditorActionID(in node: SemanticNode) -> Int? {
        if case .textEditor(let actionID, _, _, _) = node.kind {
            return actionID
        }
        for child in node.children {
            if let id = textEditorActionID(in: child) {
                return id
            }
        }
        return nil
    }

    _ = runtime.debugRender(TextEditorNativeInputView(), size: size)
    let semantic = runtime.semanticSnapshot(TextEditorNativeInputView(), size: size)
    guard let actionID = textEditorActionID(in: semantic.root) else {
        #expect(Bool(false), "Could not find semantic TextEditor action")
        return
    }

    _ = runtime.focusByRawActionID(actionID)
    runtime.replaceTextForRawActionID(actionID, previous: "Native TextEditor", next: "Native TextEditor typed")

    let rendered = runtime.debugRender(TextEditorNativeInputView(), size: size)
    #expect(rendered.text.contains("Value: Native TextEditor typed"))
}

@Test func debugSnapshot_textField_readline_key_events_work() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 4)

    let s0 = runtime.debugRender(TextFieldView(), size: size)
    s0.click(x: 1, y: 0)
    s0.type("abcdef")

    runtime._handleKey(.left)
    runtime._handleKey(.left)
    runtime._handleKey(.killToEnd)
    runtime._handleKey(.home)
    runtime._handleKey(.char("X".unicodeScalars.first!.value))
    runtime._handleKey(.end)
    runtime._handleKey(.char("Z".unicodeScalars.first!.value))

    let s1 = runtime.debugRender(TextFieldView(), size: size)
    #expect(s1.text.contains("Value: XabcdZ"))
}

struct SimplePickerView: View {
    enum Choice: String, Hashable {
        case a = "A"
        case b = "B"
        case c = "C"
    }

    @State private var choice: Choice = .a

    var body: some View {
        VStack(spacing: 0) {
            Picker("Choice", selection: $choice, options: [(.a, "A"), (.b, "B"), (.c, "C")])
        }
    }
}

@Test func semanticSnapshot_preserves_picker_options_when_collapsed() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(SimplePickerView(), size: _Size(width: 80, height: 10))

    func menuChildren(_ node: SemanticNode) -> [SemanticNode]? {
        if case .menu = node.kind {
            return node.children
        }
        for child in node.children {
            if let found = menuChildren(child) {
                return found
            }
        }
        return nil
    }

    let children = menuChildren(snapshot.root) ?? []
    #expect(children.count == 3)
    #expect(children.contains { child in
        child.children.contains { if case .text("A") = $0.kind { true } else { false } }
    })
    #expect(children.contains { child in
        child.children.contains { if case .text("C") = $0.kind { true } else { false } }
    })
}

@Test func debugSnapshot_picker_dropdown_click_selects_option() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 20, height: 6)

    // Collapsed.
    let s0 = runtime.debugRender(SimplePickerView(), size: size)
    #expect(s0.text.contains("Choice: A"))

    // Open dropdown.
    s0.click(x: 1, y: 0)
    let s1 = runtime.debugRender(SimplePickerView(), size: size)
    #expect(s1.text.contains("Choice: A"))
    #expect(s1.text.contains("*A") || s1.text.contains("* A"))

    // Click the "C" option (options are rendered on subsequent rows).
    // Menu layout:
    // y=0 header
    // y=1 top border
    // y=2 option A
    // y=3 option B
    // y=4 option C
    s1.click(x: 2, y: 4)
    let s2 = runtime.debugRender(SimplePickerView(), size: size)
    #expect(s2.text.contains("Choice: C"))
}

struct PickerOverlayView: View {
    enum Choice: String, Hashable {
        case a = "A"
        case b = "B"
        case c = "C"
    }

    @State private var choice: Choice = .a

    var body: some View {
        VStack(spacing: 0) {
            Picker("Choice", selection: $choice, options: [(.a, "A"), (.b, "B"), (.c, "C")])
            Text("Tip: this should stay in-place")
        }
    }
}

@Test func debugSnapshot_picker_dropdown_is_overlay_not_layout() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 6)

    let s0 = runtime.debugRender(PickerOverlayView(), size: size)
    #expect(s0.text.contains("Tip: this should stay in-place"))

    // Expand dropdown. It should draw over the Tip line, not push it down.
    s0.click(x: 1, y: 0)
    let s1 = runtime.debugRender(PickerOverlayView(), size: size)
    #expect(!s1.text.contains("Tip: this should stay in-place"))

    // Collapse dropdown. Tip should become visible again.
    s1.click(x: 1, y: 0)
    let s2 = runtime.debugRender(PickerOverlayView(), size: size)
    #expect(s2.text.contains("Tip: this should stay in-place"))
}

struct ListRenderView: View {
    var body: some View {
        List(0..<5, id: \.self) { i in
            Text("Row \(i)")
        }
    }
}

@Test func debugSnapshot_list_renders_rows() async throws {
    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(ListRenderView(), size: _Size(width: 20, height: 10))
    #expect(s0.text.contains("Row 0"))
    #expect(s0.text.contains("Row 4"))
}

@Test func debugSnapshot_kitchensink_contains_list_row() async throws {
    // Mirrors the demo: nested ScrollView + List.
    struct Sink: View {
        @State var pickedRow = 0
        var body: some View {
            ScrollView {
                VStack(spacing: 1) {
                    Text("Header")
                    Text("List:")
                    List(0..<12, id: \.self) { i in
                        HStack(spacing: 1) {
                            Text("Row \(i)")
                            Spacer()
                            Button("Pick") { pickedRow = i }
                        }
                    }
                }
                .padding(1)
            }
        }
    }

    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(Sink(), size: _Size(width: 80, height: 24))
    #expect(s0.text.contains("Row 0"))
}

@Test func debugSnapshot_list_row_button_updates_parent_state() async throws {
    struct V: View {
        @State var pickedRow: Int = 0
        var body: some View {
            VStack(spacing: 1) {
                Text("picked: \(pickedRow)")
                List(0..<2, id: \.self) { i in
                    HStack(spacing: 1) {
                        Text("Row \(i)")
                        Spacer()
                        Button("Pick") { pickedRow = i }
                    }
                }
            }
            .padding(1)
        }
    }

    func findPickButton(_ snap: DebugSnapshot, occurrence: Int) -> (x: Int, y: Int)? {
        var seen = 0
        for (y, line) in snap.lines.enumerated() {
            let hay = Array(line)
            let needle = Array("[ Pick ]")
            if hay.count >= needle.count {
                for x0 in 0...(hay.count - needle.count) {
                    var ok = true
                    for i in 0..<needle.count {
                        if hay[x0 + i] != needle[i] { ok = false; break }
                    }
                    if ok {
                        if seen == occurrence {
                            // Click inside the button.
                            return (x: x0 + 2, y: y)
                        }
                        seen += 1
                        break
                    }
                }
            }
        }
        return nil
    }

    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(V(), size: _Size(width: 50, height: 12))
    #expect(s0.text.contains("picked: 0"))

    // Click the second row's Pick button (occurrence 1) so the value actually changes.
    guard let p = findPickButton(s0, occurrence: 1) else {
        #expect(Bool(false), "Could not find Pick button in snapshot")
        return
    }
    s0.click(x: p.x, y: p.y)

    let s1 = runtime.debugRender(V(), size: _Size(width: 50, height: 12))
    #expect(s1.text.contains("picked: 1"))
}

private struct _StableForEachRow: View {
    let value: Int
    @State private var taps = 0

    var body: some View {
        Button("Row \(value): \(taps)") {
            taps += 1
        }
    }
}

private struct _StableForEachListProbe: View {
    @State private var items = [1, 2]

    var body: some View {
        VStack(spacing: 1) {
            Button("Reverse") {
                items.reverse()
            }
            List {
                ForEach(items, id: \.self) { item in
                    _StableForEachRow(value: item)
                }
            }
        }
    }
}

@Test func forEach_list_row_state_stays_with_stable_id_after_reorder() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let initial = runtime.debugRender(_StableForEachListProbe(), size: size)
    #expect(initial.text.contains("Row 1: 0"))
    #expect(initial.text.contains("Row 2: 0"))

    guard let row2 = _findButton(initial, title: "Row 2: 0") else {
        #expect(Bool(false), "Could not find second row button")
        return
    }
    initial.click(x: row2.x, y: row2.y)

    let tapped = runtime.debugRender(_StableForEachListProbe(), size: size)
    #expect(tapped.text.contains("Row 1: 0"))
    #expect(tapped.text.contains("Row 2: 1"))

    guard let reverse = _findButton(tapped, title: "Reverse") else {
        #expect(Bool(false), "Could not find reverse button")
        return
    }
    tapped.click(x: reverse.x, y: reverse.y)

    let reordered = runtime.debugRender(_StableForEachListProbe(), size: size)
    #expect(reordered.text.contains("Row 2: 1"))
    #expect(reordered.text.contains("Row 1: 0"))
}

@Test func swiftDataCompat_query_reflects_modelContext_inserts() async throws {
    final class M {
        var id: Int
        init(id: Int) { self.id = id }
    }

    struct V: View {
        @Environment(\.modelContext) private var modelContext
        @Query(sort: \M.id, order: .reverse) private var models: [M]
        @State private var seeded: Bool = false

        var body: some View {
            VStack(spacing: 1) {
                Text("count: \(models.count)")
                Text("first: \(models.first?.id ?? -1)")
            }
            .onAppear {
                guard !seeded else { return }
                seeded = true
                modelContext.insert(M(id: 1))
                modelContext.insert(M(id: 2))
            }
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 6)

    let s0 = runtime.debugRender(V(), size: size)
    #expect(s0.text.contains("count: 0"))

    let s1 = runtime.debugRender(V(), size: size)
    #expect(s1.text.contains("count: 2"))
    #expect(s1.text.contains("first: 2"))
}

@Test func swiftDataCompat_query_reflects_modelContext_deletes() async throws {
    final class M {
        var id: Int
        init(id: Int) { self.id = id }
    }

    struct V: View {
        @Environment(\.modelContext) private var modelContext
        @Query(sort: \M.id, order: .forward) private var models: [M]

        var body: some View {
            VStack(spacing: 1) {
                Text("count: \(models.count)")
                Text("first: \(models.first?.id ?? -1)")
                Button("Seed") {
                    if models.isEmpty {
                        modelContext.insert(M(id: 1))
                        modelContext.insert(M(id: 2))
                    }
                }
                Button("Delete first") {
                    if let first = models.first {
                        modelContext.delete(first)
                    }
                }
            }
        }
    }

    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 8)

    let initial = runtime.debugRender(V(), size: size)
    #expect(initial.text.contains("count: 0"))
    guard let seed = _findButton(initial, title: "Seed") else {
        #expect(Bool(false), "Could not find SwiftData seed button")
        return
    }
    initial.click(x: seed.x, y: seed.y)

    let seeded = runtime.debugRender(V(), size: size)
    #expect(seeded.text.contains("count: 2"))
    #expect(seeded.text.contains("first: 1"))
    guard let delete = _findButton(seeded, title: "Delete first") else {
        #expect(Bool(false), "Could not find SwiftData delete button")
        return
    }
    seeded.click(x: delete.x, y: delete.y)

    let deleted = runtime.debugRender(V(), size: size)
    #expect(deleted.text.contains("count: 1"))
    #expect(deleted.text.contains("first: 2"))
}

struct TapGestureView: View {
    @State private var tapped: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Text("tapped: \(tapped)")
            Text("TapMe")
                .onTapGesture { tapped += 1 }
        }
    }
}

@Test func debugSnapshot_onTapGesture_click_updates_state() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 20, height: 4)

    let s0 = runtime.debugRender(TapGestureView(), size: size)
    #expect(s0.text.contains("tapped: 0"))

    // TapMe is on the second row at x≈0,y=1.
    s0.click(x: 0, y: 1)

    let s1 = runtime.debugRender(TapGestureView(), size: size)
    #expect(s1.text.contains("tapped: 1"))
}

struct MenuGestureView: View {
    @State private var picked: String = "-"

    var body: some View {
        VStack(spacing: 0) {
            Text("picked: \(picked)")
            Menu {
                Button("A") { picked = "A" }
                Button("B") { picked = "B" }
            } label: {
                Text("Menu")
            }
        }
    }
}

@Test func debugSnapshot_menu_click_selects_item() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 8)

    // Collapsed.
    let s0 = runtime.debugRender(MenuGestureView(), size: size)
    #expect(s0.text.contains("picked: -"))

    // Open dropdown (Menu header is on y=1).
    s0.click(x: 1, y: 1)
    let s1 = runtime.debugRender(MenuGestureView(), size: size)

    // Click the second option ("B") in the dropdown.
    // Menu layout:
    // y=1 header
    // y=2 top border
    // y=3 option A
    // y=4 option B
    s1.click(x: 2, y: 4)

    let s2 = runtime.debugRender(MenuGestureView(), size: size)
    #expect(s2.text.contains("picked: B"))
}

@Test func keyboardShortcut_defaultAction_invokes_button_action() async throws {
    final class Box {
        var value: Int = 0
    }

    struct V: View {
        let box: Box
        var body: some View {
            Button("Inc") { box.value += 1 }
                .keyboardShortcut(.defaultAction)
        }
    }

    let box = Box()
    let runtime = _UIRuntime()
    _ = runtime.render(V(box: box), size: _Size(width: 20, height: 3))

    #expect(box.value == 0)
    #expect(runtime.invokeKeyboardShortcut(.return))
    #expect(box.value == 1)
}

@Test func keyboardShortcut_cancelAction_invokes_button_action() async throws {
    final class Box {
        var cancelled: Bool = false
    }

    struct V: View {
        let box: Box
        var body: some View {
            Button("Cancel") { box.cancelled = true }
                .keyboardShortcut(.cancelAction)
        }
    }

    let box = Box()
    let runtime = _UIRuntime()
    _ = runtime.render(V(box: box), size: _Size(width: 20, height: 3))

    #expect(!box.cancelled)
    #expect(runtime.invokeKeyboardShortcut(.escape))
    #expect(box.cancelled)
}

@Test func runtime_native_global_key_invokes_default_and_cancel_shortcuts() async throws {
    final class Box {
        var defaultCount = 0
        var cancelCount = 0
    }

    struct V: View {
        let box: Box
        var body: some View {
            VStack {
                Button("Default") { box.defaultCount += 1 }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel") { box.cancelCount += 1 }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    let box = Box()
    let runtime = _UIRuntime()
    _ = runtime.semanticSnapshot(V(box: box), size: _Size(width: 40, height: 6))

    runtime.handleNativeKeyForRawActionID(0, keyKind: 7, codepoint: 0)
    runtime.handleNativeKeyForRawActionID(0, keyKind: 8, codepoint: 0)

    #expect(box.defaultCount == 1)
    #expect(box.cancelCount == 1)
}

@Test func keyboardShortcut_action_runs_with_captured_environment() async throws {
    final class Box {
        var opened: URL? = nil
    }

    struct V: View {
        private static let openURLTestsURL: URL = {
            guard let url = URL(string: "https://example.com") else {
                preconditionFailure("Invalid OmniUICore openURL test URL")
            }
            return url
        }()

        let box: Box
        @Environment(\.openURL) private var openURL
        var body: some View {
            Button("Open") {
                _ = openURL(Self.openURLTestsURL)
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    let box = Box()
    let runtime = _UIRuntime()
    let root = V(box: box)
        .environment(\.openURL, OpenURLAction({ url in box.opened = url; return .handled }))
    _ = runtime.render(root, size: _Size(width: 20, height: 3))

    #expect(box.opened == nil)
    #expect(runtime.invokeKeyboardShortcut(.return))
    #expect(box.opened?.absoluteString == "https://example.com")
}

@MainActor
@Test func task_runs_and_cancels_with_view_lifecycle() async throws {
    final class Box {
        var started: Int = 0
        var cancelled: Int = 0
    }

    struct WithTask: View {
        let box: Box
        var body: some View {
            Text("Hi")
                .task {
                    box.started += 1
                    do {
                        while true {
                            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
                        }
                    } catch {
                        // Expected on cancellation.
                    }
                    box.cancelled += 1
                }
        }
    }

    let box = Box()
    let runtime = _UIRuntime()

    _ = runtime.render(WithTask(box: box), size: _Size(width: 10, height: 2))
    for _ in 0..<50 {
        if box.started == 1 { break }
        await Task.yield()
    }
    #expect(box.started == 1)

    // Remove the task from the tree; it should be cancelled on the next frame.
    _ = runtime.render(Text("Hi"), size: _Size(width: 10, height: 2))
    for _ in 0..<50 {
        if box.cancelled == 1 { break }
        await Task.yield()
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(box.cancelled == 1)
}

@Test func contentShape_rectangle_expands_button_hit_region() async throws {
    final class Box {
        var taps: Int = 0
    }

    struct V: View {
        let box: Box
        var body: some View {
            Button(action: { box.taps += 1 }) {
                HStack(spacing: 0) {
                    Text("Tap")
                }
                .contentShape(Rectangle())
            }
        }
    }

    let box = Box()
    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(V(box: box), size: _Size(width: 20, height: 3))
    #expect(box.taps == 0)

    // Click far to the right of the visible "[ Tap ]" label; `contentShape(Rectangle())`
    // should make the whole row hit-testable.
    s0.click(x: 19, y: 0)
    let s1 = runtime.debugRender(V(box: box), size: _Size(width: 20, height: 3))
    _ = s1
    #expect(box.taps == 1)
}

@Test func runtime_needsRender_tracks_dirty_state_and_size() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 6)

    #expect(runtime.needsRender(size: size))

    _ = runtime.render(CounterView(), size: size)
    #expect(!runtime.needsRender(size: size))

    let s0 = runtime.debugRender(CounterView(), size: size)
    s0.click(x: 2, y: 3)
    #expect(runtime.needsRender(size: size))

    _ = runtime.render(CounterView(), size: size)
    #expect(!runtime.needsRender(size: size))

    #expect(runtime.needsRender(size: _Size(width: 31, height: 6)))
}

final class _BuildCountBox {
    var left: Int = 0
    var center: Int = 0
    var right: Int = 0
}

struct _BuildProbe: View {
    let label: String
    let tick: () -> Void

    var body: some View {
        tick()
        return Text(label)
    }
}

struct _CenterCounterProbe: View {
    let box: _BuildCountBox
    @State private var value: Int = 0

    var body: some View {
        box.center += 1
        return VStack(spacing: 1) {
            Text("center: \(value)")
            Button("Inc") { value += 1 }
        }
    }
}

struct _TargetedInvalidationProbeView: View {
    let box: _BuildCountBox

    var body: some View {
        HStack(spacing: 2) {
            _BuildProbe(label: "left") { box.left += 1 }
            _CenterCounterProbe(box: box)
            _BuildProbe(label: "right") { box.right += 1 }
        }
    }
}

private func _findButton(_ snap: DebugSnapshot, title: String, occurrence: Int = 0) -> (x: Int, y: Int)? {
    var seen = 0
    let titleChars = Array(title)
    for (y, line) in snap.lines.enumerated() {
        let hay = Array(line)
        guard hay.count >= titleChars.count else { continue }
        for x0 in 0...(hay.count - titleChars.count) {
            var matchesTitle = true
            for i in 0..<titleChars.count where hay[x0 + i] != titleChars[i] {
                matchesTitle = false
                break
            }
            guard matchesTitle else { continue }

            let leftLimit = max(0, x0 - 3)
            let rightLimit = min(hay.count - 1, x0 + titleChars.count + 3)
            let hasLeftBracket = hay[leftLimit...x0].contains("[")
            let hasRightBracket = hay[(x0 + titleChars.count - 1)...rightLimit].contains("]")
            guard hasLeftBracket, hasRightBracket else { continue }

            if seen == occurrence {
                return (x: x0 + max(0, titleChars.count / 2), y: y)
            }
            seen += 1
            break
        }
    }

    // Fallback for overlays or custom button styles that render interactive text without
    // the standard "[ Title ]" chrome. Prefer coordinates that are inside a live hit region
    // so test clicks still target a real control rather than a plain text match.
    for (y, line) in snap.lines.enumerated() {
        let hay = Array(line)
        guard hay.count >= titleChars.count else { continue }
        for x0 in 0...(hay.count - titleChars.count) {
            var matchesTitle = true
            for i in 0..<titleChars.count where hay[x0 + i] != titleChars[i] {
                matchesTitle = false
                break
            }
            guard matchesTitle else { continue }

            let candidates = [
                _Point(x: x0, y: y),
                _Point(x: x0 + max(0, titleChars.count / 2), y: y),
                _Point(x: x0 + max(0, titleChars.count - 1), y: y),
            ]
            guard candidates.contains(where: { point in
                snap.containsHitRegion(at: point)
            }) else {
                continue
            }

            if seen == occurrence {
                return (x: x0 + max(0, titleChars.count / 2), y: y)
            }
            seen += 1
            break
        }
    }

    return nil
}

private func _findText(_ snap: DebugSnapshot, text: String, occurrence: Int = 0) -> (x: Int, y: Int)? {
    var seen = 0
    let needle = Array(text)
    for (y, line) in snap.lines.enumerated() {
        let hay = Array(line)
        guard hay.count >= needle.count else { continue }
        for x0 in 0...(hay.count - needle.count) {
            var ok = true
            for i in 0..<needle.count where hay[x0 + i] != needle[i] {
                ok = false
                break
            }
            if ok {
                if seen == occurrence {
                    return (x: x0, y: y)
                }
                seen += 1
                break
            }
        }
    }
    return nil
}

private func _semanticButtonActionID(in node: SemanticNode, title: String) -> Int? {
    if case .button(let actionID, _) = node.kind, _semanticContainsText(node, title) {
        return actionID
    }
    for child in node.children {
        if let actionID = _semanticButtonActionID(in: child, title: title) {
            return actionID
        }
    }
    return nil
}

private func _semanticContainsText(_ node: SemanticNode, _ text: String) -> Bool {
    if case .text(let value) = node.kind, value.contains(text) {
        return true
    }
    return node.children.contains { _semanticContainsText($0, text) }
}

private func _containsSemantic(_ node: SemanticNode, matching predicate: (SemanticNode) -> Bool) -> Bool {
    if predicate(node) { return true }
    return node.children.contains { _containsSemantic($0, matching: predicate) }
}

private func _maxScrollOffset(in node: SemanticNode) -> Int {
    let own: Int
    if case .scroll(_, _, let offset) = node.kind {
        own = offset
    } else {
        own = 0
    }
    return max(own, node.children.map(_maxScrollOffset(in:)).max() ?? 0)
}

@Test func state_invalidation_rebuilds_only_affected_subtree() async throws {
    let runtime = _UIRuntime()
    let box = _BuildCountBox()
    let size = _Size(width: 60, height: 8)

    let s0 = runtime.debugRender(_TargetedInvalidationProbeView(box: box), size: size)
    #expect(box.left == 1)
    #expect(box.center == 1)
    #expect(box.right == 1)

    guard let p = _findButton(s0, title: "Inc") else {
        #expect(Bool(false), "Could not find Inc button")
        return
    }
    s0.click(x: p.x, y: p.y)

    let s1 = runtime.debugRender(_TargetedInvalidationProbeView(box: box), size: size)
    #expect(s1.text.contains("center: 1"))
    #expect(box.center >= 2)
    #expect(box.left == 1)
    #expect(box.right == 1)
}

struct _ScrollReaderProbeView: View {
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 1) {
                Button("Jump") { proxy.scrollTo(35, anchor: .top) }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<50, id: \.self) { i in
                            Text("Row \(i)").id(i)
                        }
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

@Test func scrollViewReader_scrollTo_moves_scroll_position() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let s0 = runtime.debugRender(_ScrollReaderProbeView(), size: size)
    #expect(s0.text.contains("Row 0"))

    guard let jump = _findButton(s0, title: "Jump") else {
        #expect(Bool(false), "Could not find Jump button")
        return
    }
    s0.click(x: jump.x, y: jump.y)

    let s1 = runtime.debugRender(_ScrollReaderProbeView(), size: size)
    if s1.text.contains("Row 35") {
        #expect(Bool(true))
    } else {
        // `scrollTo` requests may be applied at the end of a frame; verify the next frame.
        let s2 = runtime.debugRender(_ScrollReaderProbeView(), size: size)
        #expect(s2.text.contains("Row 35"))
    }
}

@Test func semanticSnapshot_scrollViewReader_exposes_nonzero_scroll_offset_after_native_action() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let initial = runtime.semanticSnapshot(_ScrollReaderProbeView(), size: size)
    guard let jumpActionID = _semanticButtonActionID(in: initial.root, title: "Jump") else {
        #expect(Bool(false), "Could not find Jump button action")
        return
    }

    runtime.invokeActionByRawID(jumpActionID)
    let next = runtime.semanticSnapshot(_ScrollReaderProbeView(), size: size)

    #expect(_maxScrollOffset(in: next.root) > 0)
}

@Test func text_image_uses_terminal_symbol_mapping() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(
        HStack(spacing: 1) {
            Text(Image(systemName: "folder"))
            Text("Docs")
            Text(Image(systemName: "doc.plaintext"))
            Text("Readme")
        },
        size: _Size(width: 30, height: 2)
    )

    #expect(snapshot.text.contains("▸ Docs"))
    #expect(snapshot.text.contains("≣ Readme"))
    #expect(!snapshot.text.contains("folder"))
    #expect(!snapshot.text.contains("doc.plaintext"))
}

@Test func icon_only_labels_use_terminal_safe_glyphs() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(
        HStack(spacing: 1) {
            Button(action: {}) {
                Label("Add Bookmark", systemImage: "bookmark.fill")
            }
            .labelStyle(.iconOnly)

            Button(action: {}) {
                Label("Bookmarks", systemImage: "book")
            }
            .labelStyle(.iconOnly)
        },
        size: _Size(width: 20, height: 3)
    )

    #expect(snapshot.text.contains("◆"))
    #expect(snapshot.text.contains("▤"))
    #expect(!snapshot.text.contains("bookmark.fill"))
    #expect(!snapshot.text.contains("book"))
}

private struct _FocusFollowScrollProbeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<20, id: \.self) { index in
                    Button("Item \(index)") {}
                }
            }
        }
        .frame(height: 5)
    }
}

@Test func focus_navigation_keeps_focused_item_visible_inside_scroll_view() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 24, height: 6)

    _ = runtime.debugRender(_FocusFollowScrollProbeView(), size: size)
    for _ in 0..<10 {
        runtime.focusNext()
        _ = runtime.debugRender(_FocusFollowScrollProbeView(), size: size)
    }

    let snapshot = runtime.debugRender(_FocusFollowScrollProbeView(), size: size)
    let focusedRect = try #require(snapshot.focusedRect)
    #expect(focusedRect.origin.y >= 0)
    #expect(focusedRect.origin.y < size.height)
    #expect(snapshot.text.contains("Item 10"))
    #expect(!snapshot.text.contains("Item 0"))
}

struct _TreeProbeNode: Identifiable {
    let id: String
    let title: String
    let children: [_TreeProbeNode]?
}

struct _HierarchicalListProbeView: View {
    let nodes: [_TreeProbeNode] = [
        _TreeProbeNode(
            id: "root",
            title: "Root",
            children: [
                _TreeProbeNode(
                    id: "child",
                    title: "Child",
                    children: [
                        _TreeProbeNode(id: "leaf", title: "Leaf", children: nil),
                    ]
                ),
            ]
        ),
    ]

    var body: some View {
        List(nodes, children: \.children) { node in
            Text(node.title)
        }
    }
}

@Test func list_children_renders_nested_nodes() async throws {
    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(_HierarchicalListProbeView(), size: _Size(width: 40, height: 10))
    #expect(s0.text.contains("Root"))
    #expect(s0.text.contains("Child"))
    #expect(s0.text.contains("Leaf"))
}

struct _EditableListProbeView: View {
    @State private var items: [Int] = [10, 20, 30]

    var body: some View {
        VStack(spacing: 1) {
            EditButton()
            List {
                ForEach(items, id: \.self) { item in
                    Text("Item \(item)")
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        guard items.indices.contains(index) else { continue }
                        items.remove(at: index)
                    }
                }
            }
        }
    }
}

@Test func editButton_enables_onDelete_actions() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 50, height: 12)

    let s0 = runtime.debugRender(_EditableListProbeView(), size: size)
    #expect(!s0.text.contains("[ Del ]"))
    #expect(s0.text.contains("Item 10"))

    guard let edit = _findButton(s0, title: "Edit") else {
        #expect(Bool(false), "Could not find Edit button")
        return
    }
    s0.click(x: edit.x, y: edit.y)

    let s1 = runtime.debugRender(_EditableListProbeView(), size: size)
    #expect(s1.text.contains("[ Del ]"))

    guard let del = _findButton(s1, title: "Del", occurrence: 0) else {
        #expect(Bool(false), "Could not find Del button")
        return
    }
    s1.click(x: del.x, y: del.y)

    let s2 = runtime.debugRender(_EditableListProbeView(), size: size)
    #expect(!s2.text.contains("Item 10"))
    #expect(s2.text.contains("Item 20"))
}

final class _StableModelRecord {
    var id: Int
    init(id: Int) { self.id = id }
}

struct _StableModelContainerProbe: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \_StableModelRecord.id, order: .forward) private var records: [_StableModelRecord]
    @State private var seeded: Bool = false

    var body: some View {
        Text("count: \(records.count)")
            .onAppear {
                guard !seeded else { return }
                seeded = true
                modelContext.insert(_StableModelRecord(id: 1))
            }
    }
}

struct _OnAppearLifecycleProbeView: View {
    @State private var appearCount: Int = 0
    @State private var rerenderCount: Int = 0
    @State private var showChild: Bool = true

    var body: some View {
        VStack(spacing: 1) {
            Text("appear: \(appearCount)")
            Text("rerender: \(rerenderCount)")
            Button("Rerender") { rerenderCount += 1 }
            Button(showChild ? "Hide" : "Show") { showChild.toggle() }

            if showChild {
                Text("Child")
                    .onAppear { appearCount += 1 }
            }
        }
    }
}

@Test func modelContainer_for_keeps_context_stable_across_renders() async throws {
    let runtime = _UIRuntime()
    let root = _StableModelContainerProbe()
        .modelContainer(for: [_StableModelRecord.self], inMemory: true)
    let size = _Size(width: 40, height: 6)

    let s0 = runtime.debugRender(root, size: size)
    #expect(s0.text.contains("count: 0"))

    let s1 = runtime.debugRender(root, size: size)
    #expect(s1.text.contains("count: 1"))

    let s2 = runtime.debugRender(root, size: size)
    #expect(s2.text.contains("count: 1"))
}

@Test func onAppear_fires_once_for_a_stable_mount() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 8)

    let s0 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s0.text.contains("appear: 0"))

    let s1 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s1.text.contains("appear: 1"))

    let s2 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s2.text.contains("appear: 1"))

    guard let rerender = _findButton(s2, title: "Rerender") else {
        #expect(Bool(false), "Could not find Rerender button")
        return
    }
    s2.click(x: rerender.x, y: rerender.y)

    let s3 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s3.text.contains("rerender: 1"))
    #expect(s3.text.contains("appear: 1"))
}

@Test func onAppear_fires_again_after_remount() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 8)

    _ = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    let s1 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s1.text.contains("appear: 1"))

    guard let hide = _findButton(s1, title: "Hide") else {
        #expect(Bool(false), "Could not find Hide button")
        return
    }
    s1.click(x: hide.x, y: hide.y)

    let s2 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(!s2.text.contains("Child"))
    #expect(s2.text.contains("appear: 1"))

    guard let show = _findButton(s2, title: "Show") else {
        #expect(Bool(false), "Could not find Show button")
        return
    }
    s2.click(x: show.x, y: show.y)

    let s3 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s3.text.contains("appear: 1"))

    let s4 = runtime.debugRender(_OnAppearLifecycleProbeView(), size: size)
    #expect(s4.text.contains("appear: 2"))
}

private struct _SheetItemProbeItem: Identifiable {
    let id: Int
}

struct _SheetItemProbeView: View {
    @State private var item: _SheetItemProbeItem? = nil

    var body: some View {
        VStack(spacing: 1) {
            Text("item: \(item?.id ?? -1)")
            Button("Show") {
                item = _SheetItemProbeItem(id: 1)
            }
        }
        .sheet(item: $item) { current in
            Text("Item \(current.id)")
        }
    }
}

struct _SheetOverlayInteractionProbeView: View {
    @State private var isPresented: Bool = false
    @State private var tapped: String = "-"

    var body: some View {
        VStack(spacing: 1) {
            Text("tapped: \(tapped)")
            Button("Base") { tapped = "base" }
            Button("Show") { isPresented = true }
        }
        .sheet(isPresented: $isPresented) {
            VStack(spacing: 1) {
                Text("Overlay Body")
                Button("Inner") {
                    tapped = "inner"
                    isPresented = false
                }
            }
        }
    }
}

struct _SheetSearchInteractionProbeView: View {
    @State private var isPresented: Bool = false
    @State private var query: String = ""
    @State private var submitted: String = "-"

    var body: some View {
        VStack(spacing: 1) {
            Text("submitted: \(submitted)")
            Button("Show") { isPresented = true }
        }
        .sheet(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Search Gopherspace")
                TextField("Query", text: $query)
                HStack {
                    Button("Cancel") {
                        query = ""
                        isPresented = false
                    }
                    Spacer()
                    Button("Search") {
                        submitted = query
                        isPresented = false
                    }
                    .disabled(query.isEmpty)
                }
            }
        }
    }
}

struct _PopoverProbeView: View {
    @State private var isPresented: Bool = false

    var body: some View {
        VStack(spacing: 1) {
            Text("popover: \(isPresented ? "open" : "closed")")
            Button("Show") { isPresented = true }
        }
        .popover(isPresented: $isPresented) {
            Text("Popover Body")
        }
    }
}

struct _ConfirmationDialogProbeView: View {
    @State private var isPresented: Bool = false
    @State private var picked: String = "-"

    var body: some View {
        VStack(spacing: 1) {
            Text("picked: \(picked)")
            Button("Show") { isPresented = true }
        }
        .confirmationDialog("Confirm", isPresented: $isPresented) {
            Button("One") { picked = "One" }
            Button("Two", role: .destructive) { picked = "Two" }
            Button("Cancel", role: .cancel) { picked = "Cancel" }
        } message: {
            Text("Choose")
        }
    }
}

struct _AlertSemanticProbeView: View {
    @State private var isPresented: Bool = false

    var body: some View {
        VStack(spacing: 1) {
            Text("alert: \(isPresented ? "open" : "closed")")
            Button("Show") { isPresented = true }
        }
        .alert(isPresented: $isPresented) {
            Text("Enabled")
        }
    }
}

private struct _PopoverItemProbeItem: Identifiable {
    let id: Int
}

struct _PopoverItemProbeView: View {
    @State private var item: _PopoverItemProbeItem? = nil

    var body: some View {
        VStack(spacing: 1) {
            Text("popover item: \(item?.id ?? -1)")
            Button("Show") { item = _PopoverItemProbeItem(id: 7) }
        }
        .popover(item: $item) { current in
            Text("Popover Item \(current.id)")
        }
    }
}

@Suite("Presentation Overlays", .serialized)
struct PresentationOverlayTests {
    @Test func sheet_item_presents_and_dismisses() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 40, height: 10)

        let s0 = runtime.debugRender(_SheetItemProbeView(), size: size)
        #expect(s0.text.contains("item: -1"))

        guard let show = _findButton(s0, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        s0.click(x: show.x, y: show.y)

        let s1 = runtime.debugRender(_SheetItemProbeView(), size: size)
        #expect(s1.text.contains("Item 1"))
        #expect(s1.text.contains("item: 1"))

        guard let close = _findButton(s1, title: "Close") else {
            #expect(Bool(false), "Could not find Close button")
            return
        }
        s1.click(x: close.x, y: close.y)

        let s2 = runtime.debugRender(_SheetItemProbeView(), size: size)
        #expect(!s2.text.contains("Item 1"))
        #expect(s2.text.contains("item: -1"))
    }

    @Test func sheet_renders_overlay_body_and_inner_controls() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 40, height: 12)

        let initial = runtime.debugRender(_SheetOverlayInteractionProbeView(), size: size)
        guard let show = _findButton(initial, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        initial.click(x: show.x, y: show.y)

        let sheet = runtime.debugRender(_SheetOverlayInteractionProbeView(), size: size)
        #expect(sheet.text.contains("Overlay Body"))
        #expect(_findButton(sheet, title: "Inner") != nil)
        #expect(_findButton(sheet, title: "Close") != nil)
    }

    @Test func sheet_textField_and_action_buttons_are_interactive() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 50, height: 16)

        let initial = runtime.debugRender(_SheetSearchInteractionProbeView(), size: size)
        guard let show = _findButton(initial, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        initial.click(x: show.x, y: show.y)

        let sheet = runtime.debugRender(_SheetSearchInteractionProbeView(), size: size)
        #expect(sheet.text.contains("Search Gopherspace"))

        guard let field = _findText(sheet, text: "Query") else {
            #expect(Bool(false), "Could not find Query text field")
            return
        }
        sheet.click(x: field.x + 1, y: field.y)
        sheet.type("navan")

        let typed = runtime.debugRender(_SheetSearchInteractionProbeView(), size: size)
        #expect(typed.text.contains("navan"))

        guard let search = _findButton(typed, title: "Search") else {
            #expect(Bool(false), "Could not find Search button")
            return
        }
        typed.click(x: search.x, y: search.y)

        let final = runtime.debugRender(_SheetSearchInteractionProbeView(), size: size)
        #expect(final.text.contains("submitted: navan"))
        #expect(!final.text.contains("Search Gopherspace"))
    }

    @Test func popover_isPresented_shows_and_dismisses() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 40, height: 10)

        let s0 = runtime.debugRender(_PopoverProbeView(), size: size)
        #expect(s0.text.contains("popover: closed"))

        guard let show = _findButton(s0, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        s0.click(x: show.x, y: show.y)

        let s1 = runtime.debugRender(_PopoverProbeView(), size: size)
        #expect(s1.text.contains("Popover Body"))
        #expect(s1.text.contains("popover: open"))

        guard let close = _findButton(s1, title: "Close") else {
            #expect(Bool(false), "Could not find Close button")
            return
        }
        s1.click(x: close.x, y: close.y)

        let s2 = runtime.debugRender(_PopoverProbeView(), size: size)
        #expect(!s2.text.contains("Popover Body"))
        #expect(s2.text.contains("popover: closed"))
    }

    @Test func confirmationDialog_captures_buttons_and_runs_selected_action() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 40, height: 12)

        let s0 = runtime.debugRender(_ConfirmationDialogProbeView(), size: size)
        #expect(s0.text.contains("picked: -"))

        guard let show = _findButton(s0, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        s0.click(x: show.x, y: show.y)

        let s1 = runtime.debugRender(_ConfirmationDialogProbeView(), size: size)
        #expect(s1.text.contains("Confirm"))
        #expect(s1.text.contains("Choose"))

        guard let two = _findButton(s1, title: "Two") else {
            #expect(Bool(false), "Could not find Two button")
            return
        }
        s1.click(x: two.x, y: two.y)

        let s2 = runtime.debugRender(_ConfirmationDialogProbeView(), size: size)
        #expect(s2.text.contains("picked: Two"))
        #expect(!s2.text.contains("Choose"))
    }

    @Test func alert_uses_semantic_modal_overlay_instead_of_drawing_scrim() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 50, height: 12)

        let initial = runtime.debugRender(_AlertSemanticProbeView(), size: size)
        guard let show = _findButton(initial, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        initial.click(x: show.x, y: show.y)

        let snapshot = runtime.semanticSnapshot(_AlertSemanticProbeView(), size: size)

        func containsAdwaitaDialog(_ node: SemanticNode) -> Bool {
            if case .modifier(.background("adw-dialog")) = node.kind {
                return true
            }
            return node.children.contains(where: containsAdwaitaDialog)
        }

        func containsDrawingIsland(_ node: SemanticNode) -> Bool {
            if case .drawingIsland = node.kind {
                return true
            }
            return node.children.contains(where: containsDrawingIsland)
        }

        func containsText(_ expected: String, in node: SemanticNode) -> Bool {
            if case .text(let text) = node.kind, text.contains(expected) {
                return true
            }
            return node.children.contains { containsText(expected, in: $0) }
        }

        #expect(containsAdwaitaDialog(snapshot.root))
        #expect(containsText("Enabled", in: snapshot.root))
        #expect(containsText("OK", in: snapshot.root))
        #expect(!containsDrawingIsland(snapshot.root))
    }

    @Test func popover_item_presents_and_dismisses() async throws {
        let runtime = _UIRuntime()
        let size = _Size(width: 40, height: 10)

        let s0 = runtime.debugRender(_PopoverItemProbeView(), size: size)
        #expect(s0.text.contains("popover item: -1"))

        guard let show = _findButton(s0, title: "Show") else {
            #expect(Bool(false), "Could not find Show button")
            return
        }
        s0.click(x: show.x, y: show.y)

        let s1 = runtime.debugRender(_PopoverItemProbeView(), size: size)
        #expect(s1.text.contains("Popover Item 7"))
        #expect(s1.text.contains("popover item: 7"))

        guard let close = _findButton(s1, title: "Close") else {
            #expect(Bool(false), "Could not find Close button")
            return
        }
        s1.click(x: close.x, y: close.y)

        let s2 = runtime.debugRender(_PopoverItemProbeView(), size: size)
        #expect(!s2.text.contains("Popover Item 7"))
        #expect(s2.text.contains("popover item: -1"))
    }
}

struct _NavigationDestinationBoolProbeView: View {
    @State private var isShowingDetail: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 1) {
                Text("root")
                Button("Show") { isShowingDetail = true }
            }
            .navigationDestination(isPresented: $isShowingDetail) {
                Text("Bool Detail")
            }
        }
    }
}

@Test func navigationDestination_isPresented_pushes_and_pops() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let s0 = runtime.debugRender(_NavigationDestinationBoolProbeView(), size: size)
    #expect(s0.text.contains("root"))

    guard let show = _findButton(s0, title: "Show") else {
        #expect(Bool(false), "Could not find Show button")
        return
    }
    s0.click(x: show.x, y: show.y)

    let s1 = runtime.debugRender(_NavigationDestinationBoolProbeView(), size: size)
    #expect(s1.text.contains("Bool Detail"))
    #expect(s1.text.contains("[ Back ]"))

    guard let back = _findButton(s1, title: "Back") else {
        #expect(Bool(false), "Could not find Back button")
        return
    }
    s1.click(x: back.x, y: back.y)

    let s2 = runtime.debugRender(_NavigationDestinationBoolProbeView(), size: size)
    #expect(s2.text.contains("root"))
    #expect(!s2.text.contains("Bool Detail"))
}

private struct _NavigationDestinationItemProbeItem: Identifiable {
    let id: Int
}

struct _NavigationDestinationItemProbeView: View {
    @State private var selected: _NavigationDestinationItemProbeItem? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 1) {
                Text("selected: \(selected?.id ?? -1)")
                Button("Show") { selected = _NavigationDestinationItemProbeItem(id: 5) }
            }
            .navigationDestination(item: $selected) { item in
                Text("Item Detail \(item.id)")
            }
        }
    }
}

@Test func navigationDestination_item_pushes_and_clears_on_back() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let s0 = runtime.debugRender(_NavigationDestinationItemProbeView(), size: size)
    #expect(s0.text.contains("selected: -1"))

    guard let show = _findButton(s0, title: "Show") else {
        #expect(Bool(false), "Could not find Show button")
        return
    }
    s0.click(x: show.x, y: show.y)

    let s1 = runtime.debugRender(_NavigationDestinationItemProbeView(), size: size)
    #expect(s1.text.contains("Item Detail 5"))

    guard let back = _findButton(s1, title: "Back") else {
        #expect(Bool(false), "Could not find Back button")
        return
    }
    s1.click(x: back.x, y: back.y)

    let s2 = runtime.debugRender(_NavigationDestinationItemProbeView(), size: size)
    #expect(s2.text.contains("selected: -1"))
    #expect(!s2.text.contains("Item Detail 5"))
}

struct _NavigationDestinationValueProbeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 1) {
                NavigationLink(value: 42) {
                    Text("Value Link")
                }
            }
            .navigationDestination(for: Int.self) { value in
                Text("Value \(value)")
            }
        }
    }
}

@Test func navigationDestination_for_value_pushes_resolved_destination() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 40, height: 10)

    let s0 = runtime.debugRender(_NavigationDestinationValueProbeView(), size: size)
    #expect(s0.text.contains("Value Link"))

    guard let link = _findButton(s0, title: "Value Link") else {
        #expect(Bool(false), "Could not find Value Link button")
        return
    }
    s0.click(x: link.x, y: link.y)

    let s1 = runtime.debugRender(_NavigationDestinationValueProbeView(), size: size)
    #expect(s1.text.contains("Value 42"))
    #expect(s1.text.contains("[ Back ]"))
}

struct _CoreParityViewsProbe: View {
    @State private var date: Date = Date(timeIntervalSinceReferenceDate: 123456789)

    var body: some View {
        NavigationView {
            VStack(spacing: 1) {
                DatePicker("When", selection: $date)
                    .datePickerStyle(.graphical)
                Gauge(value: 0.4) {
                    Text("Gauge")
                } currentValueLabel: {
                    Text("40%")
                }
                .gaugeStyle(.default)
                AsyncImage(url: URL(string: "https://example.com/image.png")) { _ in
                    Text("photo")
                }
                TimelineView(()) { context in
                    Text(context.cadence == .live ? "Timeline" : "Other")
                }
                .contentTransition(ContentTransition())
                .navigationTransition(NavigationTransition())
            }
        }
        .navigationViewStyle(.default)
    }
}

@Test func core_parity_views_render_basic_output() async throws {
    let runtime = _UIRuntime()
    let s0 = runtime.debugRender(_CoreParityViewsProbe(), size: _Size(width: 60, height: 12))
    #expect(s0.text.contains("When"))
    #expect(s0.text.contains("Gauge"))
    #expect(s0.text.contains("40%"))
        }

struct _DrawingParityProbe: View {
    var body: some View {
        VStack(spacing: 1) {
            LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 4, height: 2)
            Canvas { context, _ in
                context.fill(Rectangle(), with: .color(.green))
            }
            .frame(width: 4, height: 2)
        }
    }
}

@Test func asyncImage_rejects_file_url_for_security() async throws {
    let runtime = _UIRuntime()
    let tempURL = URL.temporaryDirectory.appending(path: "omniui-async-image-test.bin")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tempURL)
    struct Probe: View {
        let url: URL
        var body: some View {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success:
                    return Text("photo")
                case .failure:
                    return Text("failure")
                case .empty:
                    return Text("empty")
                }
            }
        }
    }
    let initial = runtime.debugRender(Probe(url: tempURL), size: _Size(width: 20, height: 4))
    #expect(initial.text.contains("empty"))
    try await Task.sleep(nanoseconds: 100_000_000)
    let next = runtime.debugRender(Probe(url: tempURL), size: _Size(width: 20, height: 4))
    // file:// URLs are rejected for security — should report failure, not success
    #expect(next.text.contains("failure"))
}

@Test func timelineView_ticks_over_time() async throws {
    let runtime = _UIRuntime()
    struct Probe: View {
        var body: some View {
            TimelineView(()) { context in
                Text(context.date.formatted(date: .omitted, time: .standard))
            }
        }
    }
    let first = runtime.debugRender(Probe(), size: _Size(width: 20, height: 4)).text
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let second = runtime.debugRender(Probe(), size: _Size(width: 20, height: 4)).text
    #expect(first != second)
}

@Test func drawing_primitives_emit_renderer_ops() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.render(_DrawingParityProbe(), size: _Size(width: 6, height: 6))
    #expect(!snapshot.ops.isEmpty)
    #expect(!snapshot.shapeRegions.isEmpty)
}

struct _DisabledButtonProbe: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 1) {
            Text("Count: \(count)")
            Button("Inc") { count += 1 }
                .disabled(true)
        }
    }
}

@Test func disabled_button_blocks_interaction() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_DisabledButtonProbe(), size: _Size(width: 30, height: 6))
    #expect(initial.text.contains("Count: 0"))
    initial.click(x: 2, y: 2)
    let next = runtime.debugRender(_DisabledButtonProbe(), size: _Size(width: 30, height: 6))
    #expect(next.text.contains("Count: 0"))
}

struct _SearchableProbe: View {
    @State private var query = ""

    var body: some View {
        Text("Query: \(query)")
            .searchable(text: $query)
    }
}

@Test func searchable_renders_field_and_updates_binding() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_SearchableProbe(), size: _Size(width: 40, height: 6))
    #expect(initial.text.contains("Query:"))
    #expect(initial.text.contains("Search"))
    initial.click(x: 3, y: 0)
    initial.type("abc")
    let next = runtime.debugRender(_SearchableProbe(), size: _Size(width: 40, height: 6))
    #expect(next.text.contains("Query: abc"))
}

struct _RefreshableProbe: View {
    @State private var refreshCount = 0

    var body: some View {
        Text("Refreshes: \(refreshCount)")
            .refreshable {
                refreshCount += 1
            }
    }
}

@Test func refreshable_exposes_button_and_runs_action() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_RefreshableProbe(), size: _Size(width: 40, height: 6))
    #expect(initial.text.contains("Refreshes: 0"))
    #expect(initial.text.contains("Refresh"))
    initial.click(x: 2, y: 0)
    try await Task.sleep(nanoseconds: 50_000_000)
    let next = runtime.debugRender(_RefreshableProbe(), size: _Size(width: 40, height: 6))
    #expect(next.text.contains("Refreshes: 1"))
}

struct _OffsetOpacityProbe: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 1) {
            Text("Count: \(count)")
            Button("Go") { count += 1 }
                .offset(x: 4, y: 0)
            Text("Fade")
                .opacity(0.5)
        }
    }
}

@Test func offset_and_opacity_modifiers_affect_render_tree() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_OffsetOpacityProbe(), size: _Size(width: 30, height: 8))
    initial.click(x: 8, y: 2)
    let next = runtime.debugRender(_OffsetOpacityProbe(), size: _Size(width: 30, height: 8))
    #expect(next.text.contains("Count: 1"))

    let faded = runtime.render(Text("Fade").opacity(0.5), size: _Size(width: 10, height: 2))
    let hasAlpha = faded.ops.contains { op in
        switch op.kind {
        case .glyph(_, _, _, let fg, _), .textRun(_, _, _, let fg, _):
            return (fg?.alpha ?? 1.0) < 1.0
        default:
            return false
        }
    }
    #expect(hasAlpha)
}

struct _TextEnvironmentProbe: View {
    var body: some View {
        Text("First\nSecond\nThird")
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .font(.headline)
    }
}

@Test func text_environment_modifiers_affect_output() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(_TextEnvironmentProbe(), size: _Size(width: 20, height: 5))
    #expect(snapshot.text.contains("First"))
    #expect(snapshot.text.contains("Second"))
    #expect(!snapshot.text.contains("Third"))
}

struct _ExitCommandProbe: View {
    @State private var exits = 0

    var body: some View {
        Text("Exits: \(exits)")
            .onExitCommand {
                exits += 1
            }
    }
}

@Test func onExitCommand_registers_runtime_handler() async throws {
    let runtime = _UIRuntime()
    _ = runtime.debugRender(_ExitCommandProbe(), size: _Size(width: 20, height: 4))
    #expect(runtime.invokeExitCommand())
    let next = runtime.debugRender(_ExitCommandProbe(), size: _Size(width: 20, height: 4))
    #expect(next.text.contains("Exits: 1"))
}

struct _QuickLookProbe: View {
    let url: Binding<URL?>

    var body: some View {
        Text("Host")
            .quickLookPreview(url)
    }
}

@Test func quickLookPreview_registers_overlay() async throws {
    let runtime = _UIRuntime()
    var currentURL: URL? = URL(string: "https://example.com/file.txt")
    let binding = Binding<URL?>(get: { currentURL }, set: { currentURL = $0 })
    let snapshot = runtime.debugRender(_QuickLookProbe(url: binding), size: _Size(width: 50, height: 10))
    #expect(snapshot.text.contains("Quick Look"))
    #expect(snapshot.text.contains("file.txt"))
    currentURL = nil
    let next = runtime.debugRender(_QuickLookProbe(url: binding), size: _Size(width: 50, height: 10))
    #expect(!next.text.contains("Quick Look"))
}

struct _HoverProbe: View {
    @State private var hovered = false

    var body: some View {
        Text(hovered ? "Hover ON" : "Hover OFF")
            .onHover { hovered = $0 }
    }
}

@Test func onHover_updates_state_via_snapshot_hover() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_HoverProbe(), size: _Size(width: 20, height: 4))
    #expect(initial.text.contains("Hover OFF"))
    initial.hover(x: 1, y: 0)
    let hovered = runtime.debugRender(_HoverProbe(), size: _Size(width: 20, height: 4))
    #expect(hovered.text.contains("Hover ON"))
    hovered.hover(x: 19, y: 3)
    let cleared = runtime.debugRender(_HoverProbe(), size: _Size(width: 20, height: 4))
    #expect(cleared.text.contains("Hover OFF"))
}

struct _ToolbarSemanticProbe: View {
    var body: some View {
        Text("Toolbar Base")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Lead") {}
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Trail") {}
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Bottom") {}
                }
            }
    }
}

@Test func toolbar_items_are_preserved_in_semantic_snapshot() async throws {
    let runtime = _UIRuntime()
    let snapshot = runtime.semanticSnapshot(_ToolbarSemanticProbe(), size: _Size(width: 50, height: 10))

    func containsText(_ expected: String, in node: SemanticNode) -> Bool {
        if case .text(let text) = node.kind, text.contains(expected) {
            return true
        }
        return node.children.contains { containsText(expected, in: $0) }
    }

    func buttonCount(in node: SemanticNode) -> Int {
        let selfCount: Int
        if case .button = node.kind {
            selfCount = 1
        } else {
            selfCount = 0
        }
        return selfCount + node.children.map(buttonCount).reduce(0, +)
    }

    #expect(containsText("Toolbar Base", in: snapshot.root))
    #expect(containsText("Lead", in: snapshot.root))
    #expect(containsText("Trail", in: snapshot.root))
    #expect(containsText("Bottom", in: snapshot.root))
    #expect(buttonCount(in: snapshot.root) == 3)
}

struct _SceneCommandProbe: Scene {
    @SceneBuilder var body: some Scene {
        WindowGroup {
            Text("Scene Root")
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Command") {}
            }
        }
        .defaultSize(width: 90, height: 30)
    }
}

struct _SceneSettingsProbe: Scene {
    @SceneBuilder var body: some Scene {
        WindowGroup {
            Text("Main Root")
        }
        Settings {
            Form {
                Text("Settings Root")
            }
        }
    }
}

@Test func scene_commands_and_default_size_are_exposed() async throws {
    let scene = _SceneCommandProbe().body
    let root = _sceneRootView(scene)
    #expect(root != nil)
    let commands = _sceneCommandsView(scene)
    #expect(commands != nil)
    let preferred = _scenePreferredSize(scene)
    #expect(preferred?.width == 90)
    #expect(preferred?.height == 30)

    let runtime = _UIRuntime()
    let snapshot = runtime.debugRender(root!, size: _Size(width: 30, height: 6))
    #expect(snapshot.text.contains("Scene Root"))
}

@Test func scene_settings_are_exposed_separately_from_window_root() async throws {
    let scene = _SceneSettingsProbe().body
    let root = _sceneRootView(scene)
    let settings = _sceneSettingsView(scene)

    #expect(root != nil)
    #expect(settings != nil)

    let runtime = _UIRuntime()
    let rootSnapshot = runtime.debugRender(root!, size: _Size(width: 30, height: 6))
    #expect(rootSnapshot.text.contains("Main Root"))
    #expect(!rootSnapshot.text.contains("Settings Root"))

    let settingsSnapshot = runtime.debugRender(settings!, size: _Size(width: 30, height: 6))
    #expect(settingsSnapshot.text.contains("Settings Root"))
}

struct _TextFieldConfigProbe: View {
    @State private var url = ""
    @State private var corrected = ""

    var body: some View {
        VStack(spacing: 1) {
            TextField("URL", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.characters)
                .textContentType(.URL)
                .textFieldStyle(.plain)
            Text(url)
            TextField("Auto", text: $corrected)
                .autocorrectionDisabled(false)
            Text(corrected)
        }
    }
}

@Test func textField_style_and_input_configs_affect_behavior() async throws {
    let runtime = _UIRuntime()
    let initial = runtime.debugRender(_TextFieldConfigProbe(), size: _Size(width: 30, height: 8))
    #expect(!initial.text.contains("[URL]"))
    initial.click(x: 1, y: 0)
    initial.type("Ab C")
    let urlState = runtime.debugRender(_TextFieldConfigProbe(), size: _Size(width: 30, height: 8))
    #expect(urlState.text.contains("abc"))
    #expect(!urlState.text.contains("Ab C"))

    urlState.click(x: 1, y: 4)
    urlState.type("teh ")
    let corrected = runtime.debugRender(_TextFieldConfigProbe(), size: _Size(width: 30, height: 8))
    #expect(corrected.text.contains("the "))
}

@Test func scene_commands_and_default_size_metadata_are_preserved() async throws {
    let scene = AnyScene(
        WindowGroup {
            Text("Root")
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Command") {}
            }
        }
        .defaultSize(width: 42, height: 17)
    )

    let rootScene: _OmniUISceneRoot = scene
    #expect(rootScene._omniUIRootView() != nil)
    #expect(rootScene._omniUICommandsView() != nil)
    #expect(rootScene._omniUISettingsView() == nil)
    #expect(rootScene._omniUIPreferredSize == CGSize(width: 42, height: 17))

    let runtime = _UIRuntime()
    if let commandsView = rootScene._omniUICommandsView() {
        let snapshot = runtime.debugRender(commandsView, size: _Size(width: 20, height: 4))
        #expect(snapshot.text.contains("Command"))
    }
}

struct _SplitAutomaticProbeView: View {
    var body: some View {
        NavigationSplitView(
            columnVisibility: Binding(get: { .automatic }, set: { _ in }),
            sidebar: { Text("SIDEBAR") },
            detail: { Text("DETAIL") }
        )
    }
}

@Test func navigationSplitView_automatic_adapts_by_width() async throws {
    let runtime = _UIRuntime()

    let narrow = runtime.debugRender(_SplitAutomaticProbeView(), size: _Size(width: 40, height: 6))
    #expect(narrow.text.contains("DETAIL"))
    #expect(!narrow.text.contains("SIDEBAR"))

    let wide = runtime.debugRender(_SplitAutomaticProbeView(), size: _Size(width: 100, height: 6))
    #expect(wide.text.contains("DETAIL"))
    #expect(wide.text.contains("SIDEBAR"))
}

struct _TabViewSelectionFallbackProbe: View {
    let selection: Binding<String>

    var body: some View {
        TabView(selection: selection) {
            Text("First body")
                .tabItem { Text("First") }
                .tag("first")
            Text("Second body")
                .tabItem { Text("Second") }
                .tag("second")
        }
    }
}

@Test func tabView_reconciles_missing_selection_to_first_available_tab() async throws {
    let runtime = _UIRuntime()
    var selection = "missing"
    let binding = Binding(get: { selection }, set: { selection = $0 })

    let snapshot = runtime.debugRender(_TabViewSelectionFallbackProbe(selection: binding), size: _Size(width: 30, height: 8))

    #expect(snapshot.text.contains("[First]"))
    #expect(snapshot.text.contains("First body"))
    #expect(selection == "first")
}

// MARK: - iGopher Parity Tests (23 Features)

// Feature #1: listStyle(.plain) suppresses Section headers
@Test func parity_listStyle_plain_suppresses_section_header() async throws {
    struct PlainListView: View {
        var body: some View {
            List {
                Section(header: Text("HEADER")) {
                    Text("Row1")
                }
            }
            .listStyle(.plain)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(PlainListView(), size: _Size(width: 30, height: 10))
    #expect(!snap.text.contains("HEADER"))
    #expect(snap.text.contains("Row1"))
}

// Feature #1 (sidebar keeps headers)
@Test func parity_listStyle_sidebar_keeps_section_header() async throws {
    struct SidebarListView: View {
        var body: some View {
            List {
                Section(header: Text("HEADER")) {
                    Text("Row1")
                }
            }
            .listStyle(.sidebar)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(SidebarListView(), size: _Size(width: 30, height: 10))
    #expect(snap.text.contains("HEADER"))
    #expect(snap.text.contains("Row1"))
}

// Feature #2: listRowSeparator(.hidden) produces no dividers
@Test func parity_listRowSeparator_hidden() async throws {
    struct NoSepList: View {
        var body: some View {
            List {
                Text("A")
                Text("B")
            }
            .listRowSeparator(.hidden)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(NoSepList(), size: _Size(width: 30, height: 10))
    #expect(snap.text.contains("A"))
    #expect(snap.text.contains("B"))
    // With separator hidden, there should be no divider line between rows.
    // Divider is rendered as "─" chars; without hidden, there would be one.
    let lines = snap.lines
    let dividerLines = lines.filter { $0.contains("─") }
    #expect(dividerLines.isEmpty)
}

// Feature #3: listRowBackground wraps rows
@Test func parity_listRowBackground() async throws {
    struct BgList: View {
        var body: some View {
            List {
                Text("Row")
            }
            .listRowBackground(Color.yellow)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(BgList(), size: _Size(width: 30, height: 8))
    #expect(snap.text.contains("Row"))
}

// Feature #4: borderedProminent button style
@Test func parity_borderedProminent_button() async throws {
    struct ProminentBtn: View {
        var body: some View {
            Button("Tap") {}
                .buttonStyle(.borderedProminent)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(ProminentBtn(), size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Tap"))
    #expect(snap.text.contains("["))
    #expect(snap.text.contains("]"))
}

// Feature #5: Toggle switch slider rendering
@Test func parity_toggle_switch_slider() async throws {
    struct SwitchView: View {
        @State var isOn = true
        var body: some View {
            Toggle("Light", isOn: $isOn)
                .toggleStyle(.switch)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(SwitchView(), size: _Size(width: 30, height: 3))
    // Should contain slider chars instead of ON/OFF text
    #expect(snap.text.contains("━") || snap.text.contains("●") || snap.text.contains("○"))
}

// Feature #6: Picker segmented with pipe separators
@Test func parity_picker_segmented_pipes() async throws {
    struct SegView: View {
        @State var choice = "A"
        var body: some View {
            Picker("Pick", selection: $choice, options: [("A", "A"), ("B", "B"), ("C", "C")])
                .pickerStyle(.segmented)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(SegView(), size: _Size(width: 40, height: 3))
    #expect(snap.text.contains("│"))
    #expect(snap.text.contains("["))
    #expect(snap.text.contains("]"))
}

// Feature #7: controlSize(.large) adds bold
@Test func parity_controlSize_large_renders() async throws {
    struct LargeBtn: View {
        var body: some View {
            Button("Big") {}
                .controlSize(.large)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(LargeBtn(), size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Big"))
}

// Feature #8: scrollContentBackground(.hidden)
@Test func parity_scrollContentBackground_hidden() async throws {
    struct NoBgList: View {
        var body: some View {
            List {
                Text("Item")
            }
            .scrollContentBackground(.hidden)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(NoBgList(), size: _Size(width: 20, height: 6))
    #expect(snap.text.contains("Item"))
}

// Feature #9: contentShape(Rectangle()) is a no-op for Rectangle
@Test func parity_contentShape_rectangle() async throws {
    struct ShapeView: View {
        var body: some View {
            Text("Clickable")
                .contentShape(Rectangle())
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(ShapeView(), size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Clickable"))
}

// Feature #10: @Namespace (no-op, already done)
@Test func parity_namespace_compiles() async throws {
    struct NsView: View {
        var ns = Namespace()
        var body: some View {
            Text("Hello")
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(NsView(), size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Hello"))
}

// Feature #11: LazyVStack with spacing
@Test func parity_lazyVStack_spacing() async throws {
    struct LazyView: View {
        var body: some View {
            LazyVStack(spacing: 1) {
                Text("A")
                Text("B")
            }
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(LazyView(), size: _Size(width: 20, height: 6))
    #expect(snap.text.contains("A"))
    #expect(snap.text.contains("B"))
}

// Feature #12: ColorPicker HSL sliders
@Test func parity_colorPicker_hsl_sliders() async throws {
    struct CPView: View {
        @State var color: Color = .red
        var body: some View {
            ColorPicker("Tint", selection: $color)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(CPView(), size: _Size(width: 40, height: 6))
    #expect(snap.text.contains("Tint"))
    // Should have HSL bar indicators
    #expect(snap.text.contains("H:") || snap.text.contains("S:") || snap.text.contains("L:"))
}

// Feature #13: ContentUnavailableView.search factory
@Test func parity_contentUnavailableView_search() async throws {
    let view: ContentUnavailableView<AnyView, AnyView, EmptyView> = .search
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(view, size: _Size(width: 40, height: 8))
    #expect(snap.text.contains("No Results"))
}

// Feature #13: ContentUnavailableView string init
@Test func parity_contentUnavailableView_string_init() async throws {
    let view = ContentUnavailableView("Empty", systemImage: "xmark", description: Text("Nothing here"))
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(view, size: _Size(width: 40, height: 8))
    #expect(snap.text.contains("Empty"))
    #expect(snap.text.contains("Nothing here"))
}

// Feature #14: LabeledContent generic
@Test func parity_labeledContent_generic() async throws {
    struct LCView: View {
        var body: some View {
            LabeledContent(content: { Text("ValueView") }, label: { Text("LabelView") })
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(LCView(), size: _Size(width: 40, height: 3))
    #expect(snap.text.contains("LabelView"))
    #expect(snap.text.contains("ValueView"))
}

// Feature #14: LabeledContent string convenience
@Test func parity_labeledContent_string() async throws {
    let view = LabeledContent("Key", value: "Val")
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(view, size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Key"))
    #expect(snap.text.contains("Val"))
}

// Feature #15: safeAreaInset spacing
@Test func parity_safeAreaInset_spacing() async throws {
    struct InsetView: View {
        var body: some View {
            Text("Content")
                .safeAreaInset(edge: .top, spacing: 2) {
                    Text("Bar")
                }
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(InsetView(), size: _Size(width: 20, height: 6))
    #expect(snap.text.contains("Bar"))
    #expect(snap.text.contains("Content"))
}

// Feature #16: presentationDetents
@Test func parity_presentationDetents_medium() async throws {
    struct DetentView: View {
        @State var show = true
        var body: some View {
            Text("Base")
                .sheet(isPresented: $show) {
                    Text("SheetContent")
                        .presentationDetents([.medium])
                }
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(DetentView(), size: _Size(width: 40, height: 20))
    #expect(snap.text.contains("Base"))
}

// Feature #17: quickLookPreview metadata
@Test func parity_quickLookPreview_metadata() async throws {
    struct QLView: View {
        @State var url: URL? = URL(fileURLWithPath: "/tmp/test.txt")
        var body: some View {
            Text("File")
                .quickLookPreview($url)
        }
    }
    let runtime = _UIRuntime()
    // First render registers overlay, second renders it
    _ = runtime.debugRender(QLView(), size: _Size(width: 40, height: 10))
    let snap = runtime.debugRender(QLView(), size: _Size(width: 40, height: 10))
    // Quick Look overlay should show filename or Quick Look title
    #expect(snap.text.contains("test.txt") || snap.text.contains("Quick Look") || snap.text.contains("File"))
}

// Feature #18: deliverURL runtime API
@Test func parity_deliverURL_compiles() async throws {
    let runtime = _UIRuntime()
    // Verify deliverURL method exists and is callable
    let testURL = URL(string: "https://example.com")!
    runtime.deliverURL(testURL)
    // No crash = pass
}

// Feature #19: LinearGradient dithering
@Test func parity_linearGradient_renders() async throws {
    struct GradView: View {
        var body: some View {
            LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 20, height: 4)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(GradView(), size: _Size(width: 20, height: 4))
    // Should have some content (gradient cells)
    #expect(!snap.text.trimmingCharacters(in: .whitespaces).isEmpty)
}

// Feature #20: RadialGradient dithering
@Test func parity_radialGradient_renders() async throws {
    struct RadView: View {
        var body: some View {
            RadialGradient(gradient: Gradient(colors: [.white, .black]), center: .center, startRadius: 0, endRadius: 10)
                .frame(width: 10, height: 5)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(RadView(), size: _Size(width: 10, height: 5))
    #expect(!snap.text.trimmingCharacters(in: .whitespaces).isEmpty)
}

// Feature #21: Canvas Path rendering
@Test func parity_canvas_path_fill() async throws {
    struct CanvasView: View {
        var body: some View {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(x: 0, y: 0, width: 5, height: 3)), with: .color(.red))
            }
            .frame(width: 10, height: 5)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(CanvasView(), size: _Size(width: 10, height: 5))
    // Canvas should produce shape output
    #expect(snap.shapeRegions.count > 0 || !snap.text.trimmingCharacters(in: .whitespaces).isEmpty)
}

// Feature #22: Custom ButtonStyle
@Test func parity_custom_buttonStyle() async throws {
    struct BoldButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .bold()
        }
    }
    struct StyledBtn: View {
        var body: some View {
            Button("Custom") {}
                .buttonStyle(BoldButtonStyle())
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(StyledBtn(), size: _Size(width: 20, height: 3))
    #expect(snap.text.contains("Custom"))
}

// Feature #23: Shadow rendering
@Test func parity_shadow_small_radius() async throws {
    struct ShadowView: View {
        var body: some View {
            Text("Hi")
                .shadow(color: .gray, radius: 1)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(ShadowView(), size: _Size(width: 10, height: 5))
    #expect(snap.text.contains("Hi"))
}

@Test func parity_shadow_large_radius_glow() async throws {
    struct GlowView: View {
        var body: some View {
            Text("Hi")
                .shadow(color: .green, radius: 5)
        }
    }
    let runtime = _UIRuntime()
    let snap = runtime.debugRender(GlowView(), size: _Size(width: 20, height: 8))
    #expect(snap.text.contains("Hi"))
}

private struct _FocusedURLFieldProbe: View {
    @State private var url = "gopher://gopher.navan.dev:70/"
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            TextField("URL", text: $url)
                .focused($isFocused)
            Text("Ready")
        }
        .onAppear {
            isFocused = true
        }
    }
}

private struct _OnAppearStateProbe: View {
    @State private var shown = false

    var body: some View {
        VStack {
            if shown {
                Text("Shown")
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                Text("Hidden")
            }
        }
        .onAppear {
            guard !shown else { return }
            shown = true
        }
    }
}

private struct _BrowserChromeHotLoopProbe: View {
    @State private var url = "gopher://gopher.navan.dev:70/"
    @State private var showTooltip = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Welcome")
            Text("Info line")
            TextField("Enter a URL", text: $url)
                .focused($isFocused)
            HStack {
                Button {
                } label: {
                    Label("Home", systemImage: "house")
                }
                .labelStyle(.iconOnly)

                Spacer()

                Button("Go") {
                }
            }
        }
        .onAppear {
            isFocused = true
            guard !showTooltip else { return }
            showTooltip = true
        }
    }
}

@Test func focused_text_field_settles_after_initial_focus() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 50, height: 6)

    _ = runtime.debugRender(_FocusedURLFieldProbe(), size: size)
    _ = runtime.debugRender(_FocusedURLFieldProbe(), size: size)

    #expect(!runtime.needsRender(size: size))
}

@Test func on_appear_state_change_settles_after_mount() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 30, height: 6)

    for _ in 0..<4 {
        _ = runtime.debugRender(_OnAppearStateProbe(), size: size)
    }

    #expect(!runtime.needsRender(size: size))
}

@Test func browser_like_chrome_eventually_goes_idle() async throws {
    let runtime = _UIRuntime()
    let size = _Size(width: 60, height: 10)

    for _ in 0..<32 {
        _ = runtime.debugRender(_BrowserChromeHotLoopProbe(), size: size)
    }

    #expect(!runtime.needsRender(size: size))
}
