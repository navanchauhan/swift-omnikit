@_exported import Dispatch
@_exported import Foundation

public final class SPUUpdater: NSObject {
    @objc public dynamic var canCheckForUpdates: Bool = false
    @objc public dynamic var automaticallyChecksForUpdates: Bool = false

    @objc public func checkForUpdates() {}

    @objc public func checkForUpdatesInBackground() {}
}

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
