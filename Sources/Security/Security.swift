import Foundation

public typealias CFString = String
public typealias CFDictionary = [String: Any]
public typealias OSStatus = Int32

public let errSecSuccess: OSStatus = 0
public let errSecItemNotFound: OSStatus = -25300
public let errSecDuplicateItem: OSStatus = -25299
public let errSecInteractionNotAllowed: OSStatus = -25308
public let errSecUserCanceled: OSStatus = -128
public let errSecAuthFailed: OSStatus = -25293
public let errSecUnimplemented: OSStatus = -4

public let kSecClass: CFString = "class"
public let kSecClassGenericPassword: CFString = "genp"
public let kSecAttrService: CFString = "svce"
public let kSecAttrAccount: CFString = "acct"
public let kSecAttrAccessible: CFString = "accessible"
public let kSecAttrAccessibleAfterFirstUnlock: CFString = "ak"
public let kSecAttrSynchronizable: CFString = "sync"
public let kSecValueData: CFString = "v_Data"
public let kSecReturnData: CFString = "r_Data"
public let kSecMatchLimit: CFString = "m_Limit"
public let kSecMatchLimitOne: CFString = "m_LimitOne"
public let kSecUseAuthenticationUI: CFString = "u_AuthUI"
public let kSecUseAuthenticationUISkip: CFString = "u_AuthUISkip"
public let kSecCSSigningInformation: UInt32 = 1
public let kSecCodeInfoIdentifier: CFString = "identifier"
public let kSecCodeInfoTeamIdentifier: CFString = "teamIdentifier"

public struct SecCSFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
}

public final class SecCode: @unchecked Sendable {}
public final class SecStaticCode: @unchecked Sendable {}

private final class SecurityStore: @unchecked Sendable {
    static let shared = SecurityStore()
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func key(for query: [String: Any]) -> String? {
        guard let service = query[kSecAttrService as String] as? String,
              let account = query[kSecAttrAccount as String] as? String else { return nil }
        return service + "\u{1f}" + account
    }

    func set(_ data: Data, for key: String) {
        lock.lock()
        values[key] = data
        lock.unlock()
    }

    func value(for key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func delete(_ key: String) {
        lock.lock()
        values.removeValue(forKey: key)
        lock.unlock()
    }
}

@discardableResult
public func SecItemAdd(_ query: CFDictionary, _ result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
    guard let key = SecurityStore.shared.key(for: query),
          let data = query[kSecValueData] as? Data else { return errSecItemNotFound }
    SecurityStore.shared.set(data, for: key)
    result?.pointee = nil
    return errSecSuccess
}

@discardableResult
public func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
    guard let key = SecurityStore.shared.key(for: query),
          let data = SecurityStore.shared.value(for: key) else { return errSecItemNotFound }
    result?.pointee = data as NSData
    return errSecSuccess
}

@discardableResult
public func SecItemDelete(_ query: CFDictionary) -> OSStatus {
    guard let key = SecurityStore.shared.key(for: query) else { return errSecItemNotFound }
    SecurityStore.shared.delete(key)
    return errSecSuccess
}

@discardableResult
public func SecItemUpdate(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus {
    guard let key = SecurityStore.shared.key(for: query) else { return errSecItemNotFound }
    guard SecurityStore.shared.value(for: key) != nil else { return errSecItemNotFound }
    guard let data = attributes[kSecValueData] as? Data else { return errSecItemNotFound }
    SecurityStore.shared.set(data, for: key)
    return errSecSuccess
}

@discardableResult
public func SecCodeCopySelf(_ flags: SecCSFlags, _ code: UnsafeMutablePointer<SecCode?>?) -> OSStatus {
    _ = flags
    code?.pointee = nil
    return errSecUnimplemented
}

@discardableResult
public func SecCodeCopyStaticCode(_ code: SecCode, _ flags: SecCSFlags, _ staticCode: UnsafeMutablePointer<SecStaticCode?>?) -> OSStatus {
    _ = code
    _ = flags
    staticCode?.pointee = nil
    return errSecUnimplemented
}

@discardableResult
public func SecCodeCopySigningInformation(_ code: SecStaticCode, _ flags: SecCSFlags, _ information: UnsafeMutablePointer<CFDictionary?>?) -> OSStatus {
    _ = code
    _ = flags
    information?.pointee = nil
    return errSecUnimplemented
}

public func SecCopyErrorMessageString(_ status: OSStatus, _ reserved: UnsafeMutableRawPointer?) -> CFString? {
    _ = reserved
    return switch status {
    case errSecSuccess: "success"
    case errSecItemNotFound: "item not found"
    case errSecDuplicateItem: "duplicate item"
    case errSecInteractionNotAllowed: "interaction not allowed"
    case errSecUserCanceled: "user canceled"
    case errSecAuthFailed: "authentication failed"
    case errSecUnimplemented: "security API unavailable"
    default: nil
    }
}
