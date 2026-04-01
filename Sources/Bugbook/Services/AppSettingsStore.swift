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
            hydrateSecrets(into: &fallback)
            return fallback
        }
        var loaded = settings
        let shouldRewrite = migrateLegacySecrets(from: loaded)
        hydrateSecrets(into: &loaded)
        if shouldRewrite {
            save(loaded)
        }
        return loaded
    }

    func save(_ settings: AppSettings) {
        do {
            try ensureParentDirectoryExists()
            persistSecrets(from: settings)
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
        if settings.googleAccessToken.isEmpty {
            settings.googleAccessToken = secretStore.string(for: .googleAccessToken) ?? ""
        }
        if settings.googleRefreshToken.isEmpty {
            settings.googleRefreshToken = secretStore.string(for: .googleRefreshToken) ?? ""
        }
    }

    private func migrateLegacySecrets(from settings: AppSettings) -> Bool {
        var migrated = false
        migrated = migrateLegacySecret(settings.anthropicApiKey, key: .anthropicApiKey) || migrated
        migrated = migrateLegacySecret(settings.googleAccessToken, key: .googleAccessToken) || migrated
        migrated = migrateLegacySecret(settings.googleRefreshToken, key: .googleRefreshToken) || migrated
        return migrated
    }

    private func migrateLegacySecret(_ value: String, key: AppSecretKey) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if secretStore.string(for: key) != normalized {
            secretStore.set(normalized, for: key)
        }
        return true
    }

    private func persistSecrets(from settings: AppSettings) {
        secretStore.set(settings.anthropicApiKey, for: .anthropicApiKey)
        secretStore.set(settings.googleAccessToken, for: .googleAccessToken)
        secretStore.set(settings.googleRefreshToken, for: .googleRefreshToken)
    }

    private func sanitized(_ settings: AppSettings) -> AppSettings {
        var sanitized = settings
        sanitized.anthropicApiKey = ""
        sanitized.googleAccessToken = ""
        sanitized.googleRefreshToken = ""
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
}
