import Foundation
import Security

/// API keys in the login Keychain: service `com.minutes.app`, one generic-password item per endpoint kind.
struct KeychainStore: Sendable {
    enum Account: String, Sendable {
        case transcription, summary
    }

    private let service = "com.minutes.app"

    func read(_ account: Account) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves the key, or deletes it when `value` is empty.
    func write(_ value: String, for account: Account) {
        SecItemDelete(baseQuery(account) as CFDictionary)
        guard !value.isEmpty else { return }
        var item = baseQuery(account)
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    private func baseQuery(_ account: Account) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account.rawValue]
    }
}
