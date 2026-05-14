@_exported import Dispatch
@_exported import Foundation

#if canImport(ObjectiveC)
public final class SPUUpdater: NSObject {
    @objc public dynamic var canCheckForUpdates: Bool = false
    @objc public dynamic var automaticallyChecksForUpdates: Bool = false

    @objc public func checkForUpdates() {}

    @objc public func checkForUpdatesInBackground() {}
}
#else
public final class NSKeyValueObservation {
    private let onInvalidate: () -> Void
    private var isInvalidated = false

    init(_ onInvalidate: @escaping () -> Void = {}) {
        self.onInvalidate = onInvalidate
    }

    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        onInvalidate()
    }
}

public struct NSKeyValueObservingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let initial = NSKeyValueObservingOptions(rawValue: 1 << 0)
    public static let new = NSKeyValueObservingOptions(rawValue: 1 << 1)
}

public struct NSKeyValueObservedChange<Value> {
    public let newValue: Value?
}

public final class SPUUpdater {
    public var canCheckForUpdates: Bool = false
    public var automaticallyChecksForUpdates: Bool = false

    public init() {}

    public func checkForUpdates() {}

    public func checkForUpdatesInBackground() {}

    public func observe<Value>(
        _ keyPath: KeyPath<SPUUpdater, Value>,
        options: NSKeyValueObservingOptions = [],
        changeHandler: @escaping (SPUUpdater, NSKeyValueObservedChange<Value>) -> Void
    ) -> NSKeyValueObservation {
        if options.contains(.initial) {
            changeHandler(self, NSKeyValueObservedChange(newValue: self[keyPath: keyPath]))
        }
        return NSKeyValueObservation()
    }
}
#endif

public final class SPUStandardUpdaterController {
    public let updater: SPUUpdater

    public init(
        startingUpdater: Bool,
        updaterDelegate: AnyObject?,
        userDriverDelegate: AnyObject?
    ) {
        self.updater = SPUUpdater()
    }
}
