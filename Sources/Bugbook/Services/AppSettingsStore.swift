import Foundation

struct AppSettingsStore {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: AppSettings) {
        do {
            try ensureParentDirectoryExists()
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("Failed to save app settings: \(error.localizedDescription)")
        }
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
