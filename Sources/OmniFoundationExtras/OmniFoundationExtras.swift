import Foundation

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
