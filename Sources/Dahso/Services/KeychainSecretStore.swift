import Foundation
import Security

enum AppSecretKey: String, CaseIterable {
    case anthropicApiKey = "anthropic-api-key"
    case googleAccessToken = "google-access-token"
    case googleRefreshToken = "google-refresh-token"
}

protocol SecretStoring {
    /// Read a secret. When `accountID` is non-nil the key is namespaced by that account,
    /// allowing multiple concurrent Google accounts to have their own keychain slots.
    func string(for key: AppSecretKey, accountID: String?) -> String?
    func set(_ value: String?, for key: AppSecretKey, accountID: String?)
}

extension SecretStoring {
    func string(for key: AppSecretKey) -> String? {
        string(for: key, accountID: nil)
    }

    func set(_ value: String?, for key: AppSecretKey) {
        set(value, for: key, accountID: nil)
    }
}

struct KeychainSecretStore: SecretStoring {
    private let service = "com.maxforsey.Dahso.app-settings"
    /// Separator between the base secret key and the account id in a per-account keychain slot,
    /// e.g. `google-refresh-token::max@example.com`. Changing this orphans existing secrets.
    private static let accountIDSeparator = "::"

    func string(for key: AppSecretKey, accountID: String?) -> String? {
        var query = baseQuery(for: key, accountID: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func set(_ value: String?, for key: AppSecretKey, accountID: String?) {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalized.isEmpty {
            SecItemDelete(baseQuery(for: key, accountID: accountID) as CFDictionary)
            return
        }

        let data = Data(normalized.utf8)
        let query = baseQuery(for: key, accountID: accountID)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
            return
        }

        if status != errSecSuccess {
            Log.app.error("Failed to update keychain secret: \(keychainAccount(for: key, accountID: accountID))")
        }
    }

    private func baseQuery(for key: AppSecretKey, accountID: String?) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount(for: key, accountID: accountID),
        ]
    }

    private func keychainAccount(for key: AppSecretKey, accountID: String?) -> String {
        guard let accountID, !accountID.isEmpty else { return key.rawValue }
        return "\(key.rawValue)\(Self.accountIDSeparator)\(accountID.lowercased())"
    }
}

final class InMemorySecretStore: SecretStoring {
    private struct SecretKey: Hashable {
        let key: AppSecretKey
        let accountID: String
    }

    private var values: [SecretKey: String]

    init(values: [AppSecretKey: String] = [:]) {
        self.values = Dictionary(uniqueKeysWithValues: values.map { (SecretKey(key: $0.key, accountID: ""), $0.value) })
    }

    func string(for key: AppSecretKey, accountID: String?) -> String? {
        values[SecretKey(key: key, accountID: (accountID ?? "").lowercased())]
    }

    func set(_ value: String?, for key: AppSecretKey, accountID: String?) {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storageKey = SecretKey(key: key, accountID: (accountID ?? "").lowercased())
        if normalized.isEmpty {
            values.removeValue(forKey: storageKey)
        } else {
            values[storageKey] = normalized
        }
    }
}
