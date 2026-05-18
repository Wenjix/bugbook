import Foundation
import os
import Sentry

/// Centralized loggers for structured logging across the app.
/// Use the appropriate subsystem logger for each area.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.bugbook.app"

    /// File system operations (create, delete, rename, save)
    static let fileSystem = Logger(subsystem: subsystem, category: "FileSystem")
    /// Database queries, mutations, schema operations
    static let database = Logger(subsystem: subsystem, category: "Database")
    /// AI service (chat, model detection)
    static let ai = Logger(subsystem: subsystem, category: "AI")
    /// Editor operations (block edits, document load/save)
    static let editor = Logger(subsystem: subsystem, category: "Editor")
    /// Navigation (tabs, history, sidebar)
    static let navigation = Logger(subsystem: subsystem, category: "Navigation")
    /// Agent hub (tasks, runs, events)
    static let agent = Logger(subsystem: subsystem, category: "Agent")
    /// Audio capture and transcription
    static let transcription = Logger(subsystem: subsystem, category: "Transcription")
    /// Gmail sync, thread actions, and compose/send flows
    static let mail = Logger(subsystem: subsystem, category: "Mail")
    /// General app lifecycle
    static let app = Logger(subsystem: subsystem, category: "App")

    // MARK: - Signpost for Performance

    /// Signpost log for measuring performance intervals in Instruments.
    static let signpost = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    static func profileMarker(_ name: String) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["BUGBOOK_PROFILE_MARKERS"] == "1" else { return }
        let line = "BUGBOOK_PROFILE_MARKER \(name) \(Date().timeIntervalSince1970)\n"
        guard let data = line.data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
        guard let markerPath = environment["BUGBOOK_PROFILE_MARKER_FILE"], !markerPath.isEmpty else { return }
        if !FileManager.default.fileExists(atPath: markerPath) {
            FileManager.default.createFile(atPath: markerPath, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: markerPath) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }
}

enum SentryBreadcrumbs {
    static func add(_ breadcrumb: Breadcrumb) {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.addBreadcrumb(breadcrumb)
    }
}
