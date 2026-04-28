import Foundation

/// Single source of truth for resolving the canonical Dahso workspace path across
/// CLI, macOS, and iOS targets. All three should default to the same physical folder.
///
/// Default behavior: prefer the iCloud ubiquity container when the caller has the
/// entitlement and iCloud is available; otherwise fall back to `~/Documents/Dahso`.
///
/// The CLI binary has no iCloud entitlement, so
/// `FileManager.url(forUbiquityContainerIdentifier:)` always returns `nil` there and
/// the CLI takes the local fallback. On machines where `~/Documents/Dahso` is a
/// symlink into the iCloud container (the canonical setup), that fallback still
/// resolves to the same physical folder the iOS app writes to.
public enum WorkspaceResolver {
    public static let ubiquityContainerID = "iCloud.com.dahso.app"
    public static let defaultFolderName = "Dahso"

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
        return localFallbackWorkspacePath(
            createIfMissing: createIfMissing,
            resolveRichestSibling: allowBlockingICloudLookup
        )
    }

    /// Resolves the iCloud Dahso workspace path. Returns `nil` if iCloud is
    /// unavailable, the caller lacks the ubiquity container entitlement, or the user
    /// is not signed into iCloud. May block on first use per process.
    ///
    /// When the default "Dahso" folder is mostly empty but a sibling like
    /// "Dahso 2" or "Dahso 3" has real content (iCloud conflict duplication),
    /// returns the richest sibling instead.
    public static func resolveICloudWorkspacePath(createIfMissing: Bool = true) -> String? {
        let fm = FileManager.default
        guard let containerURL = fm.url(forUbiquityContainerIdentifier: ubiquityContainerID) else {
            return nil
        }
        let documentsURL = containerURL.appendingPathComponent("Documents")
        let defaultPath = documentsURL.appendingPathComponent(defaultFolderName).path

        // Scan all "Dahso*" siblings and pick the one with the most .md files.
        // Handles iCloud conflict duplication ("Dahso 2", "Dahso 3", etc.)
        if let siblings = try? fm.contentsOfDirectory(atPath: documentsURL.path) {
            let candidates = siblings
                .filter { $0.hasPrefix(defaultFolderName) }
                .map { documentsURL.appendingPathComponent($0).path }
                .map { (path: $0, count: mdFileCount(at: $0, fm: fm)) }
                .sorted { $0.count > $1.count }

            // swiftlint:disable:next empty_count
            if let best = candidates.first, best.count > 0 {
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
    /// Count user-authored .md files, excluding database rows and underscore-prefixed files.
    private static func mdFileCount(at path: String, fm: FileManager, depth: Int = 0) -> Int {
        guard depth < 3, let entries = try? fm.contentsOfDirectory(atPath: path) else { return 0 }
        var count = 0
        for name in entries where !name.hasPrefix(".") {
            if name == "databases" || name == "Daily Notes" || name == "Templates" { continue }
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

    /// `~/Documents/Dahso`. Always available. On the canonical setup this is a
    /// symlink into the iCloud Dahso container, so it resolves to the same
    /// physical folder as `resolveICloudWorkspacePath()`.
    ///
    /// If the default path is a symlink into an iCloud container with richer
    /// sibling workspaces, picks the richest one (same logic as iCloud resolver).
    public static func localFallbackWorkspacePath(
        createIfMissing: Bool = true,
        resolveRichestSibling: Bool = true
    ) -> String {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        return localFallbackWorkspacePath(
            documentsURL: documents,
            createIfMissing: createIfMissing,
            resolveRichestSibling: resolveRichestSibling,
            fileManager: fm
        )
    }

    static func localFallbackWorkspacePath(
        documentsURL: URL,
        createIfMissing: Bool = true,
        resolveRichestSibling: Bool = true,
        fileManager fm: FileManager = .default
    ) -> String {
        let documents = documentsURL
        let defaultPath = documents.appendingPathComponent(defaultFolderName, isDirectory: true).path

        // Resolve symlink to check for sibling workspaces in the iCloud container
        if resolveRichestSibling {
            let resolved = (defaultPath as NSString).resolvingSymlinksInPath
            let parentDir = (resolved as NSString).deletingLastPathComponent
            if let siblings = try? fm.contentsOfDirectory(atPath: parentDir) {
                let candidates = siblings
                    .filter { $0.hasPrefix(defaultFolderName) }
                    .map { (parentDir as NSString).appendingPathComponent($0) }
                    .map { (path: $0, count: mdFileCount(at: $0, fm: fm)) }
                    .sorted { $0.count > $1.count }
                // swiftlint:disable:next empty_count
                if let best = candidates.first, best.count > 0 {
                    return best.path
                }
            }
        }

        if createIfMissing, !fm.fileExists(atPath: defaultPath) {
            try? fm.createDirectory(atPath: defaultPath, withIntermediateDirectories: true)
        }
        return defaultPath
    }
}
