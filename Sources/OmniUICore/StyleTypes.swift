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

    public static let white = Color("white")
    public static let gray = Color("gray")
    public static let yellow = Color("yellow")
}

public struct Font: Hashable, Sendable {
    public enum Design: Hashable, Sendable {
        case `default`
        case monospaced
    }

    public let name: String

    public static let caption = Font(name: "caption")
    public static let caption2 = Font(name: "caption2")

    public static func system(size: CGFloat, design: Design = .default) -> Font {
        Font(name: "system(\(size),\(design))")
    }

    // SwiftUI exposes `.system(_:, design:)` overloads; this keeps call sites compiling.
    public static func system(_ style: Font, design: Design = .default) -> Font {
        Font(name: "system(\(style.name),\(design))")
    }
}

public enum TextAlignment: Sendable {
    case leading
    case center
    case trailing
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
