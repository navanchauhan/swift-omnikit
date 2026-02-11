import Foundation

// Minimal TelemetryDeck shim for non-Apple builds.
//
// iGopherBrowser uses this for analytics, but OmniKit's TUI builds don't need real telemetry.

public enum TelemetryDeck {
    public final class Config: @unchecked Sendable {
        public let appID: String
        public var analyticsDisabled: Bool = false

        public init(appID: String) {
            self.appID = appID
        }
    }

    public static func initialize(config: Config) {
        _ = config
    }

    public static func terminate() {
        // no-op
    }

    public static func signal(_ name: String, parameters: [String: String] = [:]) {
        _ = name
        _ = parameters
    }
}
