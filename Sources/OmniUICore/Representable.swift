import Foundation

#if canImport(AppKit) && !os(Linux)
import AppKit
#else
public final class NSToolbar: NSObject, @unchecked Sendable {
    public var showsBaselineSeparator: Bool = true

    public override init() {
        super.init()
    }
}

public protocol NSWindowDelegate: AnyObject {}

public extension NSWindowDelegate {
    var windowShouldClose: ((NSWindow) -> Bool)? { nil }
    var windowWillClose: ((Notification) -> Void)? { nil }
    var windowDidBecomeKey: ((Notification) -> Void)? { nil }
}

@MainActor
open class NSView: NSResponder {
    public struct AutoresizingMask: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let minXMargin = AutoresizingMask(rawValue: 1 << 0)
        public static let width = AutoresizingMask(rawValue: 1 << 1)
        public static let maxXMargin = AutoresizingMask(rawValue: 1 << 2)
        public static let minYMargin = AutoresizingMask(rawValue: 1 << 3)
        public static let height = AutoresizingMask(rawValue: 1 << 4)
        public static let maxYMargin = AutoresizingMask(rawValue: 1 << 5)
    }

    public static let noIntrinsicMetric: CGFloat = -1
    public static let boundsDidChangeNotification = Notification.Name("NSViewBoundsDidChangeNotification")

    public var frame: CGRect
    public var bounds: CGRect {
        get { CGRect(origin: .zero, size: frame.size) }
        set { frame.size = newValue.size }
    }
    public weak var superview: NSView?
    public private(set) var subviews: [NSView] = []
    public private(set) weak var window: NSWindow?
    public var wantsLayer: Bool = false
    public var layer: CALayer?
    public var needsDisplay: Bool = false
    public var needsLayout: Bool = false
    public var translatesAutoresizingMaskIntoConstraints: Bool = true
    public var autoresizingMask: AutoresizingMask = []
    public var constraints: [NSLayoutConstraint] = []
    public private(set) var registeredDraggedTypes: [NSPasteboard.PasteboardType] = []
    public private(set) var trackingAreas: [NSTrackingArea] = []
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
    open var acceptsFirstResponder: Bool { false }

    @MainActor open func addSubview(_ view: NSView) {
        if view.superview !== self {
            view.removeFromSuperview()
            view.viewWillMove(toSuperview: self)
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

    @MainActor open func removeFromSuperview() {
        guard let superview else { return }
        viewWillMove(toSuperview: nil)
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
    @MainActor open func viewDidMoveToSuperview() {}
    @MainActor open func viewWillMove(toSuperview newSuperview: NSView?) { _ = newSuperview }
    @MainActor open func viewDidMoveToWindow() {}
    open func viewEffectiveAppearanceDidChange() {}
    open func viewDidChangeBackingProperties() {}
    open func updateTrackingAreas() {}
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
    @MainActor open func mouseEntered(with event: NSEvent) { _ = event }
    @MainActor open func mouseExited(with event: NSEvent) { _ = event }
    @MainActor open func mouseMoved(with event: NSEvent) { _ = event }
    @MainActor open override func mouseDown(with event: NSEvent) { _ = event }
    @MainActor open func mouseUp(with event: NSEvent) { _ = event }
    @MainActor open func mouseDragged(with event: NSEvent) { _ = event }
    @MainActor open func rightMouseDown(with event: NSEvent) { _ = event }
    @MainActor open func rightMouseUp(with event: NSEvent) { _ = event }
    @MainActor open func otherMouseDown(with event: NSEvent) { _ = event }
    @MainActor open override func keyDown(with event: NSEvent) { _ = event }
    @MainActor open func doCommand(by selector: Selector) { _ = selector }
    @MainActor open func deleteBackward(_ sender: Any?) { _ = sender }
    @MainActor open func deleteForward(_ sender: Any?) { _ = sender }
    @MainActor open override func scrollWheel(with event: NSEvent) { _ = event }
    @MainActor open func viewWillMove(toWindow newWindow: NSWindow?) { _ = newWindow }
    open func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { _ = sender; return [] }
    open func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { _ = sender; return [] }
    open func draggingExited(_ sender: NSDraggingInfo?) { _ = sender }
    open func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { _ = sender; return true }
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
    @MainActor open func becomeFirstResponder() -> Bool { true }
    @MainActor open func resignFirstResponder() -> Bool { true }
    open func copy(_ sender: Any?) { _ = sender }
    open func paste(_ sender: Any?) { _ = sender }
    open func selectAll(_ sender: Any?) { _ = sender }
    open func registerForDraggedTypes(_ types: [NSPasteboard.PasteboardType]) {
        registeredDraggedTypes = types
    }
    open func unregisterDraggedTypes() {
        registeredDraggedTypes = []
    }
    open func addTrackingArea(_ trackingArea: NSTrackingArea) {
        trackingAreas.append(trackingArea)
    }
    open func removeTrackingArea(_ trackingArea: NSTrackingArea) {
        trackingAreas.removeAll { $0 === trackingArea }
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

    @MainActor fileprivate func _setWindowRecursively(_ newWindow: NSWindow?) {
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

@MainActor
open class _OmniNSWindow: NSObject, @unchecked Sendable {
    public typealias SendEventInterceptor = @Sendable (NSWindow, NSEvent) -> Bool

    public enum BackingStoreType: Hashable, Sendable {
        case buffered
        case retained
        case nonretained
    }

    public struct Level: Hashable, Sendable, RawRepresentable, Comparable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let normal = Level(rawValue: 0)
        public static let floating = Level(rawValue: 3)
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum OrderingMode: Hashable, Sendable {
        case above
        case below
        case out
    }

    public enum ButtonType: Hashable, Sendable {
        case closeButton
        case miniaturizeButton
        case zoomButton
    }

    public enum TabbingMode: Hashable, Sendable {
        case automatic
        case preferred
        case disallowed
    }

    public struct CollectionBehavior: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let fullScreenNone = CollectionBehavior(rawValue: 1 << 0)
    }

    public enum AnimationBehavior: Hashable, Sendable {
        case `default`
        case none
        case documentWindow
    }

    public static let didResignKeyNotification = Notification.Name("NSWindowDidResignKeyNotification")
    public static let didResignMainNotification = Notification.Name("NSWindowDidResignMainNotification")
    public static let didBecomeKeyNotification = Notification.Name("NSWindowDidBecomeKeyNotification")
    public static let didBecomeMainNotification = Notification.Name("NSWindowDidBecomeMainNotification")
    public static let didResizeNotification = Notification.Name("NSWindowDidResizeNotification")
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
    public var contentViewController: NSViewController? {
        didSet {
            contentView = contentViewController?.view
        }
    }
    public weak var firstResponder: NSView?
    public weak var delegate: NSWindowDelegate?
    public var toolbar: NSToolbar?
    public weak var sheetParent: NSWindow?
    public var title: String = ""
    public var titlebarAppearsTransparent: Bool = false
    public var acceptsMouseMovedEvents: Bool = false
    public var isOpaque: Bool = true
    public var hasShadow: Bool = false
    public var ignoresMouseEvents: Bool = false
    public var alphaValue: CGFloat = 1
    public var level: Level = .normal
    public var frame: NSRect = .zero
    public var currentEvent: NSEvent?
    public private(set) var childWindows: [NSWindow]? = []
    public private(set) var titlebarAccessoryViewControllers: [NSTitlebarAccessoryViewController] = []
    public var isReleasedWhenClosed: Bool = true
    public var tabbingMode: TabbingMode = .automatic
    public var collectionBehavior: CollectionBehavior = []
    public var animationBehavior: AnimationBehavior = .default
    public var contentMinSize: NSSize = .zero
    public var isKeyWindow: Bool {
        guard let window = self as? NSWindow else { return false }
        return NSApp.keyWindow === window
    }
    public var isMainWindow: Bool { isKeyWindow }
    public var contentLayoutRect: NSRect {
        guard let contentView else { return .zero }
        return NSRect(origin: .zero, size: contentView.frame.size)
    }
    public var screen: NSScreen? = .main
    public var backingScaleFactor: CGFloat { screen?.backingScaleFactor ?? 1 }
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

    public init(
        contentRect: NSRect,
        styleMask: NSWindowStyleMask,
        backing: BackingStoreType,
        defer flag: Bool
    ) {
        self.frame = contentRect
        self.styleMask = styleMask
        _ = backing
        _ = flag
        super.init()
        if let window = self as? NSWindow, !NSApp.windows.contains(where: { $0 === window }) {
            NSApp.windows.append(window)
        }
    }

    public convenience init(contentViewController: NSViewController) {
        self.init()
        self.contentViewController = contentViewController
        self.contentView = contentViewController.view
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
    open func orderOut(_ sender: Any?) {
        _ = sender
        guard let window = self as? NSWindow else { return }
        if NSApp.keyWindow === window {
            NSApp.keyWindow = nil
        }
    }

    open func orderFront(_ sender: Any?) {
        _ = sender
        makeKey()
    }
    open func performClose(_ sender: Any?) {
        _ = sender
        guard let window = self as? NSWindow else { return }
        guard delegate?.windowShouldClose?(window) ?? true else { return }
        let notification = Notification(name: Self.willCloseNotification, object: window)
        NotificationCenter.default.post(notification)
        delegate?.windowWillClose?(notification)
        NSApp.windows.removeAll { $0 === window }
        if NSApp.keyWindow === window {
            NSApp.keyWindow = nil
        }
    }

    open func endSheet(_ sheetWindow: NSWindow, returnCode: NSApplication.ModalResponse = .cancel) {
        _ = returnCode
        if sheetWindow.sheetParent === self {
            sheetWindow.sheetParent = nil
        }
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
        currentEvent = event
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
    @MainActor open func makeFirstResponder(_ responder: NSView?) -> Bool {
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

    open func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) {
        guard !titlebarAccessoryViewControllers.contains(where: { $0 === childViewController }) else { return }
        titlebarAccessoryViewControllers.append(childViewController)
    }

    open func removeTitlebarAccessoryViewController(at index: Int) {
        guard titlebarAccessoryViewControllers.indices.contains(index) else { return }
        titlebarAccessoryViewControllers.remove(at: index)
    }

    open func addChildWindow(_ childWindow: NSWindow, ordered orderingMode: OrderingMode) {
        _ = orderingMode
        if childWindows == nil {
            childWindows = []
        }
        guard childWindows?.contains(where: { $0 === childWindow }) != true else { return }
        childWindows?.append(childWindow)
        childWindow.parent = self as? NSWindow
    }

    open func removeChildWindow(_ childWindow: NSWindow) {
        childWindows?.removeAll { $0 === childWindow }
        if childWindow.parent === self {
            childWindow.parent = nil
        }
    }

    open func setFrame(_ frameRect: NSRect, display flag: Bool) {
        _ = flag
        frame = frameRect
        contentView?.frame = NSRect(origin: .zero, size: frameRect.size)
        NotificationCenter.default.post(name: Self.didResizeNotification, object: self)
    }

    open func setFrameOrigin(_ point: NSPoint) {
        frame.origin = point
    }

    open func setFrameTopLeftPoint(_ point: NSPoint) {
        frame.origin = NSPoint(x: point.x, y: point.y - frame.height)
    }

    open func setContentSize(_ size: NSSize) {
        var newFrame = frame
        newFrame.size = size
        setFrame(newFrame, display: true)
    }

    @discardableResult
    open func setFrameAutosaveName(_ name: String) -> Bool {
        _ = name
        return true
    }

    open func center() {
        guard let screenFrame = screen?.frame else { return }
        frame.origin = NSPoint(
            x: screenFrame.midX - frame.width / 2,
            y: screenFrame.midY - frame.height / 2
        )
    }

    open func convertToScreen(_ rect: NSRect) -> NSRect {
        NSRect(
            x: frame.origin.x + rect.origin.x,
            y: frame.origin.y + rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    open var isVisible: Bool {
        NSApp.windows.contains { $0 === self }
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

open class CALayer: NSObject {
    public var backgroundColor: CGColor?
    public var borderColor: CGColor?
    public var borderWidth: CGFloat = 0
    public var cornerRadius: CGFloat = 0
    public var masksToBounds: Bool = false
    public var frame: CGRect = .zero
    public var bounds: CGRect {
        get { CGRect(origin: .zero, size: frame.size) }
        set { frame.size = newValue.size }
    }
    public var actions: [String: Any]?
    public private(set) weak var superlayer: CALayer?
    public private(set) var sublayers: [CALayer] = []
    private var animations: [String: Any] = [:]

    public func addSublayer(_ layer: CALayer) {
        if layer.superlayer === self { return }
        layer.removeFromSuperlayer()
        sublayers.append(layer)
        layer.superlayer = self
    }

    public func removeFromSuperlayer() {
        guard let superlayer else { return }
        superlayer.sublayers.removeAll { $0 === self }
        self.superlayer = nil
    }

    public func add(_ animation: Any, forKey key: String?) {
        animations[key ?? UUID().uuidString] = animation
    }

    public func animation(forKey key: String) -> Any? {
        animations[key]
    }

    public func removeAnimation(forKey key: String) {
        animations.removeValue(forKey: key)
    }
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

    @MainActor
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

    @MainActor func makeNSView(context: NSViewRepresentableContext<Self>) -> NSViewType
    @MainActor func updateNSView(_ nsView: NSViewType, context: NSViewRepresentableContext<Self>)
    @MainActor static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator)
    @MainActor func makeCoordinator() -> Coordinator
}

public extension NSViewRepresentable {
    typealias Context = NSViewRepresentableContext<Self>

    @MainActor static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator) {
        _ = nsView
        _ = coordinator
    }
}

public extension NSViewRepresentable where Coordinator == Void {
    @MainActor func makeCoordinator() -> Void {}
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
