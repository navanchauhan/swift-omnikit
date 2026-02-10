import SwiftData
import SwiftUI

@Model
final class HarnessModel {
    var id: Int
    init(id: Int) { self.id = id }
}

private struct HarnessModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

private struct HarnessView: View {
    @AppStorage("harnessFlag") private var harnessFlag: Bool = false
    @Namespace private var ns
    @State private var text: String = ""
    @State private var showAlert: Bool = false
    @State private var picked: Color = .blue

    @Query(sort: \HarnessModel.id, order: .reverse) private var models: [HarnessModel]

    var body: some View {
        VStack(spacing: 1) {
            Group {
                Toggle("Flag", isOn: $harnessFlag)
                    .toggleStyle(.switch)

                TextField("Search", text: $text)
                    .textFieldStyle(.roundedBorder)

                Text("Tap Target")
                    .onTapGesture { showAlert = true }

                Divider()

                Text(Image(systemName: "sparkles"))

                GeometryReader { _ in
                    Text("GeometryReader")
                }

                Canvas { context, size in
                    for y in stride(from: 0.0, to: size.height, by: 4.0) {
                        let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                        context.fill(Path(rect), with: .color(Color.black.opacity(0.2)))
                    }
                }

                Text("Platform Colors")
                    .background(Color(.systemGray6))
                    .background(Color(uiColor: .systemBackground))

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .glassEffect(in: .rect(cornerRadius: 2))

                RoundedRectangle(cornerRadius: 2)
                    .stroke(
                        LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )

                RadialGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.2)]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 10
                )
            }

            Group {
                GroupBox {
                    Form {
                        Section {
                            LabeledContent("Hello", value: "World")
                        } header: {
                            Text("Section Header")
                        }
                    }
                } label: {
                    Label("GroupBox", systemImage: "star")
                }

                if models.isEmpty {
                    ContentUnavailableView("No Data", systemImage: "xmark", description: Text("Empty"))
                } else {
                    EmptyView()
                }

                ColorPicker("Color", selection: $picked)
                    .labelsHidden()

                Menu {
                    Button("One") {}
                    Button("Two") {}
                } label: {
                    Text("Menu")
                }
                .controlSize(.large)

                Button("OK") {}
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)

                Label("Icon", systemImage: "star")
                    .labelStyle(.iconOnly)

                Button("Cancel") { showAlert = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .modifier(HarnessModifier())
        .listStyle(.plain)
        .pickerStyle(.segmented)
        .tag(ns) // Ensure `Namespace.ID` is hashable
        .safeAreaInset(edge: .top) { Text("Inset") }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    withAnimation(.spring()) {
                        showAlert = false
                    }
                }
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Alert"), message: Text("Hello"), dismissButton: .default(Text("OK")))
        }
    }
}

@main
struct SwiftUICompatibilityHarnessApp: App {
    var body: some Scene {
        WindowGroup {
            HarnessView()
        }
        .commands {
            #if os(macOS)
                SidebarCommands()
            #endif
        }
    }
}
