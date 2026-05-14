import Foundation

#if canImport(AppKit) && !os(Linux)
import AppKit
#else
open class NSView: NSObject {
    public override init() {
        super.init()
    }

    public weak var window: _OmniNSWindow?
}

open class _OmniNSWindow: NSObject {
    public let tab = _OmniNSWindowTab()
}

open class _OmniNSWindowTab: NSObject {
    public var title: String = ""
}
#endif

public struct NSViewRepresentableContext<Representable: NSViewRepresentable> {
    public let coordinator: Representable.Coordinator

    public init(coordinator: Representable.Coordinator) {
        self.coordinator = coordinator
    }
}

public protocol NSViewRepresentable: View where Body == Never {
    associatedtype NSViewType: NSView
    associatedtype Coordinator = Void

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSViewType
    func updateNSView(_ nsView: NSViewType, context: NSViewRepresentableContext<Self>)
    static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator)
    func makeCoordinator() -> Coordinator
}

public extension NSViewRepresentable {
    typealias Context = NSViewRepresentableContext<Self>

    static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator) {
        _ = nsView
        _ = coordinator
    }
}

public extension NSViewRepresentable where Coordinator == Void {
    func makeCoordinator() -> Void {}
}

@inline(__always)
func _makeNode<V: NSViewRepresentable>(_ view: V, _ ctx: inout _BuildContext) -> _VNode {
    _OmniRepresentableFallback.node(for: view, path: ctx.path)
        ?? .style(fg: .secondary, bg: nil, child: .text("NSView: \(String(describing: V.NSViewType.self))"))
}

#if canImport(UIKit)
import UIKit

public struct UIViewRepresentableContext<Representable: UIViewRepresentable> {
    public let coordinator: Representable.Coordinator

    public init(coordinator: Representable.Coordinator) {
        self.coordinator = coordinator
    }
}

public protocol UIViewRepresentable: View where Body == Never {
    associatedtype UIViewType: UIView
    associatedtype Coordinator = Void

    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIViewType
    func updateUIView(_ uiView: UIViewType, context: UIViewRepresentableContext<Self>)
    static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator)
    func makeCoordinator() -> Coordinator
}

public extension UIViewRepresentable {
    typealias Context = UIViewRepresentableContext<Self>

    static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {
        _ = uiView
        _ = coordinator
    }
}

public extension UIViewRepresentable where Coordinator == Void {
    func makeCoordinator() -> Void {}
}

@inline(__always)
func _makeNode<V: UIViewRepresentable>(_ view: V, _ ctx: inout _BuildContext) -> _VNode {
    _ = view.makeCoordinator()
    _ = ctx
    return .style(fg: .secondary, bg: nil, child: .text("UIView: \(String(describing: V.UIViewType.self))"))
}
#endif
