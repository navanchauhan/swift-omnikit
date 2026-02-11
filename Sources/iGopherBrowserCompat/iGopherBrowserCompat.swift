import Foundation
import SwiftData
import SwiftUI

public enum iGopherBrowserTUISupport {
    public static func makeRootView(inMemory: Bool = true) -> AnyView {
        let schema = Schema([Bookmark.self, HistoryItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return AnyView(ContentView().modelContainer(container))
    }
}

#if os(Linux)

// MARK: - Linux shims for iGopherBrowser source compatibility

/// `BrowserView.swift` uses `UIApplication` in a `#if os(OSX) ... #else ...` block.
/// On Linux we provide a tiny stand-in that uses `xdg-open` best-effort.
final class UIApplication: @unchecked Sendable {
    static let shared = UIApplication()

    func open(_ url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        p.arguments = [url.absoluteString]
        try? p.run()
    }
}

/// iGopherBrowser uses `macOSToolbarView` as the non-iOS toolbar, but the upstream
/// implementation only exists for macOS/visionOS. Provide a Linux implementation
/// so the app compiles and remains usable in OmniKit's TUI.
struct macOSToolbarView: View {
    @Binding var url: String
    var isURLFocused: FocusState<Bool>.Binding
    let homeURL: URL
    let shareThroughProxy: Bool
    let backwardStack: [GopherNode]
    let forwardStack: [GopherNode]
    let currentHost: String
    @Binding var showAddBookmark: Bool
    @Binding var showBookmarks: Bool
    @Binding var showPreferences: Bool
    let onGo: () -> Void
    let onHome: () -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    @Binding var showHomeTooltip: Bool
    let homeTooltipMessage: String
    let onHomeTooltipAutoDismiss: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                Button("Home", action: onHome)
                    .keyboardShortcut("r", modifiers: [.command])

                Button("<", action: onBack)
                    .keyboardShortcut("[", modifiers: [.command])
                    .disabled(backwardStack.count < 2)

                Button(">", action: onForward)
                    .keyboardShortcut("]", modifiers: [.command])
                    .disabled(forwardStack.isEmpty)

                Button("Bookmarks") { showBookmarks = true }

                Button("Add") { showAddBookmark = true }
                    .disabled(currentHost.isEmpty)

                Button("Settings") { showPreferences = true }

                Spacer()
            }

            HStack(spacing: 1) {
                TextField("Enter a URL", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .focused(isURLFocused)
                    .keyboardShortcut("l", modifiers: [.command]) // common "focus location" mapping

                Button("Go", action: onGo)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(1)
        .background(.regularMaterial)
        .onChange(of: showHomeTooltip) { _, isVisible in
            if isVisible {
                // Auto-dismiss any first-run tooltip state the moment the toolbar is interacted with.
                onHomeTooltipAutoDismiss()
            }
        }
        .help(homeTooltipMessage) // keep the copy around for future renderer hints
        .onAppear {
            _ = homeURL
            _ = shareThroughProxy
        }
    }
}

// Minimal settings sheet for Linux builds (the upstream SettingsView relies on Apple APIs
// and uses `@retroactive` conformance which isn't valid when compiling inside this package).
struct SettingsView: View {
    @Binding var homeURL: URL
    @Binding var homeURLString: String

    @AppStorage("crtMode") var crtMode: Bool = false
    @AppStorage("crtScanlines") var crtScanlines: Bool = true
    @AppStorage("crtVignette") var crtVignette: Bool = true
    @AppStorage("crtPhosphorColor") var crtPhosphorColor: String = CRTPhosphorColor.green.rawValue

    @Environment(\.dismiss) private var dismiss
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    init(homeURL: Binding<URL>, homeURLString: Binding<String>) {
        self._homeURL = homeURL
        self._homeURLString = homeURLString
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Home")) {
                    TextField("Home URL", text: $homeURLString)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Save") {
                            if let url = URL(string: homeURLString) {
                                homeURL = url
                                dismiss()
                            } else {
                                alertMessage = "Invalid URL: \(homeURLString)"
                                showAlert = true
                            }
                        }
                        .keyboardShortcut(.defaultAction)

                        Button("Reset") {
                            homeURL = URL(string: "gopher://gopher.navan.dev:70/")!
                            homeURLString = homeURL.absoluteString
                        }
                    }
                }

                Section(header: Text("CRT")) {
                    Toggle("CRT Mode", isOn: $crtMode)
                    Toggle("Scanlines", isOn: $crtScanlines)
                        .disabled(!crtMode)
                    Toggle("Vignette", isOn: $crtVignette)
                        .disabled(!crtMode)

                    Picker("Phosphor", selection: $crtPhosphorColor) {
                        ForEach(CRTPhosphorColor.allCases) { c in
                            Text(c.displayName).tag(c.rawValue)
                        }
                    }
                    .disabled(!crtMode)
                }

                Section {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .navigationTitle("Settings")
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Settings Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
}

#endif

#if !os(Linux)

// Minimal fallback settings sheet for non-Linux builds when the upstream macOS SettingsView
// is not part of this compatibility target.
struct SettingsView: View {
    @AppStorage("homeURL") private var homeURL: URL = URL(string: "gopher://gopher.navan.dev:70/")!
    @State private var homeURLString: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var showAlert: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Home")) {
                    TextField("Home URL", text: $homeURLString)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Save") {
                            if let url = URL(string: homeURLString) {
                                homeURL = url
                                dismiss()
                            } else {
                                showAlert = true
                            }
                        }
                        .keyboardShortcut(.defaultAction)

                        Button("Reset") {
                            homeURL = URL(string: "gopher://gopher.navan.dev:70/")!
                            homeURLString = homeURL.absoluteString
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            homeURLString = homeURL.absoluteString
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Invalid URL"),
                message: Text("Please provide a valid gopher URL."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

#endif
