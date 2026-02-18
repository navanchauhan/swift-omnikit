import Foundation
import OmniUI
import OmniUICore
import OmniUINotcursesRenderer
#if os(Linux)
import Glibc
#else
import Darwin
#endif

private func _writeToStderr(_ message: String) {
    // Avoid `stderr` (a C global `var`) under Swift 6 strict concurrency.
    let bytes = Array(message.utf8)
    bytes.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        #if os(Linux)
        _ = Glibc.write(STDERR_FILENO, base, raw.count)
        #else
        _ = Darwin.write(STDERR_FILENO, base, raw.count)
        #endif
    }
}

struct KitchenSinkRoot: View {
    var body: some View {
        NavigationStack {
            KitchenSinkHome()
        }
    }
}

final class DemoModel: OmniUICore.ObservableObject {
    var name: String = ""
    var count: Int = 0
}

final class AppEnvironment: OmniUICore.ObservableObject {
    var banner: String = "Hello from EnvironmentObject"
}

struct KitchenSinkHome: View {
    @State private var count: Int = 0
    @State private var crtMode: Bool = false
    @State private var name: String = ""
    @State private var flavor: Flavor = .vanilla
    @State private var pickedRow: Int = 0
    @State private var selectedTaggedRow: Int? = 2
    @State private var secureToken: String = ""
    @State private var coordinatorURL: String = ""
    @State private var activeTab: DemoTab = .overview
    @State private var splitSelection: SplitPane = .overview
    @State private var showTransientProbe: Bool = false
    @State private var lastDisappearEvent: String = "none"
    @State private var pulseScale: Bool = false
    @State private var demoTick: Int = 0
    @StateObject private var model = DemoModel()
    @StateObject private var appEnv = AppEnvironment()

    enum Flavor: String, Hashable {
        case vanilla = "Vanilla"
        case chocolate = "Chocolate"
        case strawberry = "Strawberry"
    }

    enum DemoTab: Hashable {
        case overview
        case controls
        case data
    }

    enum SplitPane: Hashable {
        case overview
        case settings
        case logs
    }

    private var demoAnimationsEnabled: Bool {
        ProcessInfo.processInfo.environment["OMNIUI_DEMO_ANIM"] != "0"
    }

    private var pulseColor: Color {
        let palette: [Color] = [.cyan, .mint, .green, .yellow, .orange, .pink]
        return palette[demoTick % palette.count]
    }

    private var spinner: String {
        let frames = ["|", "/", "-", "\\"]
        return frames[demoTick % frames.count]
    }

