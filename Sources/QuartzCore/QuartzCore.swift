@_exported import AppKit
@_exported import CoreGraphics
import Foundation

open class CAAnimation: NSObject {
    public var duration: TimeInterval = 0
    public var repeatCount: Float = 0
    public var timingFunction: CAMediaTimingFunction?
    public var isRemovedOnCompletion: Bool = true
}

public final class CABasicAnimation: CAAnimation {
    public let keyPath: String?
    public var fromValue: Any?
    public var toValue: Any?

    public init(keyPath: String?) {
        self.keyPath = keyPath
        super.init()
    }
}

public struct CAMediaTimingFunctionName: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static let linear = CAMediaTimingFunctionName(rawValue: "linear")
}

public final class CAMediaTimingFunction: NSObject {
    public let name: CAMediaTimingFunctionName

    public init(name: CAMediaTimingFunctionName) {
        self.name = name
        super.init()
    }
}

public enum CATransaction {
    public static func begin() {}
    public static func commit() {}
    public static func setDisableActions(_ flag: Bool) { _ = flag }
}

public struct CAShapeLayerLineCap: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static let butt = CAShapeLayerLineCap(rawValue: "butt")
    public static let round = CAShapeLayerLineCap(rawValue: "round")
    public static let square = CAShapeLayerLineCap(rawValue: "square")
}

public final class CAShapeLayer: CALayer {
    public var fillColor: CGColor?
    public var strokeColor: CGColor?
    public var lineWidth: CGFloat = 1
    public var lineCap: CAShapeLayerLineCap = .butt
    public var strokeStart: CGFloat = 0
    public var strokeEnd: CGFloat = 1
    public var path: CGPath?
    public var contentsScale: CGFloat = 1
}
