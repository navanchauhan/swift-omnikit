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

struct TextFieldView: View {
    @State private var text: String = ""
    var body: some View {
        VStack(spacing: 1) {
            TextField("placeholder", text: $text)
            Text("Value: \(text)")
        }
    }
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

@Test func keyboardShortcut_action_runs_with_captured_environment() async throws {
    final class Box {
        var opened: URL? = nil
    }

    struct V: View {
        let box: Box
        @Environment(\.openURL) private var openURL
        var body: some View {
            Button("Open") {
                _ = openURL(URL(string: "https://example.com")!)
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
    let needle = Array("[ \(title) ]")
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
                    return (x: x0 + 2, y: y)
                }
                seen += 1
                break
            }
        }
    }
    return nil
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
