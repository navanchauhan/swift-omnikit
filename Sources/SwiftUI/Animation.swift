import OmniUICore

public struct AnimationTimelineSchedule: Hashable, Sendable { public init() {} }

public struct Animation: Hashable, Sendable {
    public let rawValue: String
    /// The parsed duration in seconds (used by withAnimation to schedule ticks).
    public let duration: Double
    /// The parsed curve kind (used by the runtime for easing).
    public let curve: AnimationCurve

    public init(_ rawValue: String) {
        self.rawValue = rawValue
        self.duration = Animation._parseDuration(rawValue)
        self.curve = Animation._parseCurve(rawValue)
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

    // MARK: - Parsing helpers

    private static func _parseDuration(_ raw: String) -> Double {
        // Extract e.g. "0.35" from "easeInOut(0.35)"
        guard let open = raw.firstIndex(of: "("),
              let close = raw.firstIndex(of: ")") else {
            return 0.35 // default duration
        }
        let inner = String(raw[raw.index(after: open)..<close])
        return Double(inner) ?? 0.35
    }

    private static func _parseCurve(_ raw: String) -> AnimationCurve {
        let lower = raw.lowercased()
        if lower.hasPrefix("easeinout") || lower == "default" { return .easeInOut }
        if lower.hasPrefix("easein") { return .easeIn }
        if lower.hasPrefix("easeout") { return .easeOut }
        if lower.hasPrefix("linear") { return .linear }
        if lower.hasPrefix("spring") { return .spring }
        return .easeInOut
    }
}

/// Execute the body immediately (state changes are synchronous), then register an
/// animation on the runtime so it keeps re-rendering with eased progress over N ticks.
@discardableResult
public func withAnimation<T>(_ animation: Animation? = nil, _ body: () -> T) -> T {
    let result = body()
    // If a runtime is available on the current task, register the animation for tick scheduling.
    if let runtime = _UIRuntime._current {
        let anim = animation ?? .default
        runtime._registerAnimation(curve: anim.curve, duration: anim.duration)
    }
    return result
}

public extension View {
    func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        let anim = animation.map { _AnyAnimation(curve: $0.curve, duration: $0.duration) }
        return _AnimationModifier(content: AnyView(self), animation: anim, value: value)
    }

    func animation(_ animation: Animation?) -> some View {
        _ = animation
        return _Passthrough(self)
    }

    func phaseAnimator<Phases: Collection, Content: View>(
        _ phases: Phases,
        @ViewBuilder content: @escaping (Self, Phases.Element) -> Content
    ) -> some View where Phases.Element: Equatable {
        _PhaseAnimatorPrimitive(phases: Array(phases).map { $0 as Any }, content: { phase in AnyView(content(self, phase as! Phases.Element)) }, intervalSeconds: 0.35)
    }

    func phaseAnimator<Phases: Collection, Content: View>(
        _ phases: Phases,
        @ViewBuilder content: @escaping (Self, Phases.Element) -> Content,
        animation: @escaping (Phases.Element) -> Animation
    ) -> some View where Phases.Element: Equatable {
        let anim = phases.first.map { animation($0) }
        let duration = anim?.duration ?? 0.35
        return _PhaseAnimatorPrimitive(phases: Array(phases).map { $0 as Any }, content: { phase in AnyView(content(self, phase as! Phases.Element)) }, intervalSeconds: duration)
    }
}
