// Minimal shape API surface for SwiftUI compatibility.
//
// These lower into the shared render tree and are rasterized by the debug/notcurses renderers.

import Foundation

// On Linux, CGPoint/CGSize/CGRect from swift-corelibs-foundation don't
// conform to Hashable. Provide conformance so Path.Element can derive it.
#if os(Linux)
extension CGPoint: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}
extension CGSize: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }
}
extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin)
        hasher.combine(size)
    }
}
#endif

public enum RoundedCornerStyle: Hashable, Sendable {
    case circular
    case continuous
}

public struct Path: Hashable, Sendable, Shape, _PrimitiveView {
    public enum Element: Hashable, Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case rect(CGRect)
        case ellipse(CGRect)
        case closeSubpath
    }

    public private(set) var elements: [Element] = []

    public init() {}

    public init(_ rect: CGRect) {
        elements = [.rect(rect)]
    }

    public init(ellipseIn rect: CGRect) {
        elements = [.ellipse(rect)]
    }

    public init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
        _ = cornerRadius
        elements = [.rect(rect)]
    }

    public mutating func move(to p: CGPoint) { elements.append(.move(to: p)) }
    public mutating func addLine(to p: CGPoint) { elements.append(.line(to: p)) }
    public mutating func addQuadCurve(to p: CGPoint, control: CGPoint) { elements.append(.quadCurve(to: p, control: control)) }
    public mutating func addCurve(to p: CGPoint, control1: CGPoint, control2: CGPoint) { elements.append(.curve(to: p, control1: control1, control2: control2)) }
    public mutating func addRect(_ rect: CGRect) { elements.append(.rect(rect)) }
    public mutating func addEllipse(in rect: CGRect) { elements.append(.ellipse(rect)) }
    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool) {
        _ = startAngle
        _ = clockwise
        let point = CGPoint(
            x: center.x + cos(endAngle.radians) * radius,
            y: center.y + sin(endAngle.radians) * radius
        )
        elements.append(.line(to: point))
    }
    public mutating func closeSubpath() { elements.append(.closeSubpath) }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .shape(_ShapeNode(kind: .path, pathElements: elements))
    }
}

public protocol Shape: View {}

@MainActor
public extension Shape where Self == RoundedRectangle {
    static func rect(cornerRadius: CGFloat = 0) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius)
    }
}

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

    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {
        _ = style
        self.cornerRadius = cornerRadius
    }

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        .shape(_ShapeNode(kind: .roundedRectangle(cornerRadius: Int(cornerRadius))))
    }
}

public struct Circle: Shape, _PrimitiveView {
    public typealias Body = Never
    public init() {}
    public func trim(from startFraction: CGFloat = 0, to endFraction: CGFloat = 1) -> Circle {
        _ = startFraction
        _ = endFraction
        return self
    }
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
    public init(style: RoundedCornerStyle = .circular) { _ = style }
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
    public enum LineCap: Hashable, Sendable {
        case butt
        case round
        case square
    }

    public var lineWidth: CGFloat
    public var lineCap: LineCap
    public var dash: [CGFloat]
    public var dashPhase: CGFloat

    public init(
        lineWidth: CGFloat = 1,
        lineCap: LineCap = .butt,
        dash: [CGFloat] = [],
        dashPhase: CGFloat = 0
    ) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.dash = dash
        self.dashPhase = dashPhase
    }
}

public struct ShapeView<S: Shape>: View, _PrimitiveView {
    public typealias Body = Never
    let shape: S
    public init(_ shape: S) { self.shape = shape }
    func _makeNode(_ ctx: inout _BuildContext) -> _VNode { ctx.buildChild(shape) }
}

@MainActor
public extension Shape {
    func fill(_ content: Color = .primary, style: FillStyle = FillStyle()) -> some View {
        _ShapeStyle(content: AnyView(self), fill: style, stroke: nil, fillColor: content, strokeColor: nil)
    }

    func fill(_ content: Material, style: FillStyle = FillStyle()) -> some View {
        _ShapeStyle(content: AnyView(self), fill: style, stroke: nil, fillColor: Color(content.raw), strokeColor: nil)
    }

    @_disfavoredOverload
    func fill<S: ShapeStyle>(_ content: S, style: FillStyle = FillStyle()) -> some View {
        _ShapeStyle(content: AnyView(self), fill: style, stroke: nil, fillColor: _omniShapeColor(from: content), strokeColor: nil)
    }

    func stroke(_ content: Color = .primary, style: StrokeStyle = StrokeStyle()) -> some View {
        _ShapeStyle(content: AnyView(self), fill: nil, stroke: style, fillColor: nil, strokeColor: content)
    }

    @_disfavoredOverload
    func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View {
        _ShapeStyle(content: AnyView(self), fill: nil, stroke: StrokeStyle(lineWidth: lineWidth), fillColor: nil, strokeColor: _omniShapeColor(from: content))
    }

    func stroke(lineWidth: CGFloat = 1) -> some View {
        _ShapeStyle(content: AnyView(self), fill: nil, stroke: StrokeStyle(lineWidth: lineWidth), fillColor: nil, strokeColor: .primary)
    }

    func strokeBorder(_ content: Color = .primary, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View {
        _ = antialiased
        return stroke(content, style: StrokeStyle(lineWidth: lineWidth))
    }

    func strokeBorder(_ content: Color = .primary, style: StrokeStyle, antialiased: Bool = true) -> some View {
        _ = antialiased
        return stroke(content, style: style)
    }

    func strokeBorder<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View {
        _ = antialiased
        return stroke(_omniShapeColor(from: content), style: style)
    }

    func strokeBorder<S>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View {
        _ = content
        _ = antialiased
        return stroke(.primary, style: StrokeStyle(lineWidth: lineWidth))
    }

    func strokeBorder(lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View {
        _ = antialiased
        return stroke(.primary, style: StrokeStyle(lineWidth: lineWidth))
    }
}

private func _omniShapeColor(from style: any ShapeStyle) -> Color {
    if let color = style as? Color {
        return color
    }
    if let material = style as? Material {
        return Color(material.raw)
    }
    if let erased = style as? AnyShapeStyle {
        return _omniShapeColor(from: erased.storage)
    }
    if let gradient = style as? LinearGradient {
        return gradient.gradient.colors.first ?? .primary
    }
    if let gradient = style as? RadialGradient {
        return gradient.gradient.colors.first ?? .primary
    }
    return .primary
}

private struct _ShapeStyle: View, _PrimitiveView {
    typealias Body = Never

    let content: AnyView
    let fill: FillStyle?
    let stroke: StrokeStyle?
    let fillColor: Color?
    let strokeColor: Color?

    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        let n = ctx.buildChild(content)
        guard case .shape(var s) = n else { return n }
        s.fillStyle = fill
        s.strokeStyle = stroke
        if let fillColor { s.fillColor = fillColor }
        if let strokeColor { s.strokeColor = strokeColor }
        return .shape(s)
    }
}