    private var bannerText: String {
        let phases = ["NATIVE WIDGETS", "SMOOTH SCROLL", "COLOR + MOTION"]
        return phases[(demoTick / 8) % phases.count]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 1) {
                Label("OmniUI KitchenSink", systemImage: "sparkles")
                    .bold()
                    .foregroundStyle(pulseColor)

                HStack(spacing: 1) {
                    Text("[\(spinner)] \(bannerText)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("tick \(demoTick)")
                        .foregroundStyle(.tertiary)
                }
                .background(Color.blue.opacity(0.12))

                Section(header: Text("State / Binding").foregroundStyle(.cyan).bold()) {
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
                            .foregroundStyle(crtMode ? .green : .secondary)
                    }

                    TextField("Type your name", text: $name)
                    Text("Hello, \(name.isEmpty ? "anonymous" : name)")
                        .foregroundStyle(name.isEmpty ? .secondary : .mint)
                }

                Section(header: Text("Picker").foregroundStyle(.cyan).bold()) {
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

                Section(header: Text("Shapes").foregroundStyle(.cyan).bold()) {
                    HStack(spacing: 1) {
                        Rectangle()
                            .foregroundStyle(.teal)
                        RoundedRectangle(cornerRadius: 3)
                            .foregroundStyle(.cyan)
                        Circle()
                            .foregroundStyle(.mint)
                        Ellipse()
                            .foregroundStyle(.yellow)
                        Capsule()
                            .foregroundStyle(.orange)
                    }
                    Text("Clipped")
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }

                Section(header: Text("ZStack").foregroundStyle(.cyan).bold()) {
                    ZStack {
                        Text("Background text")
                            .foregroundStyle(.tertiary)
                        Text("Overlay (shifted)")
                            .foregroundStyle(.white)
                            .background(Color.indigo.opacity(0.35))
                            .padding(1)
                    }
                }

                Section(header: Text("List / ForEach (picked: \(pickedRow))").foregroundStyle(.cyan).bold()) {
                    List(0..<2, id: \.self) { i in
                        HStack(spacing: 1) {
                            Text("Row \(i)")
                                .foregroundStyle(i == pickedRow ? .green : .primary)
                            Spacer()
                            Button("Pick") { pickedRow = i }
                        }
                    }
                }

                Section(header: Text("Table").foregroundStyle(.cyan).bold()) {
                    Table(0..<3, id: \.self) { i in
                        HStack(spacing: 1) {
                            Text("Cell \(i)")
                                .foregroundStyle(.blue)
                            Spacer()
                            Text("Value \(i * 10)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(header: Text("StateObject / ObservedObject").foregroundStyle(.cyan).bold()) {
                    Text("Model.count: \(model.count)")
                    HStack(spacing: 1) {
                        Button("Model +1") { model.count += 1 }
                        Button("Model -1") { model.count -= 1 }
                    }
                    TextField("Model name", text: $model.name)
                    ObservedModelView(model: model)
                }

                Section(header: Text("EnvironmentObject").foregroundStyle(.cyan).bold()) {
                    EnvironmentBannerView()
                        .environmentObject(appEnv)
                }

                Section(header: Text("Navigation").foregroundStyle(.cyan).bold()) {
                    NavigationLink("Open details") { KitchenSinkDetail() }
                }

                Section(header: Text("ScrollView (wheel over it)").foregroundStyle(.cyan).bold()) {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0..<20, id: \.self) { i in
                                Text("Item \(i)")
                                    .foregroundStyle(i % 2 == 0 ? .cyan : .secondary)
                            }
                        }
                    }
                }

                CompatibilityShowcase(
                    demoTick: demoTick,
                    pulseColor: pulseColor,
                    pulseScale: $pulseScale,
                    coordinatorURL: $coordinatorURL,
                    secureToken: $secureToken,
                    selectedTaggedRow: $selectedTaggedRow,
                    activeTab: $activeTab,
                    splitSelection: $splitSelection,
                    crtMode: $crtMode,
                    showTransientProbe: $showTransientProbe,
                    lastDisappearEvent: $lastDisappearEvent
                )

                Text("Renderer: native notcurses widgets.")
                    .foregroundStyle(.mint)
            }
            .padding(1)
            .background(Color.indigo.opacity(0.08))
        }
        .navigationTitle("KitchenSink")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Text("OmniUI")
            }
            ToolbarItem(placement: .principal) {
                Text("KitchenSink")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Text("tick \(demoTick)")
            }
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 1) {
                    Text("Bottom")
                    Button("Reset tick") { demoTick = 0 }
                }
            }
        }
        .task {
            guard demoAnimationsEnabled else { return }
            while true {
                try? await Task.sleep(nanoseconds: 120_000_000)
                demoTick = (demoTick + 1) % 1_000_000
            }
        }
    }
}

struct CompatibilityShowcase: View {
    let demoTick: Int
    let pulseColor: Color
    @Binding var pulseScale: Bool
    @Binding var coordinatorURL: String
    @Binding var secureToken: String
    @Binding var selectedTaggedRow: Int?
    @Binding var activeTab: KitchenSinkHome.DemoTab
    @Binding var splitSelection: KitchenSinkHome.SplitPane
    @Binding var crtMode: Bool
    @Binding var showTransientProbe: Bool
    @Binding var lastDisappearEvent: String

