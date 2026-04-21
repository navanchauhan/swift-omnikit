import Foundation

public struct TerminalSize: Sendable, Codable, Equatable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

public enum InteractiveSessionEvent: Sendable {
    case output(Data)
    case exit(Int32)
}

public protocol InteractiveExecutionSession: AnyObject, Sendable {
    func setEventHandler(_ handler: (@Sendable (InteractiveSessionEvent) -> Void)?) async
    func write(_ data: Data) async throws
    func resize(_ size: TerminalSize) async throws
    func terminate() async
    func isRunning() async -> Bool
}

public struct InteractiveSessionUnsupportedError: LocalizedError, Sendable {
    public init() {}

    public var errorDescription: String? {
        "Interactive execution sessions are unavailable in this environment."
    }
}
