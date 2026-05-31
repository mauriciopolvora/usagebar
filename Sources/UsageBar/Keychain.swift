import Foundation
import Security

enum Keychain {
    static let cursorService = "UsageBar-CursorSessionToken"
    static let cursorAccount = "default"
    static let claudeService = "Claude Code-credentials"

    /// Reads a generic password using the standard Keychain flow. In production, a stable
    /// code signature lets "Always Allow" stick across launches.
    static func genericPassword(service: String, account: String? = nil) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keychain access can trigger a macOS authorization prompt. Cache each secret for the
    /// process lifetime so periodic refreshes do not repeatedly ask for the same item.
    static func cachedGenericPassword(service: String, account: String? = nil) -> String? {
        let key = CacheKey(service: service, account: account)
        cacheLock.lock()
        if let cached = passwordCache[key] {
            cacheLock.unlock()
            return cached.value
        }
        cacheLock.unlock()

        let value = genericPassword(service: service, account: account)
        cacheLock.lock()
        passwordCache[key] = value.map(CachedPassword.value) ?? .missing
        cacheLock.unlock()
        return value
    }

    @discardableResult
    static func setGenericPassword(_ value: String, service: String, account: String? = nil) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(service: service, account: account)
        let update = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            cache(value, service: service, account: account)
            return true
        }
        guard status == errSecItemNotFound else { return false }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let added = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        if added {
            cache(value, service: service, account: account)
        }
        return added
    }

    @discardableResult
    static func deleteGenericPassword(service: String, account: String? = nil) -> Bool {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        let deleted = status == errSecSuccess || status == errSecItemNotFound
        if deleted {
            cache(nil, service: service, account: account)
        }
        return deleted
    }

    private static func baseQuery(service: String, account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }
        return query
    }

    private static func cache(_ value: String?, service: String, account: String?) {
        cacheLock.lock()
        passwordCache[CacheKey(service: service, account: account)] = value.map(CachedPassword.value) ?? .missing
        cacheLock.unlock()
    }

    private struct CacheKey: Hashable {
        let service: String
        let account: String?
    }

    private enum CachedPassword {
        case missing
        case value(String)

        var value: String? {
            switch self {
            case .missing: return nil
            case .value(let value): return value
            }
        }
    }

    private static let cacheLock = NSLock()
    private static var passwordCache: [CacheKey: CachedPassword] = [:]
}
