import Foundation
import OmniUIAdwaita
import SwiftData
import SwiftUI

@Model
final class DemoRecord {
    var title: String
    init(title: String) { self.title = title }
}

@SwiftUI.Observable
final class BindableDemoModel {
    var title: String = "Bindable model"
    var isPinned: Bool = true
}

private enum DemoEnvironmentLabelKey: EnvironmentKey {
    static let defaultValue = "Default environment"
}

extension EnvironmentValues {
    var demoEnvironmentLabel: String {
        get { self[DemoEnvironmentLabelKey.self] }
        set { self[DemoEnvironmentLabelKey.self] = newValue }
    }
}

struct KitchenSinkAdwaitaRoot: View {
    @State private var count = 0
    @State private var enabled = true
    @State private var name = "OmniUI"
    @State private var flavor = "Vanilla"
    @State private var notes = "Native TextEditor\nBacked by GtkTextView"
    @State private var level = 0.4
    @State private var stepValue = 2
    @State private var dueDate = Date(timeIntervalSince1970: 1_704_067_200)
    @State private var secret = "gtk"
    @State private var disabledName = "Locked"
    @State private var bindableModel = BindableDemoModel()
    @State private var path = NavigationPath()
    @State private var showSheet = false
    @State private var showAlert = false
    @State private var selectedSection = "Overview"
    @AppStorage("kitchensink-adwaita-note") private var storedNote = "Stored setting"
    @FocusState private var nameFocused: Bool
    @Namespace private var namespace
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [DemoRecord]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .modelContainer(for: [DemoRecord.self], inMemory: true)
    }

    private var sidebar: some View {
        List {
            Button("Overview") { selectedSection = "Overview" }
            Button("Controls") { selectedSection = "Controls" }
            Button("Data") { selectedSection = "Data" }
            Button("Drawing") { selectedSection = "Drawing" }
        }
        .navigationTitle("KitchenSink")
    }

    private var detail: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    content(proxy: proxy)
                        .environment(\.demoEnvironmentLabel, "BrowserView environment")
                }
                .navigationDestination(for: String.self) { value in
                    VStack {
                        Text(value)
                        Button("Pop note") { storedNote = "Updated at \(count)" }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Toolbar +1") { count += 1 }
                }
            }
            .alert(isPresented: $showAlert) {
                Text("Enabled")
            }
            .sheet(isPresented: Binding(get: { showSheet }, set: { showSheet = $0 })) {
                Text("Sheet content")
            }
        }
    }

    private func content(proxy: ScrollViewProxy) -> some View {
        LazyVStack(alignment: .leading, spacing: 3) {
            if ProcessInfo.processInfo.environment["OMNIUI_ADWAITA_HUGE_SMOKE"] == "1" {
                hugeGopherSmoke
            }
            Group {
                header
                EnvironmentBadge()
                NamespaceBadge(namespace: namespace)
                Text("Sidebar selection: \(selectedSection)")
                    .font(.caption)
                Text("Commands: demo \(UserDefaults.standard.integer(forKey: "kitchensink-adwaita-demo-command-count")), sidebar \(UserDefaults.standard.integer(forKey: "kitchensink-adwaita-sidebar-command-count"))")
                    .font(.caption)
                Text("FocusState name: \(nameFocused ? "focused" : "idle")")
                    .font(.caption)
                HStack {
                    Text("AppStorage: \(storedNote)")
                        .font(.caption)
                    Button("Update AppStorage") { storedNote = "Stored at \(count)" }
                }
                BindingCounter(count: $count)
                HStack {
                    Text("Presentation: \(showSheet ? "sheet" : showAlert ? "alert" : "idle")")
                        .font(.caption)
                    Button("Sheet") { showSheet = true }
                    Button("Alert") { showAlert = true }
                }
            }
            Group {
                smokeControls(proxy: proxy)
                commonControlSmoke
            }
            Group {
                BindableModelPanel(model: bindableModel)
                controls(proxy: proxy)
                dataList
                actions
                geometryProbe
                drawingProbe
                footer
            }
        }
        .padding(2)
    }

    private func controls(proxy: ScrollViewProxy) -> some View {
        Form {
            TextField("Name", text: $name)
                .focused($nameFocused)
            Picker("Flavor", selection: $flavor, options: [
                ("Vanilla", "Vanilla"),
                ("Mint", "Mint"),
                ("Chocolate", "Chocolate"),
            ])
            TextEditor(text: $notes)
                .frame(height: 8)
            Toggle("Enabled", isOn: $enabled)
            Button("Increment") { count += 1 }
            Button("Focus name") { nameFocused = true }
            Button("Scroll drawing") { proxy.scrollTo("drawing") }
        }
    }

    private var textInputSmoke: some View {
        HStack {
            Text("Input smoke: \(name)")
                .font(.caption)
            Button("Type !") { name += "!" }
            Button("Backspace") {
                if !name.isEmpty {
                    name.removeLast()
                }
            }
        }
    }

    private func smokeControls(proxy: ScrollViewProxy) -> some View {
        Group {
            textInputSmoke
            notesSmoke
            pickerSmoke
            swiftDataSmoke
            scrollSmoke(proxy: proxy)
        }
    }

    private var notesSmoke: some View {
        HStack {
            Text("Notes smoke: \(notes.count) chars")
                .font(.caption)
            Button("Append note") {
                notes += "\nAdwaita update \(count)"
            }
            Button("Reset notes") {
                notes = "Native TextEditor\nBacked by GtkTextView"
            }
        }
    }

    private var pickerSmoke: some View {
        HStack {
            Text("Picker smoke: \(flavor)")
                .font(.caption)
            Button("Set Mint") { flavor = "Mint" }
            Button("Set Vanilla") { flavor = "Vanilla" }
        }
    }

    private var swiftDataSmoke: some View {
        HStack {
            Text("SwiftData records: \(records.count)")
                .font(.caption)
            Button("Add record") {
                modelContext.insert(DemoRecord(title: "Record \(records.count + 1)"))
            }
            Button("Delete record") {
                if let first = records.first {
                    modelContext.delete(first)
                }
            }
        }
    }

    private func scrollSmoke(proxy: ScrollViewProxy) -> some View {
        HStack {
            Text("Scroll smoke: overview")
                .font(.caption)
            Button("Scroll drawing") {
                proxy.scrollTo("drawing")
            }
        }
    }

    private var commonControlSmoke: some View {
        Group {
            HStack {
                Text("Common controls: level \(Int((level * 100).rounded()))%, step \(stepValue)")
                    .font(.caption)
                Button("Level +") { level = min(1.0, level + 0.1) }
                Button("Step +") { stepValue = min(10, stepValue + 1) }
            }
            ProgressView(value: level, total: 1.0)
            Slider(value: $level, in: 0...1, step: 0.1) {
                Text("Level")
            }
            Stepper("Stepper: \(stepValue)", value: $stepValue, in: 0...10)
            DatePicker("Due", selection: $dueDate)
            SecureField("Secret", text: $secret)
            disabledControlSmoke
        }
    }

    private var disabledControlSmoke: some View {
        HStack {
            Button("Disabled action") { count += 100 }
                .disabled(true)
            Toggle("Disabled toggle", isOn: $enabled)
                .disabled(true)
            TextField("Disabled name", text: $disabledName)
                .disabled(true)
        }
    }

    private var dataList: some View {
        List {
            Text("Count: \(count)")
            Text("Name: \(name)")
            Text("Flavor: \(flavor)")
            Text("Notes: \(notes)")
            Text("Level: \(Int((level * 100).rounded()))%")
            Text("Step value: \(stepValue)")
            Text("Bindable: \(bindableModel.title)")
            Text("Bindable pinned: \(bindableModel.isPinned ? "yes" : "no")")
            Text("AppStorage: \(storedNote)")
            Text("SwiftData records: \(records.count)")
        }
    }

    private var hugeGopherSmoke: some View {
        Group {
            Text(String(repeating: "Large gopher text payload. ", count: 900))
            List(0..<5_000, id: \.self) { index in
                Button("gopher://example.test/item-\(index)") {
                    selectedSection = "Huge \(index)"
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("Insert model") {
                modelContext.insert(DemoRecord(title: "Record \(records.count + 1)"))
            }
            Button("Push detail") {
                path.append("Detail \(count)")
            }
            Button("Show sheet") {
                showSheet = true
            }
            Button("Show alert") {
                showAlert = true
            }
        }
    }

    private var geometryProbe: some View {
        GeometryReader { geometry in
            Text("Geometry: \(Int(geometry.size.width)) x \(Int(geometry.size.height))")
        }
        .frame(height: 4)
    }

    private var drawingProbe: some View {
        VStack(alignment: .leading) {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .color(.teal))
            }
            .frame(width: 16, height: 6)
            .id("drawing")
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [.blue, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 20, height: 4)
                .glassEffect()
            Text("Liquid Glass maps to Adwaita card styling; CRT modifiers are native no-op approximations.")
                .crtEffect(.scanline)
                .font(.caption)
        }
    }

    private var header: some View {
        VStack(alignment: .leading) {
            Text("OmniUI Adwaita KitchenSink")
                .font(.headline)
            Text("Native GTK/libadwaita semantic renderer")
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        Text("Covers App/Scene/WindowGroup/Settings/commands, state wrappers, navigation, stacks, forms, lists, controls, TextEditor, Picker, modifiers, SwiftData, drawing islands.")
            .font(.caption)
    }
}

