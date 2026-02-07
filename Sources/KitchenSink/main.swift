import OmniUI
import OmniUICore
import OmniUINotcursesRenderer
import Foundation

struct KitchenSinkRoot: View {
    @State private var count: Int = 0
    @State private var crtMode: Bool = false
    @State private var name: String = ""
    @State private var flavor: Flavor = .vanilla

    enum Flavor: String, Hashable {
        case vanilla = "Vanilla"
        case chocolate = "Chocolate"
        case strawberry = "Strawberry"
    }

    var body: some View {
        VStack(spacing: 1) {
            Label("OmniUI KitchenSink", systemImage: "sparkles")
            Text("Counter: \(count)")
            HStack(spacing: 1) {
                Button("Increment") { count += 1 }
                Button("Decrement") { count -= 1 }
            }
            Toggle("CRT Mode", isOn: $crtMode)
            Text("CRT: \(crtMode ? "ON" : "OFF")")
            TextField("Type your name", text: $name)
            Text("Hello, \(name.isEmpty ? "anonymous" : name)")
            Picker(
                "Flavor",
                selection: $flavor,
                options: [
                    (.vanilla, "Vanilla"),
                    (.chocolate, "Chocolate"),
                    (.strawberry, "Strawberry"),
                ]
            )
            Text("Tip: use `--notcurses` for the notcurses renderer.")
        }
        .padding(1)
    }
}

@main
enum KitchenSinkMain {
    static func main() async throws {
        if CommandLine.arguments.contains("--notcurses") {
            do {
                try await NotcursesApp { KitchenSinkRoot() }.run()
                return
            } catch {
                // Don't crash the whole demo if the terminal doesn't support notcurses/terminfo.
                FileHandle.standardError.write(Data("Notcurses renderer failed: \(error)\nFalling back to debug renderer.\n".utf8))
            }
        }

        // Debug renderer interactive loop (works without notcurses).
        let runtime = _UIRuntime()
        while true {
            let snap = runtime.debugRender(KitchenSinkRoot(), size: _Size(width: 80, height: 24))
            print("\u{001B}[2J\u{001B}[H", terminator: "") // clear screen + home
            print(snap.text)
            print("\nClick simulation: type `x y` and press enter, or `q` to quit.")

            guard let line = readLine() else { break }
            if line == "q" { break }
            let parts = line.split(separator: " ")
            if parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) {
                snap.click(x: x, y: y)
            }
        }
    }
}
