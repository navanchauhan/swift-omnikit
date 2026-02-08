public typealias CGFloat = Double

public struct Color: Hashable, Sendable {
    public let name: String
    public let alpha: CGFloat

    public init(_ name: String, alpha: CGFloat = 1.0) {
        self.name = name
        self.alpha = alpha
    }

    public func opacity(_ alpha: CGFloat) -> Color {
        Color(name, alpha: alpha)
    }

    public static let clear = Color("clear", alpha: 0)
    public static let primary = Color("primary")
    public static let secondary = Color("secondary")
    public static let tertiary = Color("tertiary")

    public static let accentColor = Color("accentColor")
    public static let white = Color("white")
    public static let gray = Color("gray")
    public static let yellow = Color("yellow")
}

extension Color: View, _PrimitiveView {
    public typealias Body = Never

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        // A Color acts like a background fill in SwiftUI. We model this as a background-style node
        // that fills the available layout rect in `_DebugLayout`.
        .style(fg: nil, bg: self, child: .empty)
    }
}

public struct Font: Hashable, Sendable {
    public enum Design: Hashable, Sendable {
        case `default`
        case monospaced
    }

    public let name: String

    public static let largeTitle = Font(name: "largeTitle")
    public static let title3 = Font(name: "title3")
    public static let subheadline = Font(name: "subheadline")
    public static let headline = Font(name: "headline")
    public static let body = Font(name: "body")
    public static let caption = Font(name: "caption")
    public static let caption2 = Font(name: "caption2")

    public static func system(size: CGFloat, design: Design = .default) -> Font {
        Font(name: "system(\(size),\(design))")
    }

    // SwiftUI exposes `.system(_:, design:)` overloads; this keeps call sites compiling.
    public static func system(_ style: Font, design: Design = .default) -> Font {
        Font(name: "system(\(style.name),\(design))")
    }

    public func weight(_ any: Any = ()) -> Font {
        Font(name: "\(name).weight")
    }

    public func bold() -> Font {
        Font(name: "\(name).bold")
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

public enum VerticalAlignment: Sendable {
    case top
    case center
    case bottom
}

public struct Alignment: Hashable, Sendable {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }

    public static let center = Alignment("center")
    public static let leading = Alignment("leading")
    public static let trailing = Alignment("trailing")
    public static let top = Alignment("top")
    public static let bottom = Alignment("bottom")
}

public enum Edge {
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

public enum Axis: Sendable {
    public struct Set: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let vertical = Set(rawValue: 1 << 0)
        public static let horizontal = Set(rawValue: 1 << 1)
    }
}

// SwiftUI materials (placeholder).
public struct Material: Hashable, Sendable {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public static let regularMaterial = Material("regularMaterial")
}
