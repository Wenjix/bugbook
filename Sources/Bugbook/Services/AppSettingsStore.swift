import Foundation

struct AppSettingsStore {
    private let fileManager: FileManager
    private let fileURL: URL
    private let secretStore: SecretStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        secretStore: SecretStoring = KeychainSecretStore()
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.secretStore = secretStore
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            var fallback = AppSettings.default
            if !Self.shouldSkipKeychainSecrets {
                hydrateSecrets(into: &fallback)
            }
            return fallback
        }
        var loaded = settings
        let shouldRewrite = Self.shouldSkipKeychainSecrets ? false : migrateLegacySecrets(into: &loaded)
        if !Self.shouldSkipKeychainSecrets {
            hydrateSecrets(into: &loaded)
        }
        if shouldRewrite {
            save(loaded)
        }
        return loaded
    }

    func save(_ settings: AppSettings) {
        do {
            try ensureParentDirectoryExists()
            if !Self.shouldSkipKeychainSecrets {
                persistSecrets(from: settings)
            }
            let data = try encoder.encode(sanitized(settings))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("Failed to save app settings: \(error.localizedDescription)")
        }
    }

    private func hydrateSecrets(into settings: inout AppSettings) {
        if settings.anthropicApiKey.isEmpty {
            settings.anthropicApiKey = secretStore.string(for: .anthropicApiKey) ?? ""
        }
        for index in settings.googleAccounts.indices {
            let accountID = settings.googleAccounts[index].email
            if settings.googleAccounts[index].accessToken.isEmpty {
                settings.googleAccounts[index].accessToken = secretStore.string(for: .googleAccessToken, accountID: accountID) ?? ""
            }
            if settings.googleAccounts[index].refreshToken.isEmpty {
                settings.googleAccounts[index].refreshToken = secretStore.string(for: .googleRefreshToken, accountID: accountID) ?? ""
            }
        }
    }

    /// Move any tokens that the on-disk JSON still carries (pre-Keychain installs, or the
    /// pre-multi-account `google-*-token` global slot) into the correct Keychain location.
    /// Returns `true` if the settings file should be rewritten to persist the migration.
    private func migrateLegacySecrets(into settings: inout AppSettings) -> Bool {
        var migrated = false
        if migrateAnthropic(into: &settings) { migrated = true }
        if migrateLegacyGoogleSecrets(into: &settings) { migrated = true }
        return migrated
    }

    /// Moves a plaintext anthropic key off disk into Keychain. Only returns `true` if it
    /// actually wrote something that requires a settings-file rewrite (i.e. the JSON still
    /// carries the key in plaintext from an old install).
    private func migrateAnthropic(into settings: inout AppSettings) -> Bool {
        let normalized = settings.anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if secretStore.string(for: .anthropicApiKey) != normalized {
            secretStore.set(normalized, for: .anthropicApiKey)
        }
        // Rewrite only if the plaintext key is still sitting in the in-memory copy.
        // `persistSecrets` + `sanitized` will handle the actual stripping on save.
        return true
    }

    private func migrateLegacyGoogleSecrets(into settings: inout AppSettings) -> Bool {
        let legacyAccess = secretStore.string(for: .googleAccessToken) ?? ""
        let legacyRefresh = secretStore.string(for: .googleRefreshToken) ?? ""
        guard !legacyAccess.isEmpty || !legacyRefresh.isEmpty else { return false }
        guard let firstIndex = settings.googleAccounts.indices.first else { return false }

        var migrated = false
        if settings.googleAccounts[firstIndex].accessToken.isEmpty {
            settings.googleAccounts[firstIndex].accessToken = legacyAccess
            migrated = true
        }
        if settings.googleAccounts[firstIndex].refreshToken.isEmpty {
            settings.googleAccounts[firstIndex].refreshToken = legacyRefresh
            migrated = true
        }

        // Rehome the tokens under the per-account keychain slot, then clear the legacy slot.
        if migrated {
            let accountID = settings.googleAccounts[firstIndex].email
            secretStore.set(settings.googleAccounts[firstIndex].accessToken, for: .googleAccessToken, accountID: accountID)
            secretStore.set(settings.googleAccounts[firstIndex].refreshToken, for: .googleRefreshToken, accountID: accountID)
            secretStore.set(nil, for: .googleAccessToken)
            secretStore.set(nil, for: .googleRefreshToken)
        }
        return migrated
    }

    private func persistSecrets(from settings: AppSettings) {
        secretStore.set(settings.anthropicApiKey, for: .anthropicApiKey)
        for account in settings.googleAccounts {
            secretStore.set(account.accessToken, for: .googleAccessToken, accountID: account.email)
            secretStore.set(account.refreshToken, for: .googleRefreshToken, accountID: account.email)
        }
    }

    private func sanitized(_ settings: AppSettings) -> AppSettings {
        var sanitized = settings
        sanitized.anthropicApiKey = ""
        sanitized.googleAccounts = sanitized.googleAccounts.map { account in
            var stripped = account
            stripped.accessToken = ""
            stripped.refreshToken = ""
            return stripped
        }
        return sanitized
    }

    private func ensureParentDirectoryExists() throws {
        let parent = fileURL.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: parent.path) else { return }
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Bugbook", isDirectory: true)
            .appendingPathComponent("Settings", isDirectory: true)
            .appendingPathComponent("app-settings.json")
    }

    private static var shouldSkipKeychainSecrets: Bool {
        let value = ProcessInfo.processInfo.environment["BUGBOOK_SKIP_KEYCHAIN_SECRETS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["1", "true", "yes", "on"].contains(value ?? "")
    }
}
