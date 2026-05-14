import Foundation

public typealias CFString = String
public typealias CFDictionary = [String: Any]
public typealias OSStatus = Int32

public let errSecSuccess: OSStatus = 0
public let errSecItemNotFound: OSStatus = -25300

public let kSecClass: CFString = "class"
public let kSecClassGenericPassword: CFString = "genp"
public let kSecAttrService: CFString = "svce"
public let kSecAttrAccount: CFString = "acct"
public let kSecValueData: CFString = "v_Data"
public let kSecReturnData: CFString = "r_Data"
public let kSecMatchLimit: CFString = "m_Limit"
public let kSecMatchLimitOne: CFString = "m_LimitOne"

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
