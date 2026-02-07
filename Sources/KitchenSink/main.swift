import OmniUI
import OmniUICore
import OmniUINotcursesRenderer
import OmniUITerminalRenderer
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct KitchenSinkRoot: View {
    var body: some View {
        NavigationStack {
            KitchenSinkHome()
        }
    }
}

final class DemoModel: ObservableObject {
    var name: String = ""
    var count: Int = 0
}

final class AppEnvironment: ObservableObject {
    var banner: String = "Hello from EnvironmentObject"
}

struct KitchenSinkHome: View {
    @State private var count: Int = 0
    @State private var crtMode: Bool = false
    @State private var name: String = ""
    @State private var flavor: Flavor = .vanilla
    @State private var pickedRow: Int = 0
    @StateObject private var model = DemoModel()
    @StateObject private var appEnv = AppEnvironment()

    enum Flavor: String, Hashable {
        case vanilla = "Vanilla"
        case chocolate = "Chocolate"
        case strawberry = "Strawberry"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 1) {
                Label("OmniUI KitchenSink", systemImage: "sparkles")

                Section(header: Text("State / Binding")) {
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
                    Text("Hello, \(name.isEmpty ? "anonymous" : name)")
                }

                Section(header: Text("Picker")) {
                    Picker(
                        "Flavor",
                        selection: $flavor,
                        options: [
                            (.vanilla, "Vanilla"),
                            (.chocolate, "Chocolate"),
                            (.strawberry, "Strawberry"),
                        ]
                    )
                }

                Section(header: Text("Shapes")) {
                    HStack(spacing: 1) {
                        Rectangle()
                        RoundedRectangle(cornerRadius: 3)
                        Circle()
                        Ellipse()
                        Capsule()
                    }
                    Text("Clipped")
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }

                Section(header: Text("ZStack")) {
                    ZStack {
                        Text("Background text")
                        Text("Overlay (shifted)")
                            .padding(1)
                    }
                }

                Section(header: Text("List / ForEach (picked: \(pickedRow))")) {
                    List(0..<2, id: \.self) { i in
                        HStack(spacing: 1) {
                            Text("Row \(i)")
                            Spacer()
                            Button("Pick") { pickedRow = i }
                        }
                    }
                }

                Section(header: Text("Table")) {
                    Table(0..<3, id: \.self) { i in
                        HStack(spacing: 1) {
                            Text("Cell \(i)")
                            Spacer()
                            Text("Value \(i * 10)")
                        }
                    }
                }

                Section(header: Text("StateObject / ObservedObject")) {
                    Text("Model.count: \(model.count)")
                    HStack(spacing: 1) {
                        Button("Model +1") { model.count += 1 }
                        Button("Model -1") { model.count -= 1 }
                    }
                    TextField("Model name", text: $model.name)
                    ObservedModelView(model: model)
                }

                Section(header: Text("EnvironmentObject")) {
                    EnvironmentBannerView()
                        .environmentObject(appEnv)
                }

                Section(header: Text("Navigation")) {
                    NavigationLink("Open details") { KitchenSinkDetail() }
                }

                Section(header: Text("ScrollView (wheel over it)")) {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0..<20, id: \.self) { i in
                                Text("Item \(i)")
                            }
                        }
                    }
                }

                Text("Tip: `--notcurses` for the notcurses renderer.")
            }
            .padding(1)
        }
    }
}

struct ObservedModelView: View {
    @ObservedObject var model: DemoModel

    var body: some View {
        VStack(spacing: 1) {
            Text("Observed: \(model.count)")
            Button("Observed +1") { model.count += 1 }
        }
    }
}

struct EnvironmentBannerView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(spacing: 1) {
            Text(env.banner)
            TextField("Banner", text: $env.banner)
        }
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
                fputs("Notcurses renderer failed: \(error)\nFalling back to debug renderer.\n", stderr)
            }
        }

        if CommandLine.arguments.contains("--ansi") {
            do {
                try await TerminalApp { KitchenSinkRoot() }.run()
                return
            } catch {
                fputs("ANSI renderer failed: \(error)\nFalling back to debug renderer.\n", stderr)
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
