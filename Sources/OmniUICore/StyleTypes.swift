import Foundation

public protocol ShapeStyle: Sendable {}

public struct Color: Hashable, Sendable, ShapeStyle {
    public enum RGBColorSpace: Hashable, Sendable {
        case sRGB
        case sRGBLinear
        case displayP3
    }

    public let name: String
    public let alpha: CGFloat

    public init(_ name: String, alpha: CGFloat = 1.0) {
        self.name = name
        self.alpha = alpha
    }

    // Compatibility initializers used by many SwiftUI call sites.
    public init(_ any: Any) {
        self.name = String(describing: any)
        self.alpha = 1.0
    }

    public init(hue: Double, saturation: Double, brightness: Double) {
        self.name = "hsb(\(hue),\(saturation),\(brightness))"
        self.alpha = 1.0
    }

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, opacity: CGFloat = 1.0) {
        self.name = "rgb(\(red),\(green),\(blue))"
        self.alpha = opacity
    }

    public init(white: CGFloat, opacity: CGFloat = 1.0) {
        self.name = "rgb(\(white),\(white),\(white))"
        self.alpha = opacity
    }

    public init(_ colorSpace: RGBColorSpace, red: CGFloat, green: CGFloat, blue: CGFloat, opacity: CGFloat = 1.0) {
        self.name = "\(colorSpace):rgb(\(red),\(green),\(blue))"
        self.alpha = opacity
    }

    public func opacity(_ alpha: CGFloat) -> Color {
        Color(name, alpha: alpha)
    }

    public static let clear = Color("clear", alpha: 0)
    public static let primary = Color("primary")
    public static let secondary = Color("secondary")
    public static let tertiary = Color("tertiary")
    public static let quaternary = Color("quaternary")

    public static let accentColor = Color("accentColor")
    public static let tint = Color("tint")
    public static let black = Color("black")
    public static let white = Color("white")
    public static let gray = Color("gray")
    public static let red = Color("red")
    public static let orange = Color("orange")
    public static let yellow = Color("yellow")
    public static let green = Color("green")
    public static let mint = Color("mint")
    public static let teal = Color("teal")
    public static let cyan = Color("cyan")
    public static let blue = Color("blue")
    public static let indigo = Color("indigo")
    public static let purple = Color("purple")
    public static let pink = Color("pink")
    public static let brown = Color("brown")
}

public struct AnyShapeStyle: ShapeStyle {
    public let storage: any ShapeStyle

    public init(_ style: Color) {
        self.storage = style
    }

    public init(_ style: Material) {
        self.storage = style
    }

    public init<S: ShapeStyle>(_ style: S) {
        self.storage = style
    }
}

extension Color: RawRepresentable {
    public typealias RawValue = String

    public init?(rawValue: String) {
        // Format: `<name>|<alpha>`
        let parts = rawValue.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2, let a = Double(parts[1]) {
            self.init(parts[0], alpha: CGFloat(a))
            return
        }
        // Back-compat: treat the entire raw value as the name (alpha=1).
        self.init(rawValue, alpha: 1.0)
    }

    public var rawValue: String {
        "\(name)|\(alpha)"
    }
}

extension Color: View, _PrimitiveView {
    public typealias Body = Never

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // A Color used as a View fills the entire proposed region with a solid fill,
        // just like SwiftUI's `Color.red` filling its container.
        .gradient(_GradientNode(kind: .linear(startPoint: UnitPoint(x: 0.5, y: 0), endPoint: UnitPoint(x: 0.5, y: 1)), colors: [self]))
    }
}

public struct Font: Hashable, Sendable {
    public enum Design: Hashable, Sendable {
        case `default`
        case monospaced
        case rounded
        case serif
    }

    public enum Weight: Hashable, Sendable {
        case ultraLight
        case thin
        case light
        case regular
        case medium
        case semibold
        case bold
        case heavy
        case black
    }

    public let name: String

