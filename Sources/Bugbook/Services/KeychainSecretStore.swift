import Foundation
import Security

enum AppSecretKey: String, CaseIterable {
    case anthropicApiKey = "anthropic-api-key"
    case googleAccessToken = "google-access-token"
    case googleRefreshToken = "google-refresh-token"
}

protocol SecretStoring {
    func string(for key: AppSecretKey) -> String?
    func set(_ value: String?, for key: AppSecretKey)
}

struct KeychainSecretStore: SecretStoring {
    private let service = "com.maxforsey.Bugbook.app-settings"

    func string(for key: AppSecretKey) -> String? {
        var query = baseQuery(for: key)
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

    func set(_ value: String?, for key: AppSecretKey) {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalized.isEmpty {
            SecItemDelete(baseQuery(for: key) as CFDictionary)
            return
        }

        let data = Data(normalized.utf8)
        let query = baseQuery(for: key)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
            return
        }

        if status != errSecSuccess {
            Log.app.error("Failed to update keychain secret: \(key.rawValue)")
        }
    }

    private func baseQuery(for key: AppSecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}

final class InMemorySecretStore: SecretStoring {
    private var values: [AppSecretKey: String]

    init(values: [AppSecretKey: String] = [:]) {
        self.values = values
    }

    func string(for key: AppSecretKey) -> String? {
        values[key]
    }

    func set(_ value: String?, for key: AppSecretKey) {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalized.isEmpty {
            values.removeValue(forKey: key)
        } else {
            values[key] = normalized
        }
    }
}
