import Foundation
import LocalAuthentication
import Security

enum KeychainStore {
    private static let service = "com.solarflow.monitor"
    private static let secretsAccount = "application-secrets"
    private static let passwordAccount = "zendure-history-password"
    private static let shellyAccount = "shelly-cloud-auth-key"

    struct Secrets: Codable, Equatable {
        var cloudKey = ""
        var zendurePassword = ""
        var shellyAuthKey = ""
    }

    /// Loads every secret with a single Keychain lookup. Older separate entries
    /// are imported once and then removed after the consolidated item is saved.
    static func loadSecrets(legacyCloudKey: String = "") -> Secrets? {
        let consolidated = loadData(account: secretsAccount)
        if let data = consolidated.data,
           let secrets = try? JSONDecoder().decode(Secrets.self, from: data) {
            return secrets
        }
        // Cancellation or a failed authentication must never be interpreted as
        // an empty Keychain item, otherwise a later save could erase secrets.
        guard consolidated.status == errSecItemNotFound else { return nil }
        let migrated = Secrets(
            cloudKey: legacyCloudKey,
            zendurePassword: load(account: passwordAccount),
            shellyAuthKey: load(account: shellyAccount)
        )
        if migrated != Secrets() {
            saveSecrets(migrated)
            delete(account: passwordAccount)
            delete(account: shellyAccount)
        }
        return migrated
    }

    static func saveSecrets(_ secrets: Secrets, protectWithUserPresence: Bool = false, recreateAccessControl: Bool = false) {
        guard let data = try? JSONEncoder().encode(secrets) else { return }
        if recreateAccessControl { delete(account: secretsAccount) }
        save(data, account: secretsAccount, protectWithUserPresence: protectWithUserPresence)
    }

    private static func loadData(account: String) -> (data: Data?, status: OSStatus) {
        let context = LAContext()
        context.localizedReason = "Déverrouiller les identifiants de SolarFlow Monitor"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return (nil, status) }
        return (data, status)
    }

    private static func load(account: String) -> String {
        guard let data = loadData(account: account).data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func save(_ data: Data, account: String, protectWithUserPresence: Bool = false) {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = key
            add[kSecValueData as String] = data
            if protectWithUserPresence {
                var error: Unmanaged<CFError>?
                if let access = SecAccessControlCreateWithFlags(
                    nil,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    .userPresence,
                    &error
                ) {
                    add[kSecAttrAccessControl as String] = access
                }
            } else {
                add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