    var body: some View {
        Group {
            Section(header: Text("Progress / Tint / Animation").foregroundStyle(.cyan).bold()) {
                HStack(spacing: 1) {
                    ProgressView()
                        .tint(pulseColor)
                    Spacer()
                    ProgressView(value: Double(demoTick % 100), total: 100)
                }
                Text("Scaled pulse label")
                    .foregroundStyle(.pink)
                    .scaleEffect(pulseScale ? 1.3 : 0.9)
                Button("Toggle scale") { pulseScale.toggle() }
            }

            Section(header: Text("Text Inputs (prompt + secure)").foregroundStyle(.cyan).bold()) {
                TextField(
                    "Coordinator URL",
                    text: $coordinatorURL,
                    prompt: Text("https://localhost:8080")
                )
                .autocorrectionDisabled()
                SecureField(
                    "Bearer token",
                    text: $secureToken,
                    prompt: Text("Paste your token")
                )
                .textFieldStyle(.roundedBorder)
                Text("Token length: \(secureToken.count)")
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("List(selection:)").foregroundStyle(.cyan).bold()) {
                List(selection: $selectedTaggedRow) {
                    ForEach(0..<5, id: \.self) { i in
                        Label("Tagged row \(i)", systemImage: "circle")
                            .tag(i)
                    }
                }
                Text("Selected tagged row: \(selectedTaggedRow.map(String.init) ?? "nil")")
            }

            Section(header: Text("GridItem / LazyVGrid").foregroundStyle(.cyan).bold()) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 12), spacing: 1)], spacing: 1) {
                    ForEach(0..<8, id: \.self) { i in
                        Text("Card \(i)")
                            .padding(1)
                            .frame(maxWidth: .infinity)
                            .background(i % 2 == 0 ? Color.teal.opacity(0.2) : Color.blue.opacity(0.2))
                    }
                }
            }

            Section(header: Text("TabView / tabItem").foregroundStyle(.cyan).bold()) {
                TabView(selection: $activeTab) {
                    Text("Overview panel")
                        .tabItem { Label("Overview", systemImage: "list.bullet") }
                        .tag(KitchenSinkHome.DemoTab.overview)

                    Text("Controls panel")
                        .tabItem { Label("Controls", systemImage: "slider.horizontal.3") }
                        .tag(KitchenSinkHome.DemoTab.controls)

                    Text("Data panel")
                        .tabItem { Label("Data", systemImage: "tablecells") }
                        .tag(KitchenSinkHome.DemoTab.data)
                }
                .tint(.orange)
                Text("Active tab: \(String(describing: activeTab))")
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("NavigationSplitView").foregroundStyle(.cyan).bold()) {
                NavigationSplitView {
                    List(selection: $splitSelection) {
                        Label("Overview", systemImage: "rectangle.3.group")
                            .tag(KitchenSinkHome.SplitPane.overview)
                        Label("Settings", systemImage: "gear")
                            .tag(KitchenSinkHome.SplitPane.settings)
                        Label("Logs", systemImage: "terminal")
                            .tag(KitchenSinkHome.SplitPane.logs)
                    }
                    .navigationSplitViewColumnWidth(min: 18, ideal: 24)
                } detail: {
                    switch splitSelection {
                    case .overview:
                        Text("Split detail: Overview")
                    case .settings:
                        Text("Split detail: Settings")
                    case .logs:
                        Text("Split detail: Logs")
                    }
                }
            }

            Section(header: Text("Form(.grouped)").foregroundStyle(.cyan).bold()) {
                Form {
                    Section {
                        TextField("URL", text: $coordinatorURL, prompt: Text("https://localhost:8080"))
                            .autocorrectionDisabled()
                        Toggle("Insecure TLS", isOn: $crtMode)
                    } header: {
                        Text("Connection")
                    }
                    Section {
                        SecureField("Token", text: $secureToken, prompt: Text("Bearer"))
                    } header: {
                        Text("Authentication")
                    }
                }
                .formStyle(.grouped)
            }

            Section(header: Text("onDisappear Probe").foregroundStyle(.cyan).bold()) {
                Toggle("Show transient child", isOn: $showTransientProbe)
                if showTransientProbe {
                    TransientProbe(lastDisappearEvent: $lastDisappearEvent)
                }
                Text("Last disappear event: \(lastDisappearEvent)")
                    .foregroundStyle(.secondary)
            }
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

struct TransientProbe: View {
    @Binding var lastDisappearEvent: String

    var body: some View {
        Text("Transient child is visible")
            .foregroundStyle(.yellow)
            .onDisappear {
                let unix = Int(Date().timeIntervalSince1970)
                lastDisappearEvent = "disappeared @ \(unix)"
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
        do {
            try await NotcursesApp { KitchenSinkRoot() }.run()
            return
        } catch {
            // Don't crash the whole demo if the terminal doesn't support notcurses/terminfo.
            _writeToStderr("Notcurses renderer failed: \(error)\nFalling back to debug renderer.\n")
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
