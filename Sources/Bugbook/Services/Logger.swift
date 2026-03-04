import Foundation
import os

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
    /// Canvas operations
    static let canvas = Logger(subsystem: subsystem, category: "Canvas")
    /// General app lifecycle
    static let app = Logger(subsystem: subsystem, category: "App")

    // MARK: - Signpost for Performance

    /// Signpost log for measuring performance intervals in Instruments.
    static let signpost = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
