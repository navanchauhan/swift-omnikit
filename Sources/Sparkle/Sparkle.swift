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
public final class SPUUpdater {
    public var canCheckForUpdates: Bool = false
    public var automaticallyChecksForUpdates: Bool = false

    public init() {}

    public func checkForUpdates() {}

    public func checkForUpdatesInBackground() {}
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
