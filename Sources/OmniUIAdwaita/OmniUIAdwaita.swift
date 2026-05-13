@_exported import Foundation
@_exported import OmniUICore
@_exported import OmniUIAdwaitaRenderer
import Foundation

#if canImport(AppKit)
@_exported import AppKit
#endif

public extension App {
    @MainActor
    static func main() async throws {
        let name = Self.omniUIAdwaitaDisplayName
        try await Self.adwaitaMain(appID: "dev.omnikit.\(name)", title: name)
    }

    private static var omniUIAdwaitaDisplayName: String {
        let name = String(describing: Self.self)
        if name.hasSuffix("App"), name.count > 3 {
            return String(name.dropLast(3))
        }
        return name
    }
}

public struct AnimationTimelineSchedule: Hashable, Sendable { public init() {} }

public struct Animation: Hashable, Sendable {
    public let rawValue: String
    public let duration: Double
    public let curve: AnimationCurve

    public init(_ rawValue: String) {
        self.rawValue = rawValue
        self.duration = Animation.parseDuration(rawValue)
        self.curve = Animation.parseCurve(rawValue)
    }

    public static let `default` = Animation("default")

    public static func spring() -> Animation { Animation("spring") }
    public static func easeInOut(duration: Double = 0.35) -> Animation { Animation("easeInOut(\(duration))") }
    public static func easeIn(duration: Double = 0.35) -> Animation { Animation("easeIn(\(duration))") }
    public static func easeOut(duration: Double = 0.35) -> Animation { Animation("easeOut(\(duration))") }
    public static func linear(duration: Double = 0.35) -> Animation { Animation("linear(\(duration))") }

    public func delay(_ delay: Double) -> Animation {
        Animation("\(rawValue).delay(\(delay))")
    }

    public func repeatForever(autoreverses: Bool = true) -> Animation {
        Animation("\(rawValue).repeatForever(\(autoreverses))")
    }

    private static func parseDuration(_ raw: String) -> Double {
        guard let open = raw.firstIndex(of: "("),
              let close = raw.firstIndex(of: ")")
        else { return 0.35 }
        return Double(raw[raw.index(after: open)..<close]) ?? 0.35
    }

    private static func parseCurve(_ raw: String) -> AnimationCurve {
        let lower = raw.lowercased()
        if lower.hasPrefix("easeinout") || lower == "default" { return .easeInOut }
        if lower.hasPrefix("easein") { return .easeIn }
        if lower.hasPrefix("easeout") { return .easeOut }
        if lower.hasPrefix("linear") { return .linear }
        if lower.hasPrefix("spring") { return .spring }
        return .easeInOut
    }
}

@discardableResult
public func withAnimation<T>(_ animation: Animation? = nil, _ body: () -> T) -> T {
    body()
}

public extension View {
    func animation<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
        _AnimationModifier(
            content: AnyView(self),
            animation: animation.map { _AnyAnimation(curve: $0.curve, duration: $0.duration) },
            value: value
        )
    }

    func phaseAnimator<Phase: Hashable, Content: View>(
        _ phases: [Phase],
        @ViewBuilder content: @escaping (Self, Phase) -> Content,
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
        @ViewBuilder content: @escaping (Self, Phase) -> Content,
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
