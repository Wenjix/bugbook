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
    ///
    /// When the default "Bugbook" folder is mostly empty but a sibling like
    /// "Bugbook 2" or "Bugbook 3" has real content (iCloud conflict duplication),
    /// returns the richest sibling instead.
    public static func resolveICloudWorkspacePath(createIfMissing: Bool = true) -> String? {
        let fm = FileManager.default
        guard let containerURL = fm.url(forUbiquityContainerIdentifier: ubiquityContainerID) else {
            return nil
        }
        let documentsURL = containerURL.appendingPathComponent("Documents")
        let defaultPath = documentsURL.appendingPathComponent(defaultFolderName).path

        // If default folder has real content, use it.
        if fm.fileExists(atPath: defaultPath), mdFileCount(at: defaultPath, fm: fm) > 2 {
            return defaultPath
        }

        // Scan siblings for richer workspace (handles iCloud "Bugbook 2/3" duplicates).
        if let siblings = try? fm.contentsOfDirectory(atPath: documentsURL.path) {
            let candidates = siblings
                .filter { $0.hasPrefix(defaultFolderName) }
                .map { (name: $0, path: documentsURL.appendingPathComponent($0).path) }
                .map { (name: $0.name, path: $0.path, count: mdFileCount(at: $0.path, fm: fm)) }
                .sorted { $0.count > $1.count }

            if let best = candidates.first, best.count > 2 {
                return best.path
            }
        }

        // Fall back to default (create if needed).
        if createIfMissing, !fm.fileExists(atPath: defaultPath) {
            try? fm.createDirectory(atPath: defaultPath, withIntermediateDirectories: true)
        }
        return defaultPath
    }

    /// Count .md files (non-underscore-prefixed) recursively, up to a shallow depth.
    private static func mdFileCount(at path: String, fm: FileManager, depth: Int = 0) -> Int {
        guard depth < 3, let entries = try? fm.contentsOfDirectory(atPath: path) else { return 0 }
        var count = 0
        for name in entries where !name.hasPrefix(".") {
            let full = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                count += mdFileCount(at: full, fm: fm, depth: depth + 1)
            } else if name.hasSuffix(".md") && !name.hasPrefix("_") {
                count += 1
            }
        }
        return count
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
