@_exported import Foundation

public typealias CFIndex = Int
public typealias CFTimeInterval = TimeInterval
public typealias CFAbsoluteTime = TimeInterval
public typealias CFTypeID = UInt
public typealias CFTypeRef = AnyObject
public typealias CFString = String
public typealias CFStringEncoding = UInt32
public typealias CFURL = URL
public typealias CFDictionary = [String: Any]
public typealias CFArray = NSArray
public typealias UniChar = UInt16

public struct CFAllocator: Hashable, Sendable {
    public init() {}
}

public let kCFAllocatorDefault: CFAllocator? = CFAllocator()

public struct CFRange: Hashable, Sendable {
    public var location: CFIndex
    public var length: CFIndex

    public init(location: CFIndex, length: CFIndex) {
        self.location = location
        self.length = length
    }
}

public enum CFStringBuiltInEncodings: CFStringEncoding, Sendable {
    case UTF8 = 0x0800_0100
}

public enum CFStringEncodings: CFStringEncoding, Sendable {
    case GB_18030_2000 = 0x0632
    case big5 = 0x0A03
}

public func CFAbsoluteTimeGetCurrent() -> CFAbsoluteTime {
    Date().timeIntervalSinceReferenceDate
}

public func CFGetTypeID(_ value: Any) -> CFTypeID {
    if let number = value as? NSNumber {
        return String(cString: number.objCType) == "c" ? CFBooleanGetTypeID() : 2
    }
    if value is String || value is NSString {
        return CFStringGetTypeID()
    }
    return 0
}

public func CFBooleanGetTypeID() -> CFTypeID { 1 }
public func CFStringGetTypeID() -> CFTypeID { 3 }

public func CFStringGetLength(_ source: CFString) -> CFIndex {
    source.utf16.count
}

public func CFStringGetCStringPtr(_ source: CFString, _ encoding: CFStringEncoding) -> UnsafePointer<CChar>? {
    _ = source
    _ = encoding
    return nil
}

public func CFStringGetMaximumSizeForEncoding(_ length: CFIndex, _ encoding: CFStringEncoding) -> CFIndex {
    _ = encoding
    return max(0, length) * 4
}

public func CFStringGetCString(
    _ source: CFString,
    _ buffer: UnsafeMutablePointer<CChar>?,
    _ bufferSize: CFIndex,
    _ encoding: CFStringEncoding
) -> Bool {
    _ = encoding
    guard let buffer, bufferSize > 0 else { return false }
    let bytes = Array(source.utf8)
    let limit = min(bytes.count, bufferSize - 1)
    for index in 0..<limit {
        buffer[index] = CChar(bitPattern: bytes[index])
    }
    buffer[limit] = 0
    return bytes.count < bufferSize
}

public func CFStringGetCharacters(_ source: CFString, _ range: CFRange, _ buffer: UnsafeMutablePointer<UniChar>?) {
    guard let buffer else { return }
    let units = Array(source.utf16)
    let start = max(0, min(range.location, units.count))
    let end = max(start, min(start + range.length, units.count))
    for (offset, unit) in units[start..<end].enumerated() {
        buffer[offset] = unit
    }
}

public func CFStringConvertIANACharSetNameToEncoding(_ name: CFString) -> CFStringEncoding {
    switch name.lowercased().replacingOccurrences(of: "_", with: "-") {
    case "utf-8", "utf8":
        CFStringBuiltInEncodings.UTF8.rawValue
    case "gb18030", "gb-18030":
        CFStringEncodings.GB_18030_2000.rawValue
    case "big5", "big-5":
        CFStringEncodings.big5.rawValue
    default:
        CFStringBuiltInEncodings.UTF8.rawValue
    }
}

public func CFStringConvertEncodingToNSStringEncoding(_ encoding: CFStringEncoding) -> UInt {
    switch encoding {
    case CFStringBuiltInEncodings.UTF8.rawValue:
        return String.Encoding.utf8.rawValue
    default:
        return UInt(encoding)
    }
}

public func CFArrayGetCount(_ array: CFArray) -> CFIndex {
    array.count
}

public func CFArrayGetValueAtIndex(_ array: CFArray, _ index: CFIndex) -> UnsafeRawPointer? {
    guard index >= 0, index < array.count else { return nil }
    let object = array.object(at: index) as AnyObject
    return UnsafeRawPointer(Unmanaged.passUnretained(object).toOpaque())
}

public struct CFNotificationName: RawRepresentable, Hashable, Sendable {
    public var rawValue: CFString

    public init(_ rawValue: CFString) {
        self.rawValue = rawValue
    }

    public init(rawValue: CFString) {
        self.rawValue = rawValue
    }
}

public final class CFNotificationCenter: @unchecked Sendable {}

public struct CFNotificationSuspensionBehavior: Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let deliverImmediately = CFNotificationSuspensionBehavior(rawValue: 1)
}

public typealias CFNotificationCallback = (
    CFNotificationCenter?,
    UnsafeMutableRawPointer?,
    CFNotificationName?,
    UnsafeRawPointer?,
    CFDictionary?
) -> Void

private let _omniDarwinNotificationCenter = CFNotificationCenter()

public func CFNotificationCenterGetDarwinNotifyCenter() -> CFNotificationCenter {
    _omniDarwinNotificationCenter
}

public func CFNotificationCenterAddObserver(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeRawPointer?,
    _ callBack: CFNotificationCallback?,
    _ name: CFString?,
    _ object: UnsafeRawPointer?,
    _ suspensionBehavior: CFNotificationSuspensionBehavior
) {
    _ = center
    _ = observer
    _ = callBack
    _ = name
    _ = object
    _ = suspensionBehavior
}

public func CFNotificationCenterPostNotification(
    _ center: CFNotificationCenter?,
    _ name: CFNotificationName,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?,
    _ deliverImmediately: Bool
) {
    _ = center
    _ = name
    _ = object
    _ = userInfo
    _ = deliverImmediately
}
