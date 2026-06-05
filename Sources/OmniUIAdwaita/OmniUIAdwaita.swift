@_exported import Foundation
@_exported import OmniUICore
@_exported import OmniUIAdwaitaRenderer
@_exported import OmniFoundationExtras
#if canImport(Combine)
@_exported import Combine
#endif
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif
import Foundation

#if canImport(AppKit) && !os(Linux)
@_exported import AppKit
#endif

public extension App {
    @MainActor
    static func main() async throws {
        _omniAdwaitaEntryTrace("main begin app=\(String(reflecting: Self.self))")
        let name = Self.omniUIAdwaitaDisplayName
        try await Self.adwaitaMain(appID: "dev.omnikit.\(name)", title: name)
        _omniAdwaitaEntryTrace("main end app=\(String(reflecting: Self.self))")
    }

    private static var omniUIAdwaitaDisplayName: String {
        let name = String(describing: Self.self)
        if name.hasSuffix("App"), name.count > 3 {
            return String(name.dropLast(3))
        }
        return name
    }
}

private func _omniAdwaitaEntryTrace(_ message: String) {
    guard let raw = getenv("OMNIKIT_ADWAITA_ENTRY_TRACE"),
          let value = String(validatingCString: raw),
          !value.isEmpty,
          value != "0",
          value.lowercased() != "false" else {
        return
    }
    FileHandle.standardError.write(Data("[OmniKit Adwaita entry] \(message)\n".utf8))
}

public struct AnimationTimelineSchedule: Hashable, Sendable { public init() {} }

@MainActor
public extension View {
    func phaseAnimator<Phase: Hashable, Content: View>(
        _ phases: [Phase],
        @ViewBuilder content: @escaping @MainActor @Sendable (Self, Phase) -> Content,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View {
        let firstAnimation = phases.first.flatMap { animation($0) } ?? .default
        return _PhaseAnimatorPrimitive(
            phases: phases,
            content: { anyPhase in
                guard let phase = anyPhase as? Phase else { return AnyView(self) }
                return AnyView(content(self, phase))
            },
            intervalSeconds: max(0.05, firstAnimation.duration)
        )
    }

    func phaseAnimator<Phase: Hashable, Trigger: Equatable, Content: View>(
        _ phases: [Phase],
        trigger: Trigger,
        @ViewBuilder content: @escaping @MainActor @Sendable (Self, Phase) -> Content,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View {
        _AnimationModifier(
            content: AnyView(phaseAnimator(phases, content: content, animation: animation)),
            animation: nil,
            value: trigger
        )
    }
}

@freestanding(declaration, names: named(__OmniPreview))
public macro Preview(_ name: String? = nil, @ViewBuilder _ body: () -> AnyView) = #externalMacro(module: "SwiftUIMacros", type: "PreviewMacro")
