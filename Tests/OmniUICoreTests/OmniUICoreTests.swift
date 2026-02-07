import Testing
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
