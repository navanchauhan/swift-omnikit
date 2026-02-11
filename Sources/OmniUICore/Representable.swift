import Foundation

#if canImport(AppKit)
import AppKit

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
    // Representable views are compile-time shims in OmniUI's text renderer for now.
    _ = view
    _ = ctx
    return .empty
}
#endif

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
    // Representable views are compile-time shims in OmniUI's text renderer for now.
    _ = view
    _ = ctx
    return .empty
}
#endif