    public static let largeTitle = Font(name: "largeTitle")
    public static let title = Font(name: "title")
    public static let title2 = Font(name: "title2")
    public static let title3 = Font(name: "title3")
    public static let subheadline = Font(name: "subheadline")
    public static let headline = Font(name: "headline")
    public static let body = Font(name: "body")
    public static let caption = Font(name: "caption")
    public static let caption2 = Font(name: "caption2")
    public static let callout = Font(name: "callout")
    public static let footnote = Font(name: "footnote")

    public static func system(size: CGFloat, design: Design = .default) -> Font {
        Font(name: "system(\(size),\(design))")
    }

    public static func system(size: CGFloat, weight: Weight, design: Design = .default) -> Font {
        Font(name: "system(\(size),\(weight),\(design))")
    }

    public static func custom(_ name: String, size: CGFloat) -> Font {
        Font(name: "custom(\(name),\(size))")
    }

    // SwiftUI exposes `.system(_:, design:)` overloads; this keeps call sites compiling.
    public static func system(_ style: Font, design: Design = .default) -> Font {
        Font(name: "system(\(style.name),\(design))")
    }

    public func weight(_ weight: Weight) -> Font {
        Font(name: "\(name).weight(\(weight))")
    }

    public func weight(_ any: Any = ()) -> Font {
        Font(name: "\(name).weight")
    }

    public func bold() -> Font {
        Font(name: "\(name).bold")
    }

    public func italic() -> Font {
        Font(name: "\(name).italic")
    }

    public func monospaced() -> Font {
        Font(name: "\(name).monospaced")
    }
}

struct _FontSemanticDescriptor: Hashable, Sendable {
    let size: Double?
    let weight: String?
    let design: String?
    let italic: Bool
}

extension Font {
    var _semanticDescriptor: _FontSemanticDescriptor {
        let lower = name.lowercased()
        var size: Double?
        var weight: String?
        var design: String?

        if let systemArguments = Self._arguments(in: lower, prefix: "system") {
            if let first = systemArguments.first {
                size = Double(first) ?? Self._namedTextStyleSize(first)
            }
            for argument in systemArguments.dropFirst() {
                if Self._isKnownWeight(argument) {
                    weight = argument
                } else if Self._isKnownDesign(argument) {
                    design = argument
                }
            }
        } else if let customArguments = Self._arguments(in: lower, prefix: "custom") {
            size = customArguments.reversed().lazy.compactMap(Double.init).first
        } else {
            size = Self._namedTextStyleSize(lower)
        }

        if lower.contains("ultralight") {
            weight = "ultralight"
        } else if lower.contains("semibold") {
            weight = "semibold"
        } else if lower.contains("black") {
            weight = "black"
        } else if lower.contains("heavy") {
            weight = "heavy"
        } else if lower.contains("bold") {
            weight = "bold"
        } else if lower.contains("medium") {
            weight = "medium"
        } else if lower.contains("regular") {
            weight = "regular"
        } else if lower.contains("light") {
            weight = "light"
        } else if lower.contains("thin") {
            weight = "thin"
        }

        for knownDesign in ["monospaced", "rounded", "serif"] where lower.contains(knownDesign) {
            design = knownDesign
        }

        return _FontSemanticDescriptor(
            size: size,
            weight: weight,
            design: design,
            italic: lower.contains("italic")
        )
    }

