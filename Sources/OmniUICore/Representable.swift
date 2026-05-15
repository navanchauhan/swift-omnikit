import Foundation

#if canImport(AppKit) && !os(Linux)
import AppKit
#else
open class NSView: NSObject {
    public static let noIntrinsicMetric: CGFloat = -1

    public var frame: CGRect
    public var bounds: CGRect { CGRect(origin: .zero, size: frame.size) }
    public weak var superview: NSView?
    public private(set) var subviews: [NSView] = []
    public private(set) weak var window: NSWindow?
    public var wantsLayer: Bool = false
    public var layer: CALayer?
    public var needsDisplay: Bool = false
    public var needsLayout: Bool = false
    public var translatesAutoresizingMaskIntoConstraints: Bool = true
    public var constraints: [NSLayoutConstraint] = []
    public private(set) var registeredDraggedTypes: [NSPasteboard.PasteboardType] = []
    open var appearance: NSAppearance? {
        didSet {
            _notifyEffectiveAppearanceChangedRecursively()
        }
    }
    open var effectiveAppearance: NSAppearance {
        if let appearance {
            return appearance
        }
        if let inherited = superview?.effectiveAppearance {
            return inherited
        }
        if let inherited = window?.appearance {
            return inherited
        }
        if let inherited = NSApp.appearance {
            return inherited
        }
        return NSAppearance(named: _omniEffectiveAppearanceColorScheme() == .light ? .aqua : .darkAqua)!
    }
    open var isFlipped: Bool { false }

    public override init() {
        self.frame = .zero
        super.init()
    }

    public init(frame frameRect: CGRect) {
        self.frame = frameRect
        super.init()
    }

    public required init?(coder: NSCoder) {
        self.frame = .zero
        super.init()
    }

    open var intrinsicContentSize: CGSize {
        CGSize(width: Self.noIntrinsicMetric, height: Self.noIntrinsicMetric)
    }

    open func addSubview(_ view: NSView) {
        if view.superview !== self {
            view.removeFromSuperview()
            if view.frame.size == .zero, bounds.size != .zero {
                view.frame = bounds
            }
            subviews.append(view)
            view.superview = self
            view.viewDidMoveToSuperview()
            view._setWindowRecursively(window)
            view._notifyEffectiveAppearanceChangedRecursively()
        }
    }

    open func removeFromSuperview() {
        guard let superview else { return }
        _setWindowRecursively(nil)
        superview.subviews.removeAll { $0 === self }
        self.superview = nil
        viewDidMoveToSuperview()
        _notifyEffectiveAppearanceChangedRecursively()
    }

    open func isDescendant(of view: NSView) -> Bool {
        var current = superview
        while let candidate = current {
            if candidate === view { return true }
            current = candidate.superview
        }
        return false
    }

    open func layout() {
        _omniApplySubviewConstraints()
    }
    open func layoutSubtreeIfNeeded() {
        layout()
        for subview in subviews {
            subview.layoutSubtreeIfNeeded()
        }
    }
    open func viewDidMoveToSuperview() {}
    open func viewDidMoveToWindow() {}
    open func viewEffectiveAppearanceDidChange() {}
    open func setFrameSize(_ newSize: CGSize) {
        frame.size = newSize
        layoutSubtreeIfNeeded()
    }
    open func hitTest(_ point: CGPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        for subview in subviews.reversed() {
            let subviewPoint = convert(point, to: subview)
            if let hit = subview.hitTest(subviewPoint) {
                return hit
            }
        }
        return self
    }
    open func draw(_ dirtyRect: CGRect) { _ = dirtyRect }
    open func setNeedsDisplay(_ rect: CGRect) { _ = rect; needsDisplay = true }
    open func scrollWheel(with event: NSEvent) { _ = event }
    open func viewWillMove(toWindow newWindow: NSWindow?) { _ = newWindow }
    open func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { _ = sender; return [] }
    open func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { _ = sender; return [] }
    open func draggingExited(_ sender: NSDraggingInfo?) { _ = sender }
    open func performDragOperation(_ sender: NSDraggingInfo) -> Bool { _ = sender; return false }
    open func convert(_ point: NSPoint, from view: NSView?) -> NSPoint {
        let windowPoint = view?._omniWindowPoint(fromLocal: point) ?? point
        return _omniLocalPoint(fromWindow: windowPoint)
    }
    open func convert(_ point: NSPoint, to view: NSView?) -> NSPoint {
        let windowPoint = _omniWindowPoint(fromLocal: point)
        return view?._omniLocalPoint(fromWindow: windowPoint) ?? windowPoint
    }
    open func convert(_ rect: NSRect, from view: NSView?) -> NSRect {
        NSRect(origin: convert(rect.origin, from: view), size: rect.size)
    }
    open func convert(_ rect: NSRect, to view: NSView?) -> NSRect {
        NSRect(origin: convert(rect.origin, to: view), size: rect.size)
    }
    open func menu(for event: NSEvent) -> NSMenu? { _ = event; return nil }
    open func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool { _ = item; return true }
    open func becomeFirstResponder() -> Bool { true }
    open func resignFirstResponder() -> Bool { true }
    open func copy(_ sender: Any?) { _ = sender }
    open func paste(_ sender: Any?) { _ = sender }
    open func selectAll(_ sender: Any?) { _ = sender }
    open func registerForDraggedTypes(_ types: [NSPasteboard.PasteboardType]) {
        registeredDraggedTypes = types
    }
    open func unregisterDraggedTypes() {
        registeredDraggedTypes = []
    }
    open var enclosingScrollView: NSScrollView? { superview as? NSScrollView ?? superview?.enclosingScrollView }
    open func removeConstraint(_ constraint: NSLayoutConstraint) {
        constraints.removeAll { $0 === constraint }
    }

