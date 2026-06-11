import Foundation

/// Resolves the app's profile root (the "…/Application Support/Bugbook"
/// directory that holds Settings/, WorkspaceLayouts/, EditorDrafts/, AiThreads/,
/// icons/, covers/, …).
///
/// `BUGBOOK_APP_SUPPORT_DIR` overrides the entire profile directory. It exists
/// so tests and automation can run a fully isolated profile without relying on
/// `$HOME` redirection surviving the launch — a mangled `$HOME` once let a dev
/// session write into the real profile.
enum BugbookPaths {
    static let appSupportOverrideKey = "BUGBOOK_APP_SUPPORT_DIR"

    /// The profile root. Honors the `BUGBOOK_APP_SUPPORT_DIR` override; falls
    /// back to "<Application Support>/Bugbook".
    static func profileDirectory(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[appSupportOverrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory.appendingPathComponent("Bugbook", isDirectory: true)
    }
}