struct EnvironmentBadge: View {
    @Environment(\.demoEnvironmentLabel) private var label

    var body: some View {
        Text("Environment: \(label)")
            .font(.caption)
    }
}

struct NamespaceBadge: View {
    let namespace: Namespace.ID

    var body: some View {
        Text("Namespace: \(abs(namespace.hashValue))")
            .font(.caption)
            .accessibilityIdentifier("kitchensink-namespace")
    }
}

struct BindingCounter: View {
    @Binding var count: Int

    var body: some View {
        HStack {
            Text("Binding count: \(count)")
                .font(.caption)
            Button("Binding +1") { count += 1 }
        }
    }
}

struct BindableModelPanel: View {
    @Bindable var model: BindableDemoModel

    var body: some View {
        Group {
            Text("@Bindable")
                .font(.caption)
            TextField("Bindable title", text: $model.title)
            Toggle("Pinned", isOn: $model.isPinned)
        }
    }
}

struct KitchenSinkAdwaitaDemoApp: App {
    let demoContainer: ModelContainer

    init() {
        self.demoContainer = (try? ModelContainer(for: [DemoRecord.self], inMemory: true)) ?? {
            preconditionFailure("Unable to create KitchenSinkAdwaita ModelContainer")
        }()
    }

    init(container: ModelContainer) {
        self.demoContainer = container
    }

    var body: some Scene {
        WindowGroup {
            KitchenSinkAdwaitaRoot()
        }
        .defaultSize(width: 1100, height: 900)
        .modelContainer(demoContainer)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Demo command") {
                    let key = "kitchensink-adwaita-demo-command-count"
                    UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
                    UserDefaults.standard.synchronize()
                }
            }
            SidebarCommands()
        }

        Settings {
            Form {
                Text("Adwaita renderer settings")
                Text("Settings scene is available through OmniUI Scene metadata.")
            }
        }
    }
}

@main
enum KitchenSinkAdwaitaMain {
    static func main() async throws {
        let container = try ModelContainer(for: [DemoRecord.self], inMemory: true)
        try await AdwaitaApp(title: "OmniUI Adwaita KitchenSink", scene: KitchenSinkAdwaitaDemoApp(container: container).body).run()
    }
}
