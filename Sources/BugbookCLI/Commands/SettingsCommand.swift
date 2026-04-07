import ArgumentParser
import Foundation

struct Settings: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings",
        abstract: "Read and write app settings",
        subcommands: [List.self, GetSetting.self, SetSetting.self]
    )

    // MARK: - Shared helpers

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Bugbook", isDirectory: true)
            .appendingPathComponent("Settings", isDirectory: true)
            .appendingPathComponent("app-settings.json")
    }

    /// Secret keys that must never be printed or overwritten via CLI.
    private static let secretKeys: Set<String> = [
        "anthropicApiKey", "googleAccessToken", "googleRefreshToken",
        "googleClientID", "googleClientSecret"
    ]

    static func loadSettings() throws -> [String: Any] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.fileNotFound("Settings file not found at \(url.path)")
        }
        let data = try Data(contentsOf: url)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIError.operationFailed("Settings file is not a JSON object")
        }
        return dict
    }

    static func saveSettings(_ dict: [String: Any]) throws {
        let url = fileURL
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    static func redactedSettings(_ dict: [String: Any]) -> [String: Any] {
        var output = dict
        for key in secretKeys {
            if output[key] != nil {
                output[key] = "<redacted>"
            }
        }
        return output
    }

    // MARK: - Subcommands

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Print all settings as JSON"
        )

        func run() throws {
            let dict = try Settings.loadSettings()
            try outputJSON(Settings.redactedSettings(dict))
        }
    }

    struct GetSetting: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Print a single setting value"
        )

        @Argument(help: "Setting key")
        var key: String

        func run() throws {
            let dict = try Settings.loadSettings()
            guard let value = dict[key] else {
                throw CLIError.invalidInput("Unknown setting key: \(key)")
            }
            if Settings.secretKeys.contains(key) {
                print("<redacted>")
            } else if let stringValue = value as? String {
                print(stringValue)
            } else {
                // For non-string values (Bool, Number, Array), output as JSON
                try outputJSON(value)
            }
        }
    }

    struct SetSetting: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Update a setting and save"
        )

        @Argument(help: "Setting key")
        var key: String

        @Argument(help: "New value")
        var value: String

        func run() throws {
            if Settings.secretKeys.contains(key) {
                throw CLIError.invalidInput("Cannot set secret '\(key)' via CLI. Use the GUI instead.")
            }

            var dict = try Settings.loadSettings()

            // Coerce the new value to match the existing value's type
            let coerced: Any
            if let existing = dict[key] {
                coerced = coerceValue(value, toMatch: existing)
            } else {
                // New key — store as string
                coerced = value
            }

            dict[key] = coerced
            try Settings.saveSettings(dict)
            print("Set \(key) = \(value)")
        }

        /// Attempt to match the type of an existing value.
        private func coerceValue(_ newValue: String, toMatch existing: Any) -> Any {
            // JSONSerialization represents JSON booleans as NSNumber (CFBoolean).
            // Check CFBoolean before generic NSNumber to distinguish bool from int/double.
            if let nsNum = existing as? NSNumber, CFGetTypeID(nsNum) == CFBooleanGetTypeID() {
                switch newValue.lowercased() {
                case "true", "1", "yes": return true
                case "false", "0", "no": return false
                default: return newValue
                }
            }
            if existing is Int, let i = Int(newValue) {
                return i
            }
            if existing is Double, let d = Double(newValue) {
                return d
            }
            // Default: string
            return newValue
        }
    }
}
