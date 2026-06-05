/// SwiftUI-like base protocol.
///
/// OmniUI aims to preserve the surface area and value semantics of SwiftUI where practical,
/// while keeping the runtime portable (Linux) and concurrency-friendly (Swift 6 strict mode).
@MainActor
public protocol View {
    associatedtype Body: View
    @preconcurrency @MainActor @ViewBuilder var body: Body { get }
}

public extension View where Body == Never {
    var body: Never { fatalError("Primitive views have no body") }
}

extension Never: View {
    public typealias Body = Never
    public var body: Never { fatalError("Never has no body") }
}

extension Optional: View where Wrapped: View {
    public typealias Body = Never
}

extension Optional: _PrimitiveView where Wrapped: View {
    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        switch self {
        case .some(let wrapped):
            return OmniUICore._makeNode(wrapped, &ctx)
        case .none:
            return .empty
        }
    }
}

/// Type erasure for `View`.
public struct AnyView: View {
    public typealias Body = Never

    let _makeNode: @MainActor (inout _BuildContext) -> _VNode

    public init<V: View>(_ view: V) {
        self._makeNode = { ctx in
            OmniUICore._makeNode(view, &ctx)
        }
    }
}

extension AnyView: _PrimitiveView {
    func _makeNode(_ ctx: inout _BuildContext) -> _VNode {
        _makeNode(&ctx)
    }
}

/// Internal protocol for primitive views that directly lower to nodes (do not go through `body`).
@MainActor
protocol _PrimitiveView {
    func _makeNode(_ ctx: inout _BuildContext) -> _VNode
}

@MainActor
private func _makeRepresentableNode(_ representable: any NSViewRepresentable, path: [Int]) -> _VNode {
    @MainActor
    func open<R: NSViewRepresentable>(_ value: R) -> _VNode {
        _OmniRepresentableFallback.node(for: value, path: path) ?? .empty
    }
    return _openExistential(representable, do: open)
}

@inline(__always)
@MainActor
func _makeNode<V: View>(_ view: V, _ ctx: inout _BuildContext) -> _VNode {
    if let primitive = view as? _PrimitiveView {
        return primitive._makeNode(&ctx)
    }
    if let representable = view as? any NSViewRepresentable {
        return _makeRepresentableNode(representable, path: ctx.path)
    }
    #if canImport(UIKit)
    if view is any UIViewRepresentable {
        return .empty
    }
    #endif
    return _makeNode(view.body, &ctx)
}