    private static func _arguments(in value: String, prefix: String) -> [String]? {
        let start = "\(prefix)("
        guard value.hasPrefix(start), value.hasSuffix(")") else { return nil }
        let inner = value.dropFirst(start.count).dropLast()
        return inner
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func _namedTextStyleSize(_ style: String) -> Double? {
        switch style {
        case "largetitle": return 34
        case "title": return 28
        case "title2": return 22
        case "title3": return 20
        case "headline": return 17
        case "body": return 17
        case "callout": return 16
        case "subheadline": return 15
        case "caption": return 12
        case "caption2": return 11
        default: return nil
        }
    }

    private static func _isKnownWeight(_ value: String) -> Bool {
        switch value {
        case "ultralight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black":
            return true
        default:
            return false
        }
    }

    private static func _isKnownDesign(_ value: String) -> Bool {
        switch value {
        case "default", "monospaced", "rounded", "serif":
            return true
        default:
            return false
        }
    }
}

public enum TextAlignment: Sendable {
    case leading
    case center
    case trailing
}

public enum HorizontalAlignment: Sendable {
    case leading
    case center
    case trailing
}

public enum HorizontalEdge: Sendable {
    case leading
    case trailing
}

public enum VerticalAlignment: Sendable {
    case top
    case center
    case bottom

    public static var firstTextBaseline: VerticalAlignment { .center }
    public static var lastTextBaseline: VerticalAlignment { .center }
}

public struct Alignment: Hashable, Sendable {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }

    public static let center = Alignment("center")
    public static let leading = Alignment("leading")
    public static let trailing = Alignment("trailing")
    public static let top = Alignment("top")
    public static let bottom = Alignment("bottom")
    public static let topLeading = Alignment("topLeading")
    public static let topTrailing = Alignment("topTrailing")
    public static let bottomLeading = Alignment("bottomLeading")
    public static let bottomTrailing = Alignment("bottomTrailing")
}

public enum Edge: Hashable, Sendable {
    case top
    case leading
    case bottom
    case trailing

    public struct Set: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let top = Set(rawValue: 1 << 0)
        public static let leading = Set(rawValue: 1 << 1)
        public static let bottom = Set(rawValue: 1 << 2)
        public static let trailing = Set(rawValue: 1 << 3)

        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public static let all: Set = [.top, .leading, .bottom, .trailing]
    }
}

public enum SymbolRenderingMode: Hashable, Sendable {
    case monochrome
    case hierarchical
    case palette
    case multicolor
}

public struct EdgeInsets: Hashable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init() {
        self.init(top: 0, leading: 0, bottom: 0, trailing: 0)
    }

    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

public enum ControlSize: Hashable, Sendable {
    case mini
    case small
    case regular
    case large
}

public struct PresentationDetent: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let medium = PresentationDetent("medium")
    public static let large = PresentationDetent("large")
}

public enum ContentMode: Sendable {
    case fit
    case fill
}

public struct Transaction: @unchecked Sendable {
    public var animation: Any?
    public var disablesAnimations: Bool

    public init(animation: Any? = nil, disablesAnimations: Bool = false) {
        self.animation = animation
        self.disablesAnimations = disablesAnimations
    }
}

@discardableResult
public func withTransaction<T>(_ transaction: Transaction, _ body: () throws -> T) rethrows -> T {
    _ = transaction
    return try body()
}

public struct Angle: Hashable, Sendable {
    public var radians: Double
    public var degrees: Double { radians * 180.0 / .pi }

    public init(radians: Double) { self.radians = radians }
    public init(degrees: Double) { self.radians = degrees * .pi / 180.0 }

    public static func radians(_ value: Double) -> Angle { Angle(radians: value) }
    public static func degrees(_ value: Double) -> Angle { Angle(degrees: value) }
    public static let zero = Angle(radians: 0)
}

public enum Axis: Sendable {
    public struct Set: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let vertical = Set(rawValue: 1 << 0)
        public static let horizontal = Set(rawValue: 1 << 1)
    }
}

public struct ScrollGeometry: Equatable, Sendable {
    public var contentOffset: CGPoint
    public var contentSize: CGSize
    public var visibleRect: CGRect

    public init(contentOffset: CGPoint = .zero, contentSize: CGSize = .zero, visibleRect: CGRect = .zero) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.visibleRect = visibleRect
    }
}

public enum ScrollPhase: Hashable, Sendable {
    case idle
    case tracking
    case interacting
    case decelerating
    case animating
}

public struct ScrollPhaseChangeContext: Sendable {
    public var geometry: ScrollGeometry

