// Minimal shape API surface for SwiftUI compatibility.
//
// These are currently rendered as simple placeholder text in the debug/notcurses renderer.

public struct CGPoint: Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
}

public struct CGSize: Hashable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public init(width: CGFloat, height: CGFloat) { self.width = width; self.height = height }
}

public struct CGRect: Hashable, Sendable {
    public var origin: CGPoint
    public var size: CGSize
    public init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.origin = CGPoint(x: x, y: y)
        self.size = CGSize(width: width, height: height)
    }
}

public struct Path: Hashable, Sendable, Shape, _PrimitiveView {
    public enum Element: Hashable, Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case rect(CGRect)
        case ellipse(CGRect)
        case closeSubpath
    }

    public private(set) var elements: [Element] = []

    public init() {}

    public init(_ rect: CGRect) {
        elements = [.rect(rect)]
    }

    public mutating func move(to p: CGPoint) { elements.append(.move(to: p)) }
    public mutating func addLine(to p: CGPoint) { elements.append(.line(to: p)) }
    public mutating func addRect(_ rect: CGRect) { elements.append(.rect(rect)) }
    public mutating func addEllipse(in rect: CGRect) { elements.append(.ellipse(rect)) }
    public mutating func closeSubpath() { elements.append(.closeSubpath) }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .shape(_ShapeNode(kind: .path))
    }
}

public protocol Shape: View {}

public struct Rectangle: Shape, _PrimitiveView {
    public typealias Body = Never
    public init() {}
    func _makeNode(_ ctx: inout _BuildContext) -> _VNode { .shape(_ShapeNode(kind: .rectangle)) }
}

public struct RoundedRectangle: Shape, _PrimitiveView {
    public typealias Body = Never
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    public init(cornerRadius: CGFloat, style: Any = ()) {
        self.cornerRadius = cornerRadius
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .shape(_ShapeNode(kind: .roundedRectangle(cornerRadius: Int(cornerRadius))))
    }
}

public struct Circle: Shape, _PrimitiveView {
    public typealias Body = Never
    public init() {}
    func _makeNode(_ ctx: inout _BuildContext) -> _VNode { .shape(_ShapeNode(kind: .circle)) }
}

public struct Ellipse: Shape, _PrimitiveView {
    public typealias Body = Never
    public init() {}
    func _makeNode(_ ctx: inout _BuildContext) -> _VNode { .shape(_ShapeNode(kind: .ellipse)) }
}

public struct Capsule: Shape, _PrimitiveView {
    public typealias Body = Never
    public init() {}
    public init(style: Any = ()) {}
    func _makeNode(_ ctx: inout _BuildContext) -> _VNode { .shape(_ShapeNode(kind: .capsule)) }
}

public struct FillStyle: Hashable, Sendable {
    public var isEOFilled: Bool
    public var antialiased: Bool
    public init(eoFill: Bool = false, antialiased: Bool = true) {
        self.isEOFilled = eoFill
        self.antialiased = antialiased
    }
}

public struct StrokeStyle: Hashable, Sendable {
    public var lineWidth: CGFloat
    public init(lineWidth: CGFloat = 1) { self.lineWidth = lineWidth }
}

public struct ShapeView<S: Shape>: View, _PrimitiveView {
    public typealias Body = Never
    let shape: S
    public init(_ shape: S) { self.shape = shape }
    func _makeNode(_ ctx: inout _BuildContext) -> _VNode { ctx.buildChild(shape) }
}

public extension Shape {
    func fill(_ content: Color = .primary, style: FillStyle = FillStyle()) -> some View {
        _Passthrough(self)
    }

    func stroke(_ content: Color = .primary, style: StrokeStyle = StrokeStyle()) -> some View {
        _Passthrough(self)
    }

    func stroke(lineWidth: CGFloat = 1) -> some View {
        _Passthrough(self)
    }
}
