import Foundation
import Security

enum KeychainService {
    private static let service = "com.raltemeyer.OpenClawApp"
    private static let legacyAccount = "gatewayToken"

    static func saveToken(_ token: String) {
        saveToken(token, for: "default")
    }

    static func loadToken() -> String? {
        loadToken(for: "default")
    }

    static func saveToken(_ token: String, for profileId: String) {
        let data = Data(token.utf8)
        let account = accountName(for: profileId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            attributes.forEach { addQuery[$0.key] = $0.value }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func loadToken(for profileId: String) -> String? {
        let account = accountName(for: profileId)
        if let token = loadTokenRaw(account: account) {
            return token
        }

        // Backward compatibility: if default profile does not yet have a scoped token,
        // fall back to legacy single-account storage.
        if profileId == "default" {
            return loadTokenRaw(account: legacyAccount)
        }
        return nil
    }

    private static func accountName(for profileId: String) -> String {
        "gatewayToken.\(profileId)"
    }

    private static func loadTokenRaw(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
