import OmniUIAdwaita

struct OmniUIAdwaitaSmokeContent: View {
    @State private var count = 0
    @State private var name = "Facade"
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("OmniUIAdwaita facade smoke")
            Text("Count: \(count)")
            Text("Focus: \(focused ? "focused" : "idle")")
            Button("Increment") { count += 1 }
                .keyboardShortcut(.defaultAction)
            TextField("Name", text: $name)
                .focused($focused)
        }
        .padding(2)
    }
}

@main
struct OmniUIAdwaitaSmokeApp: App {
    var body: some Scene {
        WindowGroup {
            OmniUIAdwaitaSmokeContent()
        }
        .defaultSize(width: 640, height: 420)
    }
}
