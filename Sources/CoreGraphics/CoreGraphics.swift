@_exported import Foundation
@_exported import OmniUICore

public struct CGAffineTransform: Hashable, Sendable {
    public var a: CGFloat
    public var b: CGFloat
    public var c: CGFloat
    public var d: CGFloat
    public var tx: CGFloat
    public var ty: CGFloat

    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public init(translationX tx: CGFloat, y ty: CGFloat) {
        self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty)
    }

    public static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
}

public final class CGPath: @unchecked Sendable {
    public let boundingBox: CGRect

    public init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {
        if let transform {
            self.boundingBox = rect.applying(transform.pointee)
        } else {
            self.boundingBox = rect
        }
    }

    public init(rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {
        if let transform {
            self.boundingBox = rect.applying(transform.pointee)
        } else {
            self.boundingBox = rect
        }
    }
}

public final class CGImage: _OmniCGImageLike, @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let _omniImageData: Data?

    public init(width: Int = 0, height: Int = 0, data: Data? = nil) {
        self.width = width
        self.height = height
        self._omniImageData = data
    }
}

public extension CGRect {
    func applying(_ transform: CGAffineTransform) -> CGRect {
        guard transform != .identity else { return self }
        let corners: [CGPoint] = [
            CGPoint(x: self.minX, y: self.minY),
            CGPoint(x: self.maxX, y: self.minY),
            CGPoint(x: self.minX, y: self.maxY),
            CGPoint(x: self.maxX, y: self.maxY),
        ]
        let points: [CGPoint] = corners.map { point in
            let x = point.x * transform.a + point.y * transform.c + transform.tx
            let y = point.x * transform.b + point.y * transform.d + transform.ty
            return CGPoint(x: x, y: y)
        }
        let xs: [CGFloat] = points.map { $0.x }
        let ys: [CGFloat] = points.map { $0.y }
        let minX: CGFloat = xs.min() ?? 0
        let maxX: CGFloat = xs.max() ?? 0
        let minY: CGFloat = ys.min() ?? 0
        let maxY: CGFloat = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