    public init(geometry: ScrollGeometry = ScrollGeometry()) {
        self.geometry = geometry
    }
}

// MARK: Text Input (stubs)

public enum UIKeyboardType: Hashable, Sendable {
    case `default`
    case URL
}

public enum TextInputAutocapitalization: Hashable, Sendable {
    case never
    case sentences
    case words
    case characters
}

public struct UITextContentType: Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.rawValue = value }

    public static let URL = UITextContentType("URL")
}

// SwiftUI materials (placeholder).
public struct Material: Hashable, Sendable, ShapeStyle {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public static let bar = Material("bar")
    public static let background = Material("background")
    public static let regularMaterial = Material("regularMaterial")
    public static let ultraThinMaterial = Material("ultraThinMaterial")
    public static let thinMaterial = Material("thinMaterial")
}

public enum Visibility: Hashable, Sendable {
    case automatic
    case visible
    case hidden
}

public enum TextSelection: Hashable, Sendable {
    case enabled
    case disabled
}

public struct NavigationTransition: Hashable, Sendable {
    public init() {}
}

public struct ContentTransition: Hashable, Sendable {
    public init() {}

    public static func symbolEffect(_ effect: SymbolEffect) -> ContentTransition {
        _ = effect
        return ContentTransition()
    }
}

public struct SymbolEffect: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let bounce = SymbolEffect("bounce")
    public static let replace = SymbolEffect("replace")

    public var down: SymbolEffect { SymbolEffect("\(rawValue).down") }
    public var downUp: SymbolEffect { SymbolEffect("\(rawValue).downUp") }
}

public struct SymbolEffectOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let `default` = SymbolEffectOptions([])
}

public struct AccessibilityTraits: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let isButton = AccessibilityTraits(rawValue: 1 << 0)
    public static let isHeader = AccessibilityTraits(rawValue: 1 << 1)
}

public struct AnyTransition: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static var opacity: AnyTransition { AnyTransition("opacity") }
    public static var slide: AnyTransition { AnyTransition("slide") }
    public static var scale: AnyTransition { AnyTransition("scale") }
    public static var identity: AnyTransition { AnyTransition("identity") }
    public static func move(edge: Edge) -> AnyTransition { AnyTransition("move(\(edge))") }
    public static func push(from edge: Edge) -> AnyTransition { AnyTransition("push(\(edge))") }
    public static func scale(scale: CGFloat) -> AnyTransition { AnyTransition("scale(\(scale))") }

    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition("asymmetric(insertion:\(insertion.rawValue),removal:\(removal.rawValue))")
    }

    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition("\(rawValue)+\(other.rawValue)")
    }

    public func animation(_ animation: Animation?) -> AnyTransition {
        _ = animation
        return self
    }
}

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
    public static let easeInOut = Animation("easeInOut")
    public static let easeIn = Animation("easeIn")
    public static let easeOut = Animation("easeOut")
    public static let linear = Animation("linear")

    public static func spring() -> Animation { Animation("spring") }
    public static func spring(
        response: Double,
        dampingFraction: Double,
        blendDuration: Double = 0
    ) -> Animation {
        Animation("spring(response:\(response),damping:\(dampingFraction),blend:\(blendDuration))")
    }
    public static func easeInOut(duration: Double = 0.35) -> Animation {
        Animation("easeInOut(\(duration))")
    }
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
    _ = animation
    return body()
}

/// Easing curves for terminal tick-driven animations.
public enum AnimationCurve: Hashable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case spring

    /// Evaluate the curve at a linear progress value t ∈ [0,1], returning the eased value.
    public func evaluate(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
        case .easeInOut:
            // Cubic bezier approximation: ease-in-out
            return t < 0.5
                ? 2 * t * t
                : 1 - 2 * (1 - t) * (1 - t)
        case .spring:
            // Simple damped spring approximation for terminal use
            return 1 - (1 - t) * (1 - t)
        }
    }
}
