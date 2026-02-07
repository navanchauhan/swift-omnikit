import OmniUI
import OmniUICore
import OmniUINotcursesRenderer
import Foundation

struct KitchenSinkRoot: View {
    var body: some View {
        NavigationStack {
            KitchenSinkHome()
        }
    }
}

struct KitchenSinkHome: View {
    @State private var count: Int = 0
    @State private var crtMode: Bool = false
    @State private var name: String = ""
    @State private var flavor: Flavor = .vanilla
    @State private var pickedRow: Int = 0

    enum Flavor: String, Hashable {
        case vanilla = "Vanilla"
        case chocolate = "Chocolate"
        case strawberry = "Strawberry"
    }

    var body: some View {
        VStack(spacing: 1) {
            Label("OmniUI KitchenSink", systemImage: "sparkles")

            HStack(spacing: 1) {
                Text("Count: \(count)")
                Spacer()
                Button("+") { count += 1 }
                Button("-") { count -= 1 }
            }

            HStack(spacing: 1) {
                Toggle("CRT", isOn: $crtMode)
                Spacer()
                Text(crtMode ? "ON" : "OFF")
            }

            TextField("Type your name", text: $name)
            Picker(
                "Flavor",
                selection: $flavor,
                options: [
                    (.vanilla, "Vanilla"),
                    (.chocolate, "Chocolate"),
                    (.strawberry, "Strawberry"),
                ]
            )

            Text("ZStack:")
            ZStack {
                Text("Background text")
                Text("Overlay (shifted)")
                    .padding(1)
            }

            Text("List (picked: \(pickedRow))")
            List(0..<2, id: \.self) { i in
                HStack(spacing: 1) {
                    Text("Row \(i)")
                    Spacer()
                    Button("Pick") { pickedRow = i }
                }
            }

            NavigationLink("Open details") { KitchenSinkDetail() }

            Text("ScrollView (wheel over it):")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { i in
                        Text("Item \(i)")
                    }
                }
            }

            Text("Tip: `--notcurses` for the notcurses renderer.")
        }
        .padding(1)
    }
}

struct KitchenSinkDetail: View {
    let level: Int
    @State private var localCount: Int = 0

    init(level: Int = 1) {
        self.level = level
    }

    var body: some View {
        VStack(spacing: 1) {
            Text("Detail screen (level \(level))")
            Text("Local: \(localCount)")
            Button("Local +1") { localCount += 1 }
            NavigationLink("Push next") { KitchenSinkDetail(level: level + 1) }
            Text("Back: click [ Back ] or press Backspace/Delete.")
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
