import Foundation

public struct OSLog: Hashable, Sendable {
    public var subsystem: String
    public var category: String

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    public static let `default` = OSLog(subsystem: "default", category: "default")
}

public struct OSLogPrivacy: Hashable, Sendable {
    public enum Level: Hashable, Sendable {
        case `public`
        case `private`
        case sensitive
        case auto
    }

    public var level: Level

    public init(_ level: Level = .auto) {
        self.level = level
    }

    public static let `public` = OSLogPrivacy(.public)
    public static let `private` = OSLogPrivacy(.private)
    public static let sensitive = OSLogPrivacy(.sensitive)
    public static let auto = OSLogPrivacy(.auto)
}

public struct OSLogMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable, CustomStringConvertible {
    public var description: String

    public init(stringLiteral value: String) {
        self.description = value
    }

    public init(stringInterpolation: StringInterpolation) {
        self.description = stringInterpolation.output
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var output: String

        public init(literalCapacity: Int, interpolationCount: Int) {
            self.output = ""
            self.output.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: String) {
            output += literal
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            output += String(describing: value)
        }

        public mutating func appendInterpolation<T>(_ value: T, privacy: OSLogPrivacy) {
            _ = privacy
            output += String(describing: value)
        }
    }
}

public struct Logger: Sendable {
    public var subsystem: String
    public var category: String

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    public func trace(_ message: @autoclosure () -> OSLogMessage) {
        write("trace", message())
    }

    public func debug(_ message: @autoclosure () -> OSLogMessage) {
        write("debug", message())
    }

    public func info(_ message: @autoclosure () -> OSLogMessage) {
        write("info", message())
    }

    public func notice(_ message: @autoclosure () -> OSLogMessage) {
        write("notice", message())
    }

    public func warning(_ message: @autoclosure () -> OSLogMessage) {
        write("warning", message())
    }

    public func error(_ message: @autoclosure () -> OSLogMessage) {
        write("error", message())
    }

    public func fault(_ message: @autoclosure () -> OSLogMessage) {
        write("fault", message())
    }

    public func critical(_ message: @autoclosure () -> OSLogMessage) {
        write("critical", message())
    }

    private func write(_ level: String, _ message: OSLogMessage) {
        #if DEBUG
        print("[\(subsystem):\(category)] \(level): \(message.description)")
        #else
        _ = level
        _ = message
        #endif
    }
}

public struct OSSignpostID: Hashable, Sendable {
    public var rawValue: UInt64

    public init(_ rawValue: UInt64 = 0) {
        self.rawValue = rawValue
    }

    public init(log: OSLog) {
        self.rawValue = UInt64(abs(log.hashValue))
    }
}

public enum OSSignpostType: Sendable {
    case begin
    case end
    case event
}

public struct OSSignpostIntervalState: Hashable, Sendable {
    public var id: OSSignpostID
    public var name: String

    public init(id: OSSignpostID = OSSignpostID(), name: String = "") {
        self.id = id
        self.name = name
    }
}

public struct OSSignposter: Sendable {
    public var log: OSLog

    public init(subsystem: String, category: String) {
        self.log = OSLog(subsystem: subsystem, category: category)
    }

    public init(log: OSLog = .default) {
        self.log = log
    }

    public func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        OSSignpostIntervalState(id: OSSignpostID(log: log), name: String(describing: name))
    }

    public func beginInterval(_ name: StaticString, id: OSSignpostID = OSSignpostID()) -> OSSignpostIntervalState {
        OSSignpostIntervalState(id: id, name: String(describing: name))
    }

    public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        _ = name
        _ = state
    }

    public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState, _ message: OSLogMessage) {
        _ = name
        _ = state
        _ = message
    }

    public func emitEvent(_ name: StaticString) {
        _ = name
    }

    public func emitEvent(_ name: StaticString, _ message: OSLogMessage) {
        _ = name
        _ = message
    }
}

public func os_signpost(_ type: OSSignpostType, log: OSLog, name: StaticString, signpostID: OSSignpostID) {
    _ = type
    _ = log
    _ = name
    _ = signpostID
}