    public lazy var leadingAnchor = NSLayoutXAxisAnchor(item: self, attribute: .leading)
    public lazy var trailingAnchor = NSLayoutXAxisAnchor(item: self, attribute: .trailing)
    public lazy var topAnchor = NSLayoutYAxisAnchor(item: self, attribute: .top)
    public lazy var bottomAnchor = NSLayoutYAxisAnchor(item: self, attribute: .bottom)
    public lazy var widthAnchor = NSLayoutDimension(item: self, attribute: .width)
    public lazy var heightAnchor = NSLayoutDimension(item: self, attribute: .height)

    fileprivate func _omniApplySubviewConstraints() {
        for subview in subviews {
            subview._omniApplyConstraints(relativeTo: self)
        }
    }

    private func _omniApplyConstraints(relativeTo parent: NSView) {
        var leading: CGFloat?
        var trailing: CGFloat?
        var top: CGFloat?
        var bottom: CGFloat?
        var width: CGFloat?
        var height: CGFloat?

        for constraint in constraints where constraint.isActive && constraint.firstItem === self {
            switch constraint.firstAttribute {
            case .width where constraint.secondItem == nil:
                width = constraint.constant
            case .height where constraint.secondItem == nil:
                height = constraint.constant
            case .leading where constraint.secondItem === parent && constraint.secondAttribute == .leading:
                leading = constraint.constant
            case .trailing where constraint.secondItem === parent && constraint.secondAttribute == .trailing:
                trailing = constraint.constant
            case .top where constraint.secondItem === parent && constraint.secondAttribute == .top:
                top = constraint.constant
            case .bottom where constraint.secondItem === parent && constraint.secondAttribute == .bottom:
                bottom = constraint.constant
            default:
                break
            }
        }

        var nextFrame = frame
        if let leading {
            nextFrame.origin.x = leading
        }
        if let top {
            nextFrame.origin.y = top
        }
        if let width {
            nextFrame.size.width = max(0, width)
        } else if let leading, let trailing {
            nextFrame.size.width = max(0, parent.bounds.width + trailing - leading)
        }
        if let height {
            nextFrame.size.height = max(0, height)
        } else if let top, let bottom {
            nextFrame.size.height = max(0, parent.bounds.height + bottom - top)
        }

        let sizeChanged = nextFrame.size != frame.size
        frame.origin = nextFrame.origin
        if sizeChanged {
            setFrameSize(nextFrame.size)
        } else {
            frame.size = nextFrame.size
        }
    }

    fileprivate func _setWindowRecursively(_ newWindow: NSWindow?) {
        guard window !== newWindow else { return }
        viewWillMove(toWindow: newWindow)
        window = newWindow
        viewDidMoveToWindow()
        _notifyEffectiveAppearanceChangedRecursively()
        for subview in subviews {
            subview._setWindowRecursively(newWindow)
        }
    }

    fileprivate func _notifyEffectiveAppearanceChangedRecursively() {
        viewEffectiveAppearanceDidChange()
        for subview in subviews {
            subview._notifyEffectiveAppearanceChangedRecursively()
        }
    }

    private func _omniOriginInWindowCoordinates() -> CGPoint {
        var origin = frame.origin
        var current = superview
        while let view = current {
            origin.x += view.frame.origin.x
            origin.y += view.frame.origin.y
            current = view.superview
        }
        return origin
    }

    private func _omniWindowPoint(fromLocal point: CGPoint) -> CGPoint {
        let origin = _omniOriginInWindowCoordinates()
        return CGPoint(x: point.x + origin.x, y: point.y + origin.y)
    }

