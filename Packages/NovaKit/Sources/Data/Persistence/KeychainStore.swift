import Foundation
import NovaCore
import Security

/// Secrets (session tokens) belong in the Keychain, never `UserDefaults` or files.
public protocol SecureStorage: Sendable {
    func read(_ key: String) -> Data?
    func write(_ data: Data, for key: String) throws
    func delete(_ key: String)
}

public struct KeychainStore: SecureStorage {
    private let service: String

    public init(service: String = "com.novashop.app") {
        self.service = service
    }

    public func read(_ key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    public func write(_ data: Data, for key: String) throws {
        delete(key)
        var query = baseQuery(key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            Log.persistence.error("Keychain write failed: \(status)")
            throw KeychainError(status: status)
        }
    }

    public func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// In-memory secure storage for tests / UI tests.
public final class EphemeralSecureStorage: SecureStorage, @unchecked Sendable {
    // Guarded by `lock`; `@unchecked` is justified because every access goes through `withLock`.
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init() {}

    public func read(_ key: String) -> Data? {
        lock.withLock { values[key] }
    }

    public func write(_ data: Data, for key: String) throws {
        lock.withLock { values[key] = data }
    }

    public func delete(_ key: String) {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}
