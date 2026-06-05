import Foundation

@discardableResult
public func autoreleasepool<Result>(invoking work: () throws -> Result) rethrows -> Result {
    try work()
}

public extension Data.WritingOptions {
    static let atomicWrite: Data.WritingOptions = .atomic
}

public final class RelativeDateTimeFormatter {
    public enum UnitsStyle: Sendable {
        case abbreviated
        case full
        case spellOut
        case short
    }

    public var unitsStyle: UnitsStyle = .full

    public init() {}

    public func localizedString(for date: Date, relativeTo referenceDate: Date) -> String {
        let seconds = Int(date.timeIntervalSince(referenceDate).rounded())
        let magnitude = abs(seconds)
        let future = seconds > 0
        let units: [(name: String, short: String, value: Int)] = [
            ("year", "y", 31_536_000),
            ("month", "mo", 2_592_000),
            ("week", "w", 604_800),
            ("day", "d", 86_400),
            ("hour", "h", 3_600),
            ("minute", "m", 60),
            ("second", "s", 1),
        ]
        let unit = units.first { magnitude >= $0.value } ?? units[units.count - 1]
        let count = max(1, magnitude / unit.value)

        switch unitsStyle {
        case .abbreviated, .short:
            return future ? "in \(count)\(unit.short)" : "\(count)\(unit.short) ago"
        case .full, .spellOut:
            let label = count == 1 ? unit.name : "\(unit.name)s"
            return future ? "in \(count) \(label)" : "\(count) \(label) ago"
        }
    }
}

public extension FileManager {
    func trashItem(at url: URL, resultingItemURL outResultingURL: UnsafeMutablePointer<URL?>?) throws {
        let trashRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local/share/Trash/files", isDirectory: true)
        try createDirectory(at: trashRoot, withIntermediateDirectories: true)

        var destination = trashRoot.appendingPathComponent(url.lastPathComponent)
        if fileExists(atPath: destination.path) {
            let stem = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            let suffix = UUID().uuidString
            destination = trashRoot.appendingPathComponent(ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)")
        }

        try moveItem(at: url, to: destination)
        outResultingURL?.pointee = destination
    }
}

public extension NSString {
    class func stringEncoding(
        for data: Data,
        encodingOptions opts: [AnyHashable: Any] = [:],
        convertedString string: UnsafeMutablePointer<NSString?>?,
        usedLossyConversion lossy: UnsafeMutablePointer<ObjCBool>?
    ) -> UInt {
        _ = opts
        if let decoded = String(data: data, encoding: .utf8) {
            string?.pointee = decoded as NSString
            lossy?.pointee = false
            return String.Encoding.utf8.rawValue
        }
        if let decoded = String(data: data, encoding: .isoLatin1) {
            string?.pointee = decoded as NSString
            lossy?.pointee = true
            return String.Encoding.isoLatin1.rawValue
        }
        string?.pointee = nil
        lossy?.pointee = true
        return 0
    }
}

private final class _OmniProcessActivityToken: NSObject {}

public extension ProcessInfo {
    struct ActivityOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let idleSystemSleepDisabled = ActivityOptions(rawValue: 1 << 0)
        public static let userInitiated = ActivityOptions(rawValue: 1 << 1)
        public static let latencyCritical = ActivityOptions(rawValue: 1 << 2)
    }

    func beginActivity(options: ActivityOptions, reason: String) -> NSObjectProtocol {
        _ = options
        _ = reason
        return _OmniProcessActivityToken()
    }

    func endActivity(_ activity: NSObjectProtocol) {
        _ = activity
    }
}