    private func _omniLocalPoint(fromWindow point: CGPoint) -> CGPoint {
        let origin = _omniOriginInWindowCoordinates()
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }
}

open class _OmniNSWindow: NSObject, @unchecked Sendable {
    public typealias SendEventInterceptor = @Sendable (NSWindow, NSEvent) -> Bool

    public enum ButtonType: Hashable, Sendable {
        case closeButton
        case miniaturizeButton
        case zoomButton
    }

    public static let didResignKeyNotification = Notification.Name("NSWindowDidResignKeyNotification")
    public static let didResignMainNotification = Notification.Name("NSWindowDidResignMainNotification")
    public static let didBecomeKeyNotification = Notification.Name("NSWindowDidBecomeKeyNotification")
    public static let didBecomeMainNotification = Notification.Name("NSWindowDidBecomeMainNotification")
    public static let didEnterFullScreenNotification = Notification.Name("NSWindowDidEnterFullScreenNotification")
    public static let didExitFullScreenNotification = Notification.Name("NSWindowDidExitFullScreenNotification")
    public static let willCloseNotification = Notification.Name("NSWindowWillCloseNotification")
    public let tab = _OmniNSWindowTab()
    public var contentView: NSView? {
        didSet {
            oldValue?._setWindowRecursively(nil)
            contentView?._setWindowRecursively(self as? NSWindow)
        }
    }
    public var appearance: NSAppearance? {
        didSet {
            contentView?._notifyEffectiveAppearanceChangedRecursively()
        }
    }
    public var backgroundColor: NSColor?
    public var parent: NSWindow?
    public var styleMask: NSWindowStyleMask = []
    public weak var firstResponder: NSView?
    public var titlebarAppearsTransparent: Bool = false
    public var contentLayoutRect: NSRect {
        guard let contentView else { return .zero }
        return NSRect(origin: .zero, size: contentView.frame.size)
    }
    public var screen: NSScreen? = .main
    private var lastMouseLocation: NSPoint = .zero
    private var standardWindowButtons: [ButtonType: NSButton] = [:]
    private lazy var titlebarContainerView: NSView = {
        let frameView = NSView()
        let titlebarView = NSView()
        frameView.addSubview(titlebarView)
        return frameView
    }()

    public override init() {
        super.init()
        if let window = self as? NSWindow, !NSApp.windows.contains(where: { $0 === window }) {
            NSApp.windows.append(window)
        }
    }

    deinit {
        if let window = self as? NSWindow {
            NSApp.windows.removeAll { $0 === window }
            if NSApp.keyWindow === window {
                NSApp.keyWindow = nil
            }
        }
    }

    open func makeKey() {
        guard let window = self as? NSWindow else { return }
        guard NSApp.keyWindow !== window else { return }
        let previous = NSApp.keyWindow
        NSApp.keyWindow = window
        if let previous {
            NotificationCenter.default.post(name: Self.didResignKeyNotification, object: previous)
            NotificationCenter.default.post(name: Self.didResignMainNotification, object: previous)
        }
        NotificationCenter.default.post(name: Self.didBecomeKeyNotification, object: window)
        NotificationCenter.default.post(name: Self.didBecomeMainNotification, object: window)
    }
    open func makeKeyAndOrderFront(_ sender: Any?) {
        _ = sender
        makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
    open func toggleFullScreen(_ sender: Any?) {
        _ = sender
        if styleMask.contains(.fullScreen) {
            styleMask.remove(.fullScreen)
            NotificationCenter.default.post(name: Self.didExitFullScreenNotification, object: self)
        } else {
            styleMask.insert(.fullScreen)
            NotificationCenter.default.post(name: Self.didEnterFullScreenNotification, object: self)
        }
    }
    open func _recordMouseLocation(_ location: NSPoint) {
        lastMouseLocation = location
    }
    open func sendEvent(_ event: NSEvent) {
        _recordMouseLocation(event.locationInWindow)
        if let window = self as? NSWindow, Self._omniDispatchSendEventInterceptors(window: window, event: event) {
            return
        }
        guard NSEvent._deliverLocalMonitors(event) != nil else { return }
        if event.type == .rightMouseDown || event.type == .rightMouseUp {
            _ = _omniPresentContextMenu(for: event)
        } else if event.type == .scrollWheel {
            _ = _omniDispatchScrollWheel(for: event)
        }
    }

    @discardableResult
    public static func _omniAddSendEventInterceptor(_ interceptor: @escaping SendEventInterceptor) -> Any {
        _OmniWindowSendEventInterceptorRegistry.shared.add(interceptor)
    }

    public static func _omniRemoveSendEventInterceptor(_ token: Any) {
        _OmniWindowSendEventInterceptorRegistry.shared.remove(token)
    }

    private static func _omniDispatchSendEventInterceptors(window: NSWindow, event: NSEvent) -> Bool {
        _OmniWindowSendEventInterceptorRegistry.shared.dispatch(window: window, event: event)
    }

    open var mouseLocationOutsideOfEventStream: NSPoint { lastMouseLocation }
    open func makeFirstResponder(_ responder: NSView?) -> Bool {
        guard firstResponder !== responder else { return true }
        guard responder?.becomeFirstResponder() ?? true else { return false }
        if firstResponder?.resignFirstResponder() == false { return false }
        firstResponder = responder
        return true
    }

    open func standardWindowButton(_ button: ButtonType) -> NSButton? {
        if let existing = standardWindowButtons[button] {
            return existing
        }
        let control = NSButton()
        control.isBordered = false
        control.frame = NSRect(x: CGFloat(standardWindowButtons.count) * 18, y: 0, width: 14, height: 14)
        titlebarContainerView.subviews.first?.addSubview(control)
        standardWindowButtons[button] = control
        return control
    }
}

private final class _OmniWindowSendEventInterceptorRegistry: @unchecked Sendable {
    typealias Interceptor = _OmniNSWindow.SendEventInterceptor

