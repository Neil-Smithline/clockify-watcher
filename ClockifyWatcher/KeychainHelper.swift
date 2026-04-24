import Foundation
import Security

enum KeychainHelper {
    static func save(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        delete(service: service, account: account)  // allow overwrite
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]
        _ = SecItemAdd(query as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    // App-level convenience
    static func saveApiKey(_ key: String) {
        save(key, service: "clockify-watcher", account: "api-key")
    }

    static func loadApiKey() -> String? {
        load(service: "clockify-watcher", account: "api-key")
    }

    static func deleteApiKey() {
        delete(service: "clockify-watcher", account: "api-key")
    }
}
