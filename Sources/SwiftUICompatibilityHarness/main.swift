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

    @Query(sort: \HarnessModel.id, order: .reverse) private var models: [HarnessModel]

    var body: some View {
        VStack(spacing: 1) {
            Toggle("Flag", isOn: $harnessFlag)
                .toggleStyle(.switch)

            TextField("Search", text: $text)
                .textFieldStyle(.roundedBorder)

            Text("Tap Target")
                .onTapGesture { showAlert = true }

            Divider()

            GeometryReader { _ in
                Text("GeometryReader")
            }

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

            Menu {
                Button("One") {}
                Button("Two") {}
            } label: {
                Text("Menu")
            }
            .controlSize(.large)

            Button("OK") {}
                .buttonStyle(.borderedProminent)

            Label("Icon", systemImage: "star")
                .labelStyle(.iconOnly)
        }
        .modifier(HarnessModifier())
        .listStyle(.plain)
        .pickerStyle(.segmented)
        .tag(ns) // Ensure `Namespace.ID` is hashable
        .safeAreaInset(edge: .top) { Text("Inset") }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {}
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
