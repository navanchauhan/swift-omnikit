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

    @Query(sort: \HarnessModel.id, order: .reverse) private var models: [HarnessModel]

    var body: some View {
        VStack {
            Toggle("Flag", isOn: $harnessFlag)
                .toggleStyle(.switch)

            TextField("Search", text: $text)
                .textFieldStyle(.roundedBorder)

            Button("OK") {}
                .buttonStyle(.borderedProminent)

            Label("Icon", systemImage: "star")
                .labelStyle(.iconOnly)
        }
        .modifier(HarnessModifier())
        .listStyle(.plain)
        .pickerStyle(.segmented)
        .tag(ns) // Ensure `Namespace.ID` is hashable
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
