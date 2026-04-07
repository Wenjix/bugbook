import Foundation

/// Single source of truth for resolving the canonical Bugbook workspace path across
/// CLI, macOS, and iOS targets. All three should default to the same physical folder.
///
/// Default behavior: prefer the iCloud ubiquity container when the caller has the
/// entitlement and iCloud is available; otherwise fall back to `~/Documents/Bugbook`.
///
/// The CLI binary has no iCloud entitlement, so
/// `FileManager.url(forUbiquityContainerIdentifier:)` always returns `nil` there and
/// the CLI takes the local fallback. On machines where `~/Documents/Bugbook` is a
/// symlink into the iCloud container (the canonical setup), that fallback still
/// resolves to the same physical folder the iOS app writes to.
public enum WorkspaceResolver {
    public static let ubiquityContainerID = "iCloud.com.bugbook.app"
    public static let defaultFolderName = "Bugbook"

    /// Returns the canonical workspace path for the running target.
    ///
    /// - Parameters:
    ///   - allowBlockingICloudLookup: When `true`, calls
    ///     `url(forUbiquityContainerIdentifier:)`, which can block for seconds on
    ///     first use per process. Pass `false` from main-actor callers that must
    ///     return immediately; they should upgrade asynchronously via
    ///     `resolveICloudWorkspacePath()` from a background task.
    ///   - createIfMissing: When `true`, creates the workspace directory if it does
    ///     not exist.
    public static func defaultWorkspacePath(
        allowBlockingICloudLookup: Bool = true,
        createIfMissing: Bool = true
    ) -> String {
        if allowBlockingICloudLookup,
           let iCloudPath = resolveICloudWorkspacePath(createIfMissing: createIfMissing) {
            return iCloudPath
        }
        return localFallbackWorkspacePath(createIfMissing: createIfMissing)
    }

    /// Resolves the iCloud Bugbook workspace path. Returns `nil` if iCloud is
    /// unavailable, the caller lacks the ubiquity container entitlement, or the user
    /// is not signed into iCloud. May block on first use per process.
    public static func resolveICloudWorkspacePath(createIfMissing: Bool = true) -> String? {
        let fm = FileManager.default
        guard let containerURL = fm.url(forUbiquityContainerIdentifier: ubiquityContainerID) else {
            return nil
        }
        let path = containerURL
            .appendingPathComponent("Documents/\(defaultFolderName)")
            .path
        if createIfMissing, !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        return path
    }

    /// `~/Documents/Bugbook`. Always available. On the canonical setup this is a
    /// symlink into the iCloud Bugbook container, so it resolves to the same
    /// physical folder as `resolveICloudWorkspacePath()`.
    public static func localFallbackWorkspacePath(createIfMissing: Bool = true) -> String {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let path = documents.appendingPathComponent(defaultFolderName, isDirectory: true).path
        if createIfMissing, !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        return path
    }
}
