// Minimal drawing/gradient API surface for SwiftUI compatibility.
// These are currently compile-first stubs; renderers may ignore them.

public struct GraphicsContext: Sendable {
    public init() {}

    public struct Shading: Hashable, Sendable {
        enum _Kind: Hashable, Sendable {
            case color(Color)
        }

        var kind: _Kind

        public static func color(_ color: Color) -> Shading {
            Shading(kind: .color(color))
        }
    }

    public mutating func fill<S: Shape>(_ shape: S, with shading: Shading, style: FillStyle = FillStyle()) {
        _ = shape
        _ = shading
        _ = style
    }
}

public struct Canvas: View, _PrimitiveView {
    public typealias Body = Never

    let renderer: (inout GraphicsContext, CGSize) -> Void

    public init(
        opaque: Bool = false,
        colorMode: Any = (),
        rendersAsynchronously: Bool = false,
        renderer: @escaping (inout GraphicsContext, CGSize) -> Void
    ) {
        _ = opaque
        _ = colorMode
        _ = rendersAsynchronously
        self.renderer = renderer
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let rs = _UIRuntime._currentRenderSize ?? _Size(width: 0, height: 0)
        var gc = GraphicsContext()
        renderer(&gc, CGSize(width: CGFloat(rs.width), height: CGFloat(rs.height)))
        return .empty
    }
}

public struct Gradient: Hashable, Sendable {
    public var colors: [Color]
    public init(colors: [Color]) {
        self.colors = colors
    }
}

public struct UnitPoint: Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let topLeading = UnitPoint(x: 0.0, y: 0.0)
    public static let bottomTrailing = UnitPoint(x: 1.0, y: 1.0)
}

public struct LinearGradient: View, _PrimitiveView {
    public typealias Body = Never

    public let gradient: Gradient
    public let startPoint: UnitPoint
    public let endPoint: UnitPoint

    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _ = ctx
        // No-op placeholder.
        return .empty
    }
}

public struct RadialGradient: View, _PrimitiveView {
    public typealias Body = Never

    public let gradient: Gradient
    public let center: UnitPoint
    public let startRadius: CGFloat
    public let endRadius: CGFloat

    public init(gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.gradient = gradient
        self.center = center
        self.startRadius = startRadius
        self.endRadius = endRadius
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _ = ctx
        // No-op placeholder.
        return .empty
    }
}

