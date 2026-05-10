@_exported import Foundation
@_exported import OmniUICore
import OmniUINotcursesRenderer

private struct _OmniSwiftUIAppRootView: View, @unchecked Sendable {
    let root: AnyView
    let commands: AnyView?
    let preferredSize: CGSize?

    var body: some View {
        let sized: AnyView = {
            guard let preferredSize else { return root }
            return AnyView(root.frame(width: preferredSize.width, height: preferredSize.height))
        }()

        if let commands {
            return AnyView(
                VStack(spacing: 0) {
                    sized
                    Divider()
                    commands
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 1)
                }
            )
        }
        return sized
    }
}

public extension App {
    @MainActor
    static func main() async throws {
        let app = Self.init()
        try await NotcursesApp(scene: app.body).run()
    }
}

@freestanding(declaration, names: named(__OmniPreview))
public macro Preview(_ name: String? = nil, @ViewBuilder _ body: () -> AnyView) = #externalMacro(module: "SwiftUIMacros", type: "PreviewMacro")

@attached(member, names: arbitrary)
@attached(memberAttribute)
@attached(extension, conformances: OmniUICore.ObservableObject, names: arbitrary)
public macro Observable() = #externalMacro(module: "SwiftUIMacros", type: "ObservableMacro")

@attached(accessor)
public macro _ObservationTracked() = #externalMacro(module: "SwiftUIMacros", type: "ObservationTrackedMacro")
