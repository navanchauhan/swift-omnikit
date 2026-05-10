import SwiftUI
import SwiftData

@Model
final class AliasSmokeRecord {
    var title: String
    init(title: String) { self.title = title }
}

struct OmniUIAdwaitaSwiftUISmokeContent: View {
    @State private var count = 0
    @State private var name = "SwiftUI alias"
    @FocusState private var focused: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [AliasSmokeRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SwiftUI import routed to OmniUIAdwaita")
            Text("Count: \(count)")
            Text("Focus: \(focused ? "focused" : "idle")")
            Text("SwiftData records: \(records.count)")
            Button("Increment") { count += 1 }
                .keyboardShortcut(.defaultAction)
            Button("Add record") {
                modelContext.insert(AliasSmokeRecord(title: "Record \(records.count + 1)"))
            }
            TextField("Name", text: $name)
                .focused($focused)
        }
        .padding(2)
    }
}

@main
struct OmniUIAdwaitaSwiftUISmokeApp: App {
    let container: ModelContainer

    init() {
        self.container = (try? ModelContainer(for: [AliasSmokeRecord.self], inMemory: true)) ?? {
            preconditionFailure("Unable to create OmniUIAdwaitaSwiftUISmoke ModelContainer")
        }()
    }

    var body: some Scene {
        WindowGroup {
            OmniUIAdwaitaSwiftUISmokeContent()
        }
        .defaultSize(width: 640, height: 420)
        .modelContainer(container)
    }
}