    static let shared = _OmniWindowSendEventInterceptorRegistry()

    private let lock = NSLock()
    private var interceptors: [UUID: Interceptor] = [:]

    private init() {}

    @discardableResult
    func add(_ interceptor: @escaping Interceptor) -> Any {
        let id = UUID()
        lock.lock()
        interceptors[id] = interceptor
        lock.unlock()
        return id
    }

    func remove(_ token: Any) {
        guard let id = token as? UUID else { return }
        lock.lock()
        interceptors.removeValue(forKey: id)
        lock.unlock()
    }

    func dispatch(window: NSWindow, event: NSEvent) -> Bool {
        lock.lock()
        let current = Array(interceptors.values)
        lock.unlock()
        for interceptor in current where interceptor(window, event) {
            return true
        }
        return false
    }
}

open class _OmniNSWindowTab: NSObject {
    public var title: String = ""
}

public final class CALayer: NSObject {
    public var backgroundColor: CGColor?
}

public class NSLayoutAnchor<AnchorType>: NSObject {
    fileprivate weak var item: NSView?
    fileprivate let attribute: NSLayoutConstraint.Attribute

    fileprivate init(item: NSView, attribute: NSLayoutConstraint.Attribute) {
        self.item = item
        self.attribute = attribute
        super.init()
    }

    public func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>, constant: CGFloat = 0) -> NSLayoutConstraint {
        NSLayoutConstraint(
            firstItem: item,
            firstAttribute: attribute,
            secondItem: anchor.item,
            secondAttribute: anchor.attribute,
            constant: constant
        )
    }
}

public final class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {}
public final class NSLayoutYAxisAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor> {}

public final class NSLayoutDimension: NSLayoutAnchor<NSLayoutDimension> {
    public func constraint(equalToConstant constant: CGFloat) -> NSLayoutConstraint {
        NSLayoutConstraint(
            firstItem: item,
            firstAttribute: attribute,
            secondItem: nil,
            secondAttribute: .other,
            constant: constant
        )
    }
}

public final class NSLayoutConstraint: NSObject {
    public enum Attribute: Hashable, Sendable {
        case leading
        case trailing
        case top
        case bottom
        case width
        case height
        case other
    }

    public weak var firstItem: AnyObject?
    public var firstAttribute: Attribute = .other
    public weak var secondItem: AnyObject?
    public var secondAttribute: Attribute = .other
    public var constant: CGFloat = 0
    public var isActive: Bool = false

    public override init() {
        super.init()
    }

    fileprivate init(
        firstItem: NSView?,
        firstAttribute: Attribute,
        secondItem: NSView?,
        secondAttribute: Attribute,
        constant: CGFloat
    ) {
        self.firstItem = firstItem
        self.firstAttribute = firstAttribute
        self.secondItem = secondItem
        self.secondAttribute = secondAttribute
        self.constant = constant
        super.init()
    }

    public static func activate(_ constraints: [NSLayoutConstraint]) {
        for constraint in constraints {
            constraint.isActive = true
            if let view = constraint.firstItem as? NSView,
               !view.constraints.contains(where: { $0 === constraint }) {
                view.constraints.append(constraint)
            }
            if let view = constraint.secondItem as? NSView {
                view.layoutSubtreeIfNeeded()
            } else if let view = constraint.firstItem as? NSView {
                view.superview?.layoutSubtreeIfNeeded()
            }
        }
    }
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
@MainActor
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
