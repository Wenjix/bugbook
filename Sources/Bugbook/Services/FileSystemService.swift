import Foundation
import AppKit
import BugbookCore
import Darwin
import os
import Sentry

@MainActor
@Observable
class FileSystemService {
    private enum ReleaseDefaultsMigration {
        static let markerKey = "releaseDefaultsMigratedFromDevelopmentBundle.v1"
        static let productionBundleIdentifier = "com.maxforsey.Bugbook"
        static let sourceBundleIdentifiers = [
            "com.maxforsey.Dahso.dev",
            "com.maxforsey.Bugbook.dev"
        ]
    }

    private enum DatabaseTreeItem {
        case none
        case hidden
        case visible(FileEntry)
    }

    private enum FileTreeItem {
        case none
        case folder(FileEntry)
        case file(FileEntry)
    }

    enum FirstPartyDatabaseKind: Equatable, Sendable {
        case dailyNotes
        case meetings
    }

    struct LegacyWorkspace: Identifiable, Hashable, Sendable {
        enum Kind: String, CaseIterable, Sendable {
            case documentsDahso
            case dahsoApplicationSupport
            case dahsoICloud
            case applicationSupportBugbook
            case bugbookApplicationSupport
            case bugbookICloud

            var title: String {
                switch self {
                case .documentsDahso:
                    return "Bugbook documents workspace"
                case .dahsoApplicationSupport:
                    return "Bugbook application support data"
                case .dahsoICloud:
                    return "Bugbook iCloud workspace"
                case .applicationSupportBugbook:
                    return "Old Bugbook application support data"
                case .bugbookApplicationSupport:
                    return "Bugbook application support data"
                case .bugbookICloud:
                    return "Bugbook iCloud workspace"
                }
            }

            var sortOrder: Int {
                switch self {
                case .documentsDahso: return 0
                case .dahsoApplicationSupport: return 1
                case .dahsoICloud: return 2
                case .applicationSupportBugbook: return 3
                case .bugbookApplicationSupport: return 4
                case .bugbookICloud: return 5
                }
            }
        }

        let path: URL
        let kind: Kind

        var id: String { defaultsKey }

        var defaultsKey: String {
            "legacyWorkspaceDismissed.\(kind.rawValue).\(path.standardizedFileURL.path)"
        }

        var displayPath: String {
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            guard path.path.hasPrefix(homePath) else { return path.path }
            return path.path.replacingOccurrences(of: homePath, with: "~", options: [.anchored])
        }
    }

    enum MigrationItemKind: String, Equatable, Sendable {
        case file
        case directory
    }

    enum MigrationError: LocalizedError, Equatable, Sendable {
        case legacyWorkspaceNotFound
        case activeWorkspaceNotFolder
        case typeMismatch(
            sourcePath: String,
            destPath: String,
            sourceKind: MigrationItemKind,
            destKind: MigrationItemKind
        )

        var errorDescription: String? {
            switch self {
            case .legacyWorkspaceNotFound:
                return "The legacy workspace could not be found."
            case .activeWorkspaceNotFolder:
                return "The active workspace path is not a folder."
            case let .typeMismatch(sourcePath, destPath, sourceKind, destKind):
                return """
                Cannot migrate \(sourcePath) into \(destPath) because the source is a \
                \(sourceKind.rawValue) and the destination is a \(destKind.rawValue).
                """
            }
        }
    }

    var workspacePath: String?
    var recentWorkspaces: [String] = []
    private(set) var legacyWorkspaces: [LegacyWorkspace] = []

    private let fileManager = FileManager.default
    private let recentWorkspacesKey = "recentWorkspaces"
    private let maxRecentWorkspaces = 20
    private let customOrderPrefix = "sidebarOrder_"
    private let sidebarReferencePrefix = "sidebarReference_"
    private let favoritesPrefix = "favorites_"
    nonisolated private static let legacyMigrationExcludedTopLevelNames: Set<String> = [
        ".bugbook", ".dahso", "MailCache", "EditorDrafts", "drafts"
    ]
    nonisolated private static let legacyMigrationExcludedEntryNames: Set<String> = [
        ".git", ".build", ".DS_Store", "node_modules", ".venv", "__pycache__", ".swiftpm"
    ]
    nonisolated private static let hiddenSidebarFolders: Set<String> = [
        "attachments", "inbox", "raw",
        "aithreads", "assets", "comparisons", "covers", "icons",
        "settings", "workspacelayouts", "daily notes 2",
        // Logseq vault leftovers
        "journals", "logseq", "whiteboards"
    ]

    init() {
        migrateReleaseDefaultsFromDevelopmentBundlesIfNeeded()
        loadRecentWorkspaces()
    }

    private func migrateReleaseDefaultsFromDevelopmentBundlesIfNeeded() {
        guard Bundle.main.bundleIdentifier == ReleaseDefaultsMigration.productionBundleIdentifier else { return }

        let targetDefaults = UserDefaults.standard
        guard !targetDefaults.bool(forKey: ReleaseDefaultsMigration.markerKey) else { return }

        for identifier in ReleaseDefaultsMigration.sourceBundleIdentifiers {
            guard let sourceDefaults = UserDefaults(suiteName: identifier) else { continue }
            migrateSidebarDefaults(from: sourceDefaults, to: targetDefaults)
        }

        targetDefaults.set(true, forKey: ReleaseDefaultsMigration.markerKey)
    }

    private func migrateSidebarDefaults(from sourceDefaults: UserDefaults, to targetDefaults: UserDefaults) {
        for key in sourceDefaults.dictionaryRepresentation().keys where key.hasPrefix(favoritesPrefix) {
            guard let sourcePaths = sourceDefaults.stringArray(forKey: key),
                  !sourcePaths.isEmpty else { continue }

            let currentPaths = targetDefaults.stringArray(forKey: key) ?? []
            guard currentPaths.isEmpty else { continue }

            targetDefaults.set(sourcePaths, forKey: key)
        }
    }

    @discardableResult
    func refreshLegacyWorkspaces(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [LegacyWorkspace] {
        let detectedWorkspaces = detectLegacyWorkspaces(homeDirectory: homeDirectory)
        applyLegacyWorkspaces(detectedWorkspaces)
        return detectedWorkspaces
    }

    @discardableResult
    func refreshLegacyWorkspacesInBackground(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async -> [LegacyWorkspace] {
        let detectedWorkspaces = await Task.detached(priority: .utility) {
            Self.detectLegacyWorkspacesOffMain(homeDirectory: homeDirectory)
        }.value
        applyLegacyWorkspaces(detectedWorkspaces)
        return detectedWorkspaces
    }

    nonisolated func detectLegacyWorkspaces(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [LegacyWorkspace] {
        Self.detectLegacyWorkspacesOffMain(homeDirectory: homeDirectory)
    }

    private func applyLegacyWorkspaces(_ detectedWorkspaces: [LegacyWorkspace]) {
        legacyWorkspaces = detectedWorkspaces
        logLegacyWorkspaceIfPresent()
    }

    nonisolated private static func detectLegacyWorkspacesOffMain(
        homeDirectory: URL
    ) -> [LegacyWorkspace] {
        let fileManager = FileManager.default
        return legacyWorkspaceCandidates(homeDirectory: homeDirectory)
            .filter { containsMigratableContent(at: $0.path, fileManager: fileManager, isTopLevel: true) }
            .sorted { lhs, rhs in
                if lhs.kind.sortOrder != rhs.kind.sortOrder {
                    return lhs.kind.sortOrder < rhs.kind.sortOrder
                }
                return lhs.path.path.localizedCaseInsensitiveCompare(rhs.path.path) == .orderedAscending
            }
    }

    func migrateLegacyWorkspace(
        _ legacyWorkspace: LegacyWorkspace,
        into destinationURL: URL
    ) async throws {
        try await Task.detached(priority: .utility) {
            try Self.copyLegacyWorkspaceContents(
                from: legacyWorkspace.path,
                to: destinationURL
            )
        }.value
    }

    private func logLegacyWorkspaceIfPresent() {
        guard !legacyWorkspaces.isEmpty else { return }
        let canonicalPath = WorkspaceResolver.defaultWorkspacePath(
            allowBlockingICloudLookup: false,
            createIfMissing: false
        )
        for legacyWorkspace in legacyWorkspaces {
            Log.fileSystem.warning(
                "Legacy workspace detected at \(legacyWorkspace.path.path). Review the in-app migration banner before copying into \(canonicalPath)."
            )
        }
    }

    nonisolated private static func legacyWorkspaceCandidates(homeDirectory: URL) -> [LegacyWorkspace] {
        [
            LegacyWorkspace(
                path: homeDirectory
                    .appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Dahso", isDirectory: true),
                kind: .documentsDahso
            ),
            LegacyWorkspace(
                path: homeDirectory
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("Dahso", isDirectory: true),
                kind: .dahsoApplicationSupport
            ),
            LegacyWorkspace(
                path: homeDirectory
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Mobile Documents", isDirectory: true)
                    .appendingPathComponent("iCloud~com~dahso~app", isDirectory: true)
                    .appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Dahso", isDirectory: true),
                kind: .dahsoICloud
            ),
            LegacyWorkspace(
                path: homeDirectory
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("bugbook", isDirectory: true),
                kind: .applicationSupportBugbook
            ),
            LegacyWorkspace(
                path: homeDirectory
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("com.bugbook.app", isDirectory: true),
                kind: .bugbookApplicationSupport
            ),
            LegacyWorkspace(
                path: homeDirectory
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Mobile Documents", isDirectory: true)
                    .appendingPathComponent("iCloud~com~bugbook~app", isDirectory: true)
                    .appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Bugbook 2", isDirectory: true),
                kind: .bugbookICloud
            )
        ]
    }

    nonisolated private static func copyLegacyWorkspaceContents(
        from sourceRoot: URL,
        to destinationRoot: URL
    ) throws {
        let fileManager = FileManager.default
        var sourceIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceRoot.path, isDirectory: &sourceIsDirectory),
              sourceIsDirectory.boolValue else {
            throw MigrationError.legacyWorkspaceNotFound
        }

        let resolvedDestinationRoot = migrationDestinationRoot(
            for: destinationRoot,
            fileManager: fileManager
        )

        var destinationIsDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: resolvedDestinationRoot.path, isDirectory: &destinationIsDirectory) {
            guard destinationIsDirectory.boolValue else {
                throw MigrationError.activeWorkspaceNotFolder
            }
        } else {
            try fileManager.createDirectory(at: resolvedDestinationRoot, withIntermediateDirectories: true)
        }

        let entries = try fileManager.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .contentModificationDateKey,
                .fileSizeKey
            ],
            options: []
        )
        for entry in entries {
            let destination = resolvedDestinationRoot.appendingPathComponent(entry.lastPathComponent)
            try mergeLegacyItem(
                from: entry,
                to: destination,
                fileManager: fileManager,
                isTopLevel: true
            )
        }

        try migrateLegacyMeetingStores(
            from: sourceRoot,
            to: resolvedDestinationRoot,
            fileManager: fileManager
        )
    }

    nonisolated private static func migrationDestinationRoot(
        for destinationRoot: URL,
        fileManager: FileManager
    ) -> URL {
        guard let symlinkDestination = try? fileManager.destinationOfSymbolicLink(
            atPath: destinationRoot.path
        ) else {
            return destinationRoot
        }

        let destinationPath: String
        if symlinkDestination.hasPrefix("/") {
            destinationPath = symlinkDestination
        } else {
            destinationPath = (destinationRoot.deletingLastPathComponent().path as NSString)
                .appendingPathComponent(symlinkDestination)
        }
        return URL(fileURLWithPath: destinationPath, isDirectory: true).standardizedFileURL
    }

    nonisolated private static func containsMigratableContent(
        at directoryURL: URL,
        fileManager: FileManager,
        isTopLevel: Bool
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return false
        }

        for entry in entries {
            if isLegacyMeetingStoreContainer(entry, isTopLevel: isTopLevel, fileManager: fileManager) {
                return true
            }

            if shouldSkipLegacyEntry(named: entry.lastPathComponent, isTopLevel: isTopLevel) {
                continue
            }

            let resourceValues = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if resourceValues?.isSymbolicLink == true {
                continue
            }

            if resourceValues?.isDirectory == true {
                if containsMigratableContent(
                    at: entry,
                    fileManager: fileManager,
                    isTopLevel: false
                ) {
                    return true
                }
                continue
            }

            return true
        }

        return false
    }

    nonisolated private static func isLegacyMeetingStoreContainer(
        _ entry: URL,
        isTopLevel: Bool,
        fileManager: FileManager
    ) -> Bool {
        guard isTopLevel,
              [".bugbook", ".dahso"].contains(entry.lastPathComponent) else {
            return false
        }

        let meetingsDirectory = entry.appendingPathComponent("meetings", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: meetingsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let entries = try? fileManager.contentsOfDirectory(at: meetingsDirectory, includingPropertiesForKeys: nil) else {
            return false
        }

        return entries.contains { $0.pathExtension == "json" }
    }

    nonisolated private static func shouldSkipLegacyEntry(
        named name: String,
        isTopLevel: Bool
    ) -> Bool {
        if isTopLevel && legacyMigrationExcludedTopLevelNames.contains(name) {
            return true
        }
        return legacyMigrationExcludedEntryNames.contains(name)
    }

    nonisolated private static func mergeLegacyItem(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager,
        isTopLevel: Bool
    ) throws {
        guard !shouldSkipLegacyEntry(named: sourceURL.lastPathComponent, isTopLevel: isTopLevel) else {
            return
        }

        let sourceValues = try sourceURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        )
        // v1 skips symlinks entirely. Resolving them could copy unrelated data or recurse
        // back into the workspace through external links.
        if sourceValues.isSymbolicLink == true {
            Log.fileSystem.warning(
                "Skipping symbolic link during legacy workspace migration: \(sourceURL.path)"
            )
            return
        }

        let sourceIsDirectory = sourceValues.isDirectory ?? false
        var destinationIsDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: destinationURL.path, isDirectory: &destinationIsDirectory) else {
            try ensureParentDirectoryExists(for: destinationURL, fileManager: fileManager)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        if sourceIsDirectory && destinationIsDirectory.boolValue {
            let children = try fileManager.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .contentModificationDateKey,
                    .fileSizeKey
                ],
                options: []
            )
            for child in children {
                try mergeLegacyItem(
                    from: child,
                    to: destinationURL.appendingPathComponent(child.lastPathComponent),
                    fileManager: fileManager,
                    isTopLevel: false
                )
            }
            return
        }

        guard !sourceIsDirectory && !destinationIsDirectory.boolValue else {
            throw MigrationError.typeMismatch(
                sourcePath: sourceURL.path,
                destPath: destinationURL.path,
                sourceKind: migrationItemKind(isDirectory: sourceIsDirectory),
                destKind: migrationItemKind(isDirectory: destinationIsDirectory.boolValue)
            )
        }

        if shouldReplaceLegacyDestination(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        ) {
            try replaceDestinationFileAtomically(
                from: sourceURL,
                to: destinationURL,
                fileManager: fileManager
            )
        }
    }

    nonisolated private static func migrateLegacyMeetingStores(
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager
    ) throws {
        let destinationMeetings = destinationRoot
            .appendingPathComponent(".bugbook", isDirectory: true)
            .appendingPathComponent("meetings", isDirectory: true)

        for legacyStoreName in [".dahso", ".bugbook"] {
            let sourceMeetings = sourceRoot
                .appendingPathComponent(legacyStoreName, isDirectory: true)
                .appendingPathComponent("meetings", isDirectory: true)

            var sourceIsDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: sourceMeetings.path, isDirectory: &sourceIsDirectory),
                  sourceIsDirectory.boolValue else {
                continue
            }

            try mergeLegacyItem(
                from: sourceMeetings,
                to: destinationMeetings,
                fileManager: fileManager,
                isTopLevel: false
            )
        }
    }

    nonisolated private static func ensureParentDirectoryExists(
        for destinationURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    nonisolated private static func shouldReplaceLegacyDestination(
        sourceURL: URL,
        destinationURL: URL
    ) -> Bool {
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let sourceValues = try? sourceURL.resourceValues(forKeys: resourceKeys)
        let destinationValues = try? destinationURL.resourceValues(forKeys: resourceKeys)

        guard let destinationDate = destinationValues?.contentModificationDate else {
            return true
        }

        guard let sourceDate = sourceValues?.contentModificationDate else {
            return false
        }

        if sourceDate > destinationDate { return true }
        if destinationDate >= sourceDate {
            if destinationDate == sourceDate,
               let sourceSize = sourceValues?.fileSize,
               let destinationSize = destinationValues?.fileSize,
               sourceSize != destinationSize {
                Log.fileSystem.debug(
                    """
                    Skipping legacy migration overwrite for equal mtime conflict at \
                    \(destinationURL.path); sizes differ between source and destination.
                    """
                )
            }
            return false
        }

        return false
    }

    nonisolated private static func replaceDestinationFileAtomically(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        let tempURL = temporarySiblingURL(
            for: destinationURL,
            marker: "bugbook-migrate-tmp"
        )
        let backupName = "\(destinationURL.lastPathComponent).bugbook-backup-\(UUID().uuidString)"
        let backupURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(backupName)

        do {
            try fileManager.copyItem(at: sourceURL, to: tempURL)
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: tempURL,
                backupItemName: backupName,
                options: []
            )
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
        } catch {
            if fileManager.fileExists(atPath: tempURL.path) {
                try? fileManager.removeItem(at: tempURL)
            }
            if !fileManager.fileExists(atPath: destinationURL.path),
               fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: destinationURL)
            } else if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.removeItem(at: backupURL)
            }
            throw error
        }
    }

    nonisolated private static func temporarySiblingURL(
        for destinationURL: URL,
        marker: String
    ) -> URL {
        destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "\(destinationURL.lastPathComponent).\(marker)-\(UUID().uuidString)"
            )
    }

    nonisolated private static func migrationItemKind(
        isDirectory: Bool
    ) -> MigrationItemKind {
        isDirectory ? .directory : .file
    }

    // MARK: - Workspace Management

    func openFolder() async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Select Notes Folder"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }

        let path = url.path
        setWorkspace(path)
        return path
    }

    func setWorkspace(_ path: String) {
        workspacePath = path
        addToRecentWorkspaces(path)
    }

    func defaultWorkspacePath() -> String {
        // Return the local fallback immediately so the UI renders fast. Callers that
        // want the canonical iCloud path should call upgradeDefaultToICloudIfAvailable()
        // from a background Task after initial render.
        WorkspaceResolver.defaultWorkspacePath(allowBlockingICloudLookup: false)
    }

    /// Resolves the iCloud Bugbook workspace path off the main thread and, if it
    /// differs from the current `workspacePath`, re-points the workspace at it.
    /// No-op when iCloud is unavailable or the current path already matches.
    /// Returns the iCloud path if an upgrade was applied, otherwise `nil`.
    func upgradeDefaultToICloudIfAvailable() async -> String? {
        let iCloudPath = await Task.detached(priority: .utility) {
            WorkspaceResolver.resolveICloudWorkspacePath()
        }.value
        guard let iCloudPath else { return nil }
        guard iCloudPath != workspacePath else { return nil }
        setWorkspace(iCloudPath)
        return iCloudPath
    }

    // MARK: - File Tree Building

    nonisolated func buildFileTree(at path: String, depth: Int = 0) -> [FileEntry] {
        let state = depth == 0 ? Log.signpost.beginInterval("buildFileTree") : nil
        defer { if let state { Log.signpost.endInterval("buildFileTree", state) } }
        let fm = FileManager.default

        guard depth < 5 else { return [] }

        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            return []
        }

        // Collect sibling names for companion folder detection
        let siblingNames = Set(contents)

        var folders: [FileEntry] = []
        var files: [FileEntry] = []
        folders.reserveCapacity(contents.count / 4)
        files.reserveCapacity(contents.count / 2)

        for name in contents {
            switch fileTreeItem(name: name, parentPath: path, siblings: siblingNames, depth: depth) {
            case .folder(let entry):
                folders.append(entry)
            case .file(let entry):
                files.append(entry)
            case .none:
                continue
            }
        }

        // Sort: folders first (alphabetical), then files (alphabetical)
        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return folders + files
    }

    nonisolated private func fileTreeItem(
        name: String,
        parentPath: String,
        siblings: Set<String>,
        depth: Int
    ) -> FileTreeItem {
        guard Self.shouldShowSidebarEntry(named: name) else { return .none }

        let fullPath = (parentPath as NSString).appendingPathComponent(name)
        guard !WorkspacePathRules.shouldIgnoreAbsolutePath(fullPath) else { return .none }

        // Single stat() syscall for both directory check and file size.
        guard let resourceValues = try? URL(fileURLWithPath: fullPath).resourceValues(
            forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        ) else {
            return .none
        }

        if resourceValues.isDirectory ?? false {
            return directoryTreeItem(name: name, path: fullPath, siblings: siblings, depth: depth)
        }
        return markdownTreeItem(
            name: name,
            path: fullPath,
            resourceValues: resourceValues,
            siblings: siblings,
            depth: depth
        )
    }

    nonisolated private static func shouldShowSidebarEntry(named name: String) -> Bool {
        guard !name.hasPrefix(".") else { return false }
        guard !name.hasPrefix("_") else { return false }
        guard name != "Daily Notes", name != "Templates" else { return false }
        return !hiddenSidebarFolders.contains(name.lowercased())
    }

    nonisolated private func directoryTreeItem(
        name: String,
        path: String,
        siblings: Set<String>,
        depth: Int
    ) -> FileTreeItem {
        switch Self.databaseTreeItem(at: path, fallbackName: name) {
        case .visible(let entry):
            return .folder(entry)
        case .hidden:
            return .none
        case .none:
            guard !isCompanionFolder(name, siblings: siblings) else { return .none }
            let children = buildFileTree(at: path, depth: depth + 1)
            guard !children.isEmpty else { return .none }
            return .folder(FileEntry(
                id: path,
                name: name,
                path: path,
                isDirectory: true,
                children: children
            ))
        }
    }

    nonisolated private func markdownTreeItem(
        name: String,
        path: String,
        resourceValues: URLResourceValues,
        siblings: Set<String>,
        depth: Int
    ) -> FileTreeItem {
        guard name.hasSuffix(".md") else { return .none }

        let isDbFile = name.hasSuffix(".db.md")
        // Skip empty .md files and the `# \n` placeholder from createNewFile.
        // Database files are kept regardless of size since they store metadata elsewhere.
        if !isDbFile, let size = resourceValues.fileSize, size < 10 {
            return .none
        }

        let companionName = String(name.dropLast(3))
        let children: [FileEntry]?
        if siblings.contains(companionName) {
            let companionPath = ((path as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(companionName)
            children = buildFileTree(at: companionPath, depth: depth + 1)
        } else {
            children = nil
        }

        return .file(FileEntry(
            id: path,
            name: name,
            path: path,
            isDirectory: false,
            kind: isDbFile ? .database : .page,
            icon: nil,
            children: children
        ))
    }

    nonisolated private static func databaseTreeItem(at path: String, fallbackName: String) -> DatabaseTreeItem {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .none
        }

        guard !isFirstPartyBackingDatabaseSchema(json) else { return .hidden }

        let dbName = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        return .visible(FileEntry(
            id: path,
            name: dbName,
            path: path,
            isDirectory: false,
            kind: .database
        ))
    }

    nonisolated private static func isFirstPartyBackingDatabaseSchema(_ json: [String: Any]) -> Bool {
        guard let id = json["id"] as? String else { return false }
        return id == "db_daily_notes" || id == "db_meetings"
    }

    // MARK: - File Operations

    func loadFile(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    func saveFile(at path: String, content: String) throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func createNewFile(in directory: String, name: String = "New Page") throws -> String {
        let filename = uniqueFilename(in: directory, base: name, ext: "md")
        let filePath = (directory as NSString).appendingPathComponent(filename)
        try "# \n".write(toFile: filePath, atomically: true, encoding: .utf8)
        Log.fileSystem.info("Created file: \(filename)")
        SentryBreadcrumbs.add(Breadcrumb(level: .info, category: "file.create"))
        return filePath
    }

    func createFolder(at path: String) throws {
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func renameFile(from oldPath: String, to newPath: String) throws {
        let oldCompanion = companionFolderPath(for: oldPath)
        let newCompanion = companionFolderPath(for: newPath)
        let shouldMoveCompanion = oldPath.hasSuffix(".md") &&
            newPath.hasSuffix(".md") &&
            fileManager.fileExists(atPath: oldCompanion)
        if shouldMoveCompanion && fileManager.fileExists(atPath: newCompanion) {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteFileExistsError,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "A folder named \"\((newCompanion as NSString).lastPathComponent)\" already exists."
                ]
            )
        }

        try fileManager.moveItem(atPath: oldPath, toPath: newPath)
        if shouldMoveCompanion {
            do {
                try fileManager.moveItem(atPath: oldCompanion, toPath: newCompanion)
            } catch {
                try? fileManager.moveItem(atPath: newPath, toPath: oldPath)
                throw error
            }
        }
        Log.fileSystem.info("Renamed: \((oldPath as NSString).lastPathComponent) → \((newPath as NSString).lastPathComponent)")
        SentryBreadcrumbs.add(Breadcrumb(level: .info, category: "file.rename"))
        NotificationCenter.default.post(name: .fileMoved, object: nil, userInfo: [
            "oldPath": oldPath,
            "newPath": newPath
        ])
    }

    func deleteFile(at path: String) throws {
        let name = (path as NSString).lastPathComponent
        try fileManager.removeItem(atPath: path)
        Log.fileSystem.info("Deleted file: \(name)")
        SentryBreadcrumbs.add(Breadcrumb(level: .info, category: "file.delete"))
        // Also remove companion folder if it exists
        let companion = companionFolderPath(for: path)
        if fileManager.fileExists(atPath: companion) {
            try fileManager.removeItem(atPath: companion)
            Log.fileSystem.debug("Deleted companion folder for: \(name)")
        }
        // Remove any database embed blocks referencing this path from on-disk pages (background)
        if let root = workspacePath {
            let dbPath = path
            let fm = fileManager
            Task.detached(priority: .utility) {
                let marker = "<!-- database: \(dbPath) -->"
                var files: [String] = []
                if let enumerator = fm.enumerator(atPath: root) {
                    while let item = enumerator.nextObject() as? String {
                        if item.hasSuffix(".md") {
                            files.append((root as NSString).appendingPathComponent(item))
                        }
                    }
                }
                for filePath in files {
                    guard let text = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
                    let filtered = text.components(separatedBy: "\n")
                        .filter { $0.trimmingCharacters(in: .whitespaces) != marker }
                        .joined(separator: "\n")
                    if filtered != text {
                        try? filtered.write(toFile: filePath, atomically: true, encoding: .utf8)
                    }
                }
            }
        }
    }

    func duplicateFile(at path: String) throws -> String {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }

        if isDir.boolValue {
            let dir = (path as NSString).deletingLastPathComponent
            let originalName = (path as NSString).lastPathComponent
            let newPath = uniqueDirectoryPath(in: dir, base: "\(originalName) copy")
            try fileManager.copyItem(atPath: path, toPath: newPath)
            let displayName = (newPath as NSString).lastPathComponent
            if isDatabaseFolder(at: newPath) {
                try? updateDatabaseDisplayName(at: newPath, name: displayName)
            }
            return newPath
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let dir = (path as NSString).deletingLastPathComponent
        let originalName = (path as NSString).lastPathComponent
        let baseName = (originalName as NSString).deletingPathExtension

        let newFilename = uniqueFilename(in: dir, base: "\(baseName) copy", ext: "md")
        let newPath = (dir as NSString).appendingPathComponent(newFilename)
        try content.write(toFile: newPath, atomically: true, encoding: .utf8)
        return newPath
    }

    /// Move a page (and its companion folder) to a new parent directory.
    /// Returns the new path of the moved file.
    func movePage(at sourcePath: String, toDirectory destDir: String) throws -> String {
        let name = (sourcePath as NSString).lastPathComponent
        let destPath = (destDir as NSString).appendingPathComponent(name)

        guard sourcePath != destPath else { return sourcePath }
        guard !fileManager.fileExists(atPath: destPath) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError,
                          userInfo: [NSLocalizedDescriptionKey: "A file named \"\(name)\" already exists in the destination."])
        }

        // Check companion folder conflict before moving anything
        let sourceCompanion = companionFolderPath(for: sourcePath)
        let destCompanion = companionFolderPath(for: destPath)
        let hasCompanion = sourcePath.hasSuffix(".md") && fileManager.fileExists(atPath: sourceCompanion)
        if hasCompanion && fileManager.fileExists(atPath: destCompanion) {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError,
                          userInfo: [NSLocalizedDescriptionKey: "A folder named \"\((sourceCompanion as NSString).lastPathComponent)\" already exists in the destination."])
        }

        // Prevent moving a page into its own subtree
        if hasCompanion && destDir.hasPrefix(sourceCompanion + "/") {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInvalidFileNameError,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot move a page into its own sub-pages."])
        }

        // Create destination directory if needed (e.g. companion folder for a parent page)
        let createdDestDir = !fileManager.fileExists(atPath: destDir)
        if createdDestDir {
            try fileManager.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        }

        // Move the file — clean up created directory on failure to avoid orphans
        do {
            try fileManager.moveItem(atPath: sourcePath, toPath: destPath)
        } catch {
            if createdDestDir, let contents = try? fileManager.contentsOfDirectory(atPath: destDir), contents.isEmpty {
                try? fileManager.removeItem(atPath: destDir)
            }
            throw error
        }

        // Move companion folder if it exists
        if hasCompanion {
            try fileManager.moveItem(atPath: sourceCompanion, toPath: destCompanion)
        }

        Log.fileSystem.info("Moved page: \(name) → \(destDir)")
        SentryBreadcrumbs.add(Breadcrumb(level: .info, category: "file.move"))
        return destPath
    }

    func createSubPage(under pagePath: String, name: String) throws -> String {
        let companion = companionFolderPath(for: pagePath)

        if !fileManager.fileExists(atPath: companion) {
            try fileManager.createDirectory(atPath: companion, withIntermediateDirectories: true)
        }

        let sanitizedName = name.replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
        let filename = uniqueFilename(in: companion, base: sanitizedName, ext: "md")
        let filePath = (companion as NSString).appendingPathComponent(filename)

        try "# \(sanitizedName)\n\n".write(toFile: filePath, atomically: true, encoding: .utf8)
        return filePath
    }

    func createDatabase(underPage pagePath: String, name: String) throws -> String {
        let companion = companionFolderPath(for: pagePath)
        if !fileManager.fileExists(atPath: companion) {
            try fileManager.createDirectory(atPath: companion, withIntermediateDirectories: true)
        }
        return try createDatabase(in: companion, name: name)
    }

    func createDatabase(in directory: String, name: String) throws -> String {
        let sanitizedName = sanitizeDatabaseFolderName(name)
        let folderPath = uniqueDirectoryPath(in: directory, base: sanitizedName)
        try fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true)

        let defaultViewId = "view_table"
        let now = ISO8601DateFormatter().string(from: Date())
        let schemaName = (folderPath as NSString).lastPathComponent
        let dbId = "db_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
        let schema = DatabaseSchema(
            id: dbId,
            name: schemaName,
            version: 1,
            properties: [
                PropertyDefinition(id: "prop_title", name: "Name", type: .title),
            ],
            views: [
                ViewConfig(id: defaultViewId, name: "Table", type: .table, sorts: [], filters: [])
            ],
            defaultView: defaultViewId,
            createdAt: now
        )

        // Write _schema.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(schema)
        let schemaPath = (folderPath as NSString).appendingPathComponent("_schema.json")
        try jsonData.write(to: URL(fileURLWithPath: schemaPath), options: .atomic)

        // Write empty _index.json
        let indexPath = (folderPath as NSString).appendingPathComponent("_index.json")
        let emptyIndex: [String: Any] = ["version": 1, "updated_at": now, "rows": [:] as [String: Any], "indexes": [:] as [String: Any]]
        let indexData = try JSONSerialization.data(withJSONObject: emptyIndex, options: [.prettyPrinted, .sortedKeys])
        try indexData.write(to: URL(fileURLWithPath: indexPath), options: .atomic)

        return folderPath
    }

    nonisolated func retargetDatabaseEmbedsInWorkspace(
        from oldDatabasePath: String,
        to newDatabasePath: String,
        workspace: String,
        excluding excludedPaths: Set<String> = []
    ) {
        let oldMarker = "<!-- database: \(oldDatabasePath) -->"
        let newMarker = "<!-- database: \(newDatabasePath) -->"
        guard oldMarker != newMarker else { return }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: workspace) else { return }
        while let relativePath = enumerator.nextObject() as? String {
            if WorkspacePathRules.shouldIgnoreRelativePath(relativePath) {
                enumerator.skipDescendants()
                continue
            }

            guard relativePath.hasSuffix(".md") else { continue }
            let filePath = (workspace as NSString).appendingPathComponent(relativePath)
            guard !excludedPaths.contains(filePath),
                  let content = try? String(contentsOfFile: filePath, encoding: .utf8),
                  content.contains(oldMarker) else {
                continue
            }

            let nextContent = content.replacingOccurrences(of: oldMarker, with: newMarker)
            guard nextContent != content else { continue }
            try? nextContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Daily Notes

    struct FirstPartyDatabaseLocation: Equatable, Sendable {
        let hubPath: String
        let databasePath: String
        let rowPath: String?
    }

    func dailyNotePath(in workspace: String) -> String {
        FirstPartyDatabaseFiles.dailyNotePath(in: workspace)
    }

    func openOrCreateDailyNote(in workspace: String) throws -> String {
        try FirstPartyDatabaseFiles.openOrCreateDailyNote(in: workspace)
    }

    func openOrCreateDailyNoteInBackground(in workspace: String) async throws -> String {
        try await Task.detached(priority: .utility) {
            try FirstPartyDatabaseFiles.openOrCreateDailyNote(in: workspace)
        }.value
    }

    func ensureDailyNotesHub(in workspace: String, date: Date = Date()) throws -> FirstPartyDatabaseLocation {
        try FirstPartyDatabaseFiles.ensureDailyNotesHub(in: workspace, date: date)
    }

    func ensureMeetingsHub(in workspace: String) throws -> FirstPartyDatabaseLocation {
        try FirstPartyDatabaseFiles.ensureMeetingsHub(in: workspace)
    }

    func ensureMeetingsHubInBackground(in workspace: String) async throws -> FirstPartyDatabaseLocation {
        try await Task.detached(priority: .utility) {
            try FirstPartyDatabaseFiles.ensureMeetingsHub(in: workspace)
        }.value
    }

    func createMeetingDatabaseRow(
        in workspace: String,
        title: String,
        date: Date,
        durationMinutes: Int? = nil,
        attendees: [String] = [],
        body: String = ""
    ) throws -> FirstPartyDatabaseLocation {
        try FirstPartyDatabaseFiles.createMeetingDatabaseRow(
            in: workspace,
            title: title,
            date: date,
            durationMinutes: durationMinutes,
            attendees: attendees,
            body: body
        )
    }

    func createMeetingDatabaseRowInBackground(
        in workspace: String,
        title: String,
        date: Date,
        durationMinutes: Int? = nil,
        attendees: [String] = [],
        body: String = ""
    ) async throws -> FirstPartyDatabaseLocation {
        try await Task.detached(priority: .utility) {
            try FirstPartyDatabaseFiles.createMeetingDatabaseRow(
                in: workspace,
                title: title,
                date: date,
                durationMinutes: durationMinutes,
                attendees: attendees,
                body: body
            )
        }.value
    }

    func refreshMeetingsDatabaseIndex(in workspace: String) throws {
        try FirstPartyDatabaseFiles.refreshMeetingsDatabaseIndex(in: workspace)
    }

    func refreshFirstPartyDatabaseIndexForRowFile(at rowPath: String) throws {
        try FirstPartyDatabaseFiles.refreshFirstPartyDatabaseIndexForRowFile(at: rowPath)
    }

    func firstPartyDatabaseKindForRowFile(at rowPath: String) -> FirstPartyDatabaseKind? {
        FirstPartyDatabaseFiles.firstPartyDatabaseKindForRowFile(at: rowPath)
    }

    func firstPartySchemaForRowFile(at rowPath: String) -> DatabaseSchema? {
        FirstPartyDatabaseFiles.firstPartySchemaForRowFile(at: rowPath)
    }

    func synchronizeMeetingRowFilename(rowPath: String, title: String) throws -> String {
        try FirstPartyDatabaseFiles.synchronizeMeetingRowFilename(rowPath: rowPath, title: title)
    }

    func firstPartyPagePathForDatabaseRow(dbPath: String, rowId: String) -> String? {
        FirstPartyDatabaseFiles.firstPartyPagePathForDatabaseRow(dbPath: dbPath, rowId: rowId)
    }

    func rowFilePathForDatabaseRow(dbPath: String, rowId: String) -> String? {
        FirstPartyDatabaseFiles.rowFilePathForDatabaseRow(dbPath: dbPath, rowId: rowId)
    }

    // MARK: - Templates

    func listTemplates(in workspace: String) -> [FileEntry] {
        let folder = (workspace as NSString).appendingPathComponent("Templates")
        if !fileManager.fileExists(atPath: folder) {
            try? fileManager.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        guard let contents = try? fileManager.contentsOfDirectory(atPath: folder) else { return [] }
        return contents
            .filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
            .sorted()
            .map { name in
                let path = (folder as NSString).appendingPathComponent(name)
                return FileEntry(id: path, name: name, path: path, isDirectory: false)
            }
    }

    func saveAsTemplate(content: String, name: String, in workspace: String) throws {
        let folder = (workspace as NSString).appendingPathComponent("Templates")
        if !fileManager.fileExists(atPath: folder) {
            try fileManager.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        let filename = uniqueFilename(in: folder, base: name, ext: "md")
        let filePath = (folder as NSString).appendingPathComponent(filename)
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    func createFromTemplate(templatePath: String, in directory: String, name: String) throws -> String {
        var content = try String(contentsOfFile: templatePath, encoding: .utf8)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: Date())

        content = content
            .replacingOccurrences(of: "{{title}}", with: name)
            .replacingOccurrences(of: "{{date}}", with: dateStr)
            .replacingOccurrences(of: "{{time}}", with: timeStr)

        let filename = uniqueFilename(in: directory, base: name, ext: "md")
        let filePath = (directory as NSString).appendingPathComponent(filename)
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
        return filePath
    }

    // MARK: - Breadcrumbs

    func getBreadcrumbs(for filePath: String, relativeTo workspace: String) -> [BreadcrumbItem] {
        guard filePath.hasPrefix(workspace) else { return [] }

        let relativePath = String(filePath.dropFirst(workspace.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = relativePath.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return [] }

        var breadcrumbs: [BreadcrumbItem] = []
        var currentPath = workspace

        for (i, part) in parts.enumerated() {
            currentPath = (currentPath as NSString).appendingPathComponent(part)

            if i < parts.count - 1 {
                // Folder segment
                var segmentName = part
                var segmentPath: String
                if isDatabaseFolder(at: currentPath) {
                    // Database folder - use schema name and link to the database itself
                    let schemaPath = (currentPath as NSString).appendingPathComponent("_schema.json")
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let schemaName = json["name"] as? String {
                        segmentName = schemaName
                    }
                    segmentPath = currentPath
                } else {
                    // Regular folder - link to parent page .md if it exists
                    let parentPagePath = (currentPath as NSString).deletingLastPathComponent
                    segmentPath = (parentPagePath as NSString).appendingPathComponent("\(part).md")
                }
                breadcrumbs.append(BreadcrumbItem(
                    id: currentPath,
                    name: segmentName,
                    path: segmentPath,
                    icon: parseIconFromFile(at: segmentPath)
                ))
            } else {
                // The file itself
                var displayName = part.hasSuffix(".md") ? String(part.dropLast(3)) : part
                // For database folders, use schema name instead of folder name
                if isDatabaseFolder(at: currentPath) {
                    let schemaPath = (currentPath as NSString).appendingPathComponent("_schema.json")
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let schemaName = json["name"] as? String {
                        displayName = schemaName
                    }
                }
                breadcrumbs.append(BreadcrumbItem(
                    id: currentPath,
                    name: displayName,
                    path: currentPath,
                    icon: parseIconFromFile(at: currentPath)
                ))
            }
        }

        return breadcrumbs
    }

    // MARK: - Icon Parsing

    func parseIcon(from content: String) -> String? {
        guard let range = content.range(of: "<!-- icon:(.*?) -->", options: .regularExpression) else {
            return nil
        }
        let match = String(content[range])
        let inner = match.dropFirst(10).dropLast(4).trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? nil : inner
    }

    // MARK: - Custom File Order (Drag & Drop)

    /// Returns the UserDefaults key for a given parent directory path.
    private func orderKey(for parentPath: String) -> String {
        let key = parentPath.isEmpty ? "__root__" : parentPath
        return "\(customOrderPrefix)\(key)"
    }

    /// Get the saved custom order for entries in a directory.
    func customOrder(for parentPath: String) -> [String]? {
        UserDefaults.standard.stringArray(forKey: orderKey(for: parentPath))
    }

    /// Save a custom order for entries in a directory (by file name).
    func saveCustomOrder(_ names: [String], for parentPath: String) {
        // Filter out empty names to prevent corrupted order lists
        let cleaned = names.filter { !$0.isEmpty }
        UserDefaults.standard.set(cleaned, forKey: orderKey(for: parentPath))
    }

    /// Sort entries using custom order if available, falling back to directories-first then alphabetical.
    /// This is called from computed properties during rendering — it must be side-effect-free.
    /// Known entries are sorted by their saved order; unknown entries (e.g. newly created files)
    /// are appended at the end in default sort order. Deleted entries in the saved order are ignored.
    func sortedEntries(_ entries: [FileEntry], parentPath: String) -> [FileEntry] {
        guard let order = customOrder(for: parentPath), !order.isEmpty else {
            return defaultSortedEntries(entries)
        }

        let orderSet = Set(order)
        // Use uniquingKeysWith to handle potential duplicate names in saved order
        let orderMap = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        var known: [FileEntry] = []
        var unknown: [FileEntry] = []
        for entry in entries {
            if orderSet.contains(entry.name) {
                known.append(entry)
            } else {
                unknown.append(entry)
            }
        }

        known.sort { (orderMap[$0.name] ?? Int.max) < (orderMap[$1.name] ?? Int.max) }
        unknown.sort { defaultCompare($0, $1) }

        return known + unknown
    }

    /// Update the saved custom order to include new entries and prune deleted ones.
    /// Call after sortedEntries() to keep the persisted order in sync with current entries.
    func reconcileCustomOrder(for sortedEntries: [FileEntry], parentPath: String) {
        guard customOrder(for: parentPath) != nil else { return }
        saveCustomOrder(sortedEntries.map(\.name), for: parentPath)
    }

    /// Default sort: directories first, then alphabetical.
    func defaultSortedEntries(_ entries: [FileEntry]) -> [FileEntry] {
        entries.sorted { defaultCompare($0, $1) }
    }

    private func defaultCompare(_ a: FileEntry, _ b: FileEntry) -> Bool {
        if a.isDirectory != b.isDirectory {
            return a.isDirectory
        }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// Reorder an entry within its sibling list. Saves the new order.
    func reorderEntry(named name: String, toIndex newIndex: Int, inParent parentPath: String, siblings: [FileEntry]) {
        guard !name.isEmpty else { return }
        // Deduplicate names while preserving order — prevents corrupted saved orders
        var seen = Set<String>()
        var names = siblings.map(\.name).filter { !$0.isEmpty && seen.insert($0).inserted }
        guard let currentIndex = names.firstIndex(of: name) else { return }
        names.remove(at: currentIndex)
        let insertAt = min(newIndex, names.count)
        names.insert(name, at: insertAt)
        saveCustomOrder(names, for: parentPath)
    }

    private func sidebarReferenceKey(for workspacePath: String) -> String {
        "\(sidebarReferencePrefix)\(workspacePath)"
    }

    func sidebarReferencePaths(for workspacePath: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: sidebarReferenceKey(for: workspacePath)) ?? []
    }

    func saveSidebarReferencePaths(_ paths: [String], for workspacePath: String) {
        UserDefaults.standard.set(paths, forKey: sidebarReferenceKey(for: workspacePath))
    }

    func addSidebarReferencePath(_ path: String, for workspacePath: String) {
        var paths = sidebarReferencePaths(for: workspacePath)
        guard !paths.contains(path) else { return }
        paths.append(path)
        saveSidebarReferencePaths(paths, for: workspacePath)
    }

    func removeSidebarReferencePath(_ path: String, for workspacePath: String) {
        let filtered = sidebarReferencePaths(for: workspacePath).filter { $0 != path }
        saveSidebarReferencePaths(filtered, for: workspacePath)
    }

    // MARK: - Favorites

    private func favoritesKey(for workspacePath: String) -> String {
        "\(favoritesPrefix)\(workspacePath)"
    }

    nonisolated private static func isFirstPartySidebarFavoritePath(
        _ path: String,
        workspacePath: String
    ) -> Bool {
        let root = (workspacePath as NSString).standardizingPath
        let normalizedPath = (path as NSString).standardizingPath
        let dailyNotesPath = (root as NSString).appendingPathComponent("Daily Notes.md")
        let meetingsPath = (root as NSString).appendingPathComponent("Meetings.md")
        return normalizedPath == dailyNotesPath || normalizedPath == meetingsPath
    }

    func favoritePaths(for workspacePath: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: favoritesKey(for: workspacePath)) ?? []
    }

    func saveFavoritePaths(_ paths: [String], for workspacePath: String) {
        UserDefaults.standard.set(paths, forKey: favoritesKey(for: workspacePath))
    }

    func addFavoritePath(_ path: String, for workspacePath: String) {
        guard !Self.isFirstPartySidebarFavoritePath(path, workspacePath: workspacePath) else { return }
        var paths = favoritePaths(for: workspacePath)
        guard !paths.contains(path) else { return }
        paths.append(path)
        saveFavoritePaths(paths, for: workspacePath)
    }

    func removeFavoritePath(_ path: String, for workspacePath: String) {
        let filtered = favoritePaths(for: workspacePath).filter { $0 != path }
        saveFavoritePaths(filtered, for: workspacePath)
    }

    func isFavorite(_ path: String, for workspacePath: String) -> Bool {
        guard !Self.isFirstPartySidebarFavoritePath(path, workspacePath: workspacePath) else { return false }
        return favoritePaths(for: workspacePath).contains(path)
    }

    func reorderFavoritePath(
        _ path: String,
        toVisibleIndex newIndex: Int,
        visiblePaths: [String],
        for workspacePath: String
    ) {
        let storedPaths = favoritePaths(for: workspacePath)
        let visiblePathSet = Set(visiblePaths)
        var reorderedVisiblePaths = visiblePaths.filter { storedPaths.contains($0) }
        guard let oldIndex = reorderedVisiblePaths.firstIndex(of: path) else { return }

        reorderedVisiblePaths.remove(at: oldIndex)
        let adjustedIndex = max(0, min(newIndex - (oldIndex < newIndex ? 1 : 0), reorderedVisiblePaths.count))
        reorderedVisiblePaths.insert(path, at: adjustedIndex)

        let hiddenPaths = storedPaths.filter { storedPath in
            !visiblePathSet.contains(storedPath)
            && !Self.isFirstPartySidebarFavoritePath(storedPath, workspacePath: workspacePath)
        }
        saveFavoritePaths(reorderedVisiblePaths + hiddenPaths, for: workspacePath)
    }

    // MARK: - Trash (Recently Deleted)

    /// Metadata sidecar stored alongside each trashed item.
    struct TrashMeta: Codable {
        let originalPath: String
        let trashedAt: Date
    }

    /// An item in the trash.
    struct TrashItem: Identifiable {
        let id: String  // filename in .trash
        let name: String
        let originalPath: String
        let trashedAt: Date
        let trashPath: String
    }

    nonisolated private func trashDirectory(in workspace: String) -> String {
        (workspace as NSString).appendingPathComponent(".trash")
    }

    // MARK: - Agent Skills

    /// Scans ~/.claude/skills/ and ~/.claude/agents/ for skill/agent subfolders containing a .md file.
    /// Returns one FileEntry per skill, pointing at the first .md file found.
    /// Parses YAML frontmatter from each file to extract name and description.
    nonisolated func scanSkills() -> [FileEntry] {
        let home = NSHomeDirectory() as NSString
        let skillsRoot = home.appendingPathComponent(".claude/skills")
        let agentsRoot = home.appendingPathComponent(".claude/agents")
        let fm = FileManager.default

        var entries: [FileEntry] = []

        for root in [skillsRoot, agentsRoot] {
            guard let subfolders = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for folder in subfolders.sorted() {
                if folder.hasPrefix(".") { continue }
                let folderPath = (root as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
                guard let mdFile = files.first(where: { $0.hasSuffix(".md") }) else { continue }
                let mdPath = (folderPath as NSString).appendingPathComponent(mdFile)

                let displayName = parseSkillFrontmatterName(at: mdPath) ?? folder
                entries.append(FileEntry(
                    id: "skill:\(mdPath)",
                    name: displayName,
                    path: mdPath,
                    isDirectory: false,
                    kind: .skill,
                    icon: "sf:bolt.fill"
                ))
            }
        }
        return entries
    }

    /// Extracts the `name` field from YAML frontmatter in a SKILL.md file.
    nonisolated private func parseSkillFrontmatterName(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return nil }
        guard content.hasPrefix("---") else { return nil }
        let lines = content.components(separatedBy: "\n")
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if trimmed.hasPrefix("name:") {
                let value = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    func resolveFavorites(for workspacePath: String, fileTree: [FileEntry]) -> [FileEntry] {
        let storedPaths = favoritePaths(for: workspacePath)
        let userFavoritePaths = storedPaths.filter {
            !Self.isFirstPartySidebarFavoritePath($0, workspacePath: workspacePath)
        }
        var resolvedPaths: [String] = []
        let entries = userFavoritePaths.compactMap { path -> FileEntry? in
            if let entry = findEntry(path: path, in: fileTree) {
                resolvedPaths.append(path)
                return FileEntry(
                    id: "favorite:\(path)",
                    name: entry.name,
                    path: entry.path,
                    isDirectory: entry.isDirectory,
                    kind: entry.kind,
                    icon: entry.icon,
                    children: entry.children
                )
            }
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            resolvedPaths.append(path)
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
            let isDb = FileManager.default.fileExists(atPath: schemaPath)
            let kind: TabKind = isDb ? .database : .page
            let name: String
            if isDb, let data = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dbName = json["name"] as? String {
                name = dbName
            } else {
                name = (path as NSString).lastPathComponent
            }
            return FileEntry(
                id: "favorite:\(path)",
                name: name,
                path: path,
                isDirectory: isDirectory.boolValue,
                kind: kind
            )
        }
        if resolvedPaths != storedPaths {
            saveFavoritePaths(resolvedPaths, for: workspacePath)
        }
        return entries
    }

    func findEntry(path: String, in entries: [FileEntry]) -> FileEntry? {
        for entry in entries {
            if entry.path == path { return entry }
            if let children = entry.children, let found = findEntry(path: path, in: children) { return found }
        }
        return nil
    }

    func databaseDisplayName(at path: String) -> String? {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["name"] as? String
    }

    // MARK: - Path Rewriting

    nonisolated func rewritePathsInFile(at filePath: String, oldBase: String, newBase: String) {
        guard filePath.hasSuffix(".md"),
              oldBase != newBase,
              var content = try? String(contentsOfFile: filePath, encoding: .utf8),
              content.contains(oldBase) else { return }
        content = content.replacingOccurrences(of: oldBase, with: newBase)
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    nonisolated func rewritePathsRecursively(in directory: String, oldBase: String, newBase: String) {
        guard oldBase != newBase,
              FileManager.default.fileExists(atPath: directory) else { return }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        for item in items {
            let fullPath = (directory as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
            if isDir.boolValue {
                rewritePathsRecursively(in: fullPath, oldBase: oldBase, newBase: newBase)
            } else {
                rewritePathsInFile(at: fullPath, oldBase: oldBase, newBase: newBase)
            }
        }
    }

    // MARK: - Wiki Link Updates

    nonisolated func updateWikiLinksOnDisk(in directory: String, oldLink: String, newLink: String, excludingPaths: Set<String>) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return }
        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(".md") else { continue }
            let fullPath = (directory as NSString).appendingPathComponent(relativePath)
            guard !excludingPaths.contains(fullPath) else { continue }
            guard var content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }
            guard content.contains(oldLink) else { continue }
            content = content.replacingOccurrences(of: oldLink, with: newLink)
            try? content.write(toFile: fullPath, atomically: true, encoding: .utf8)
        }
    }

    /// Move a file (and companion folder) to `.trash/` instead of permanently deleting.
    func trashFile(at path: String, workspace: String) throws {
        let trashDir = trashDirectory(in: workspace)
        if !fileManager.fileExists(atPath: trashDir) {
            try fileManager.createDirectory(atPath: trashDir, withIntermediateDirectories: true)
        }

        let name = (path as NSString).lastPathComponent
        let timestamp = Int(Date.now.timeIntervalSince1970)
        let trashName = "\(timestamp)_\(name)"
        let trashPath = (trashDir as NSString).appendingPathComponent(trashName)

        try fileManager.moveItem(atPath: path, toPath: trashPath)

        // Move companion folder if it exists
        let companion = companionFolderPath(for: path)
        if fileManager.fileExists(atPath: companion) {
            let companionName = (companion as NSString).lastPathComponent
            let trashCompanionName = "\(timestamp)_\(companionName)"
            let trashCompanionPath = (trashDir as NSString).appendingPathComponent(trashCompanionName)
            try fileManager.moveItem(atPath: companion, toPath: trashCompanionPath)
        }

        // Write metadata sidecar
        let meta = TrashMeta(originalPath: path, trashedAt: .now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metaData = try encoder.encode(meta)
        let metaPath = trashPath + ".meta.json"
        try metaData.write(to: URL(fileURLWithPath: metaPath), options: .atomic)

        Log.fileSystem.info("Trashed file: \(name)")
        SentryBreadcrumbs.add(Breadcrumb(level: .info, category: "file.trash"))
    }

    /// List all items in the trash.
    nonisolated func listTrash(in workspace: String) -> [TrashItem] {
        let trashDir = trashDirectory(in: workspace)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: trashDir) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return contents.compactMap { name -> TrashItem? in
            guard !name.hasSuffix(".meta.json") else { return nil }
            // Skip companion folders in trash (they'll be restored with their page)
            let fullPath = (trashDir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue,
               !isDatabaseFolder(at: fullPath) {
                return nil
            }

            let metaPath = fullPath + ".meta.json"
            guard let metaData = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                  let meta = try? decoder.decode(TrashMeta.self, from: metaData) else {
                return nil
            }

            let displayName = (meta.originalPath as NSString).lastPathComponent
            return TrashItem(
                id: name,
                name: displayName,
                originalPath: meta.originalPath,
                trashedAt: meta.trashedAt,
                trashPath: fullPath
            )
        }
        .sorted { $0.trashedAt > $1.trashedAt }
    }

    /// Restore a trashed item to its original location.
    func restoreFromTrash(_ item: TrashItem, workspace: String) throws {
        let destDir = (item.originalPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: destDir) {
            try fileManager.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        }

        // Handle name conflicts
        var destPath = item.originalPath
        if fileManager.fileExists(atPath: destPath) {
            let dir = (destPath as NSString).deletingLastPathComponent
            let name = (destPath as NSString).lastPathComponent
            let baseName = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            if ext.isEmpty {
                destPath = uniqueDirectoryPath(in: dir, base: baseName)
            } else {
                let newName = uniqueFilename(in: dir, base: baseName, ext: ext)
                destPath = (dir as NSString).appendingPathComponent(newName)
            }
        }

        try fileManager.moveItem(atPath: item.trashPath, toPath: destPath)

        // Restore companion folder if present
        if let companionPath = trashCompanionPath(for: item, workspace: workspace) {
            let destCompanion = companionFolderPath(for: destPath)
            try? fileManager.moveItem(atPath: companionPath, toPath: destCompanion)
        }

        // Clean up metadata
        let metaPath = item.trashPath + ".meta.json"
        try? fileManager.removeItem(atPath: metaPath)

        Log.fileSystem.info("Restored from trash: \(item.name)")
    }

    /// Permanently delete a single item from the trash.
    func deletePermanently(_ item: TrashItem, workspace: String) throws {
        try fileManager.removeItem(atPath: item.trashPath)
        let metaPath = item.trashPath + ".meta.json"
        try? fileManager.removeItem(atPath: metaPath)

        // Delete companion folder if present
        if let companionPath = trashCompanionPath(for: item, workspace: workspace) {
            try? fileManager.removeItem(atPath: companionPath)
            let companionMeta = companionPath + ".meta.json"
            try? fileManager.removeItem(atPath: companionMeta)
        }

        Log.fileSystem.info("Permanently deleted: \(item.name)")
    }

    /// Empty the entire trash.
    func emptyTrash(in workspace: String) throws {
        let trashDir = trashDirectory(in: workspace)
        if fileManager.fileExists(atPath: trashDir) {
            try fileManager.removeItem(atPath: trashDir)
        }
        Log.fileSystem.info("Emptied trash")
    }

    /// Purge items older than 30 days. Call on app launch.
    nonisolated func purgeOldTrash(in workspace: String) {
        let items = listTrash(in: workspace)
        let cutoff = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        let fm = FileManager.default
        for item in items where item.trashedAt < cutoff {
            try? fm.removeItem(atPath: item.trashPath)
            try? fm.removeItem(atPath: item.trashPath + ".meta.json")
            if let companionPath = trashCompanionPathNonisolated(for: item, workspace: workspace, fm: fm) {
                try? fm.removeItem(atPath: companionPath)
                try? fm.removeItem(atPath: companionPath + ".meta.json")
            }
        }
    }

    // MARK: - Helpers

    /// Resolve the companion folder path for a trashed item (if it exists in trash).
    private func trashCompanionPath(for item: TrashItem, workspace: String) -> String? {
        let trashDir = trashDirectory(in: workspace)
        let prefix = String(item.id.prefix(while: { $0 != "_" })) + "_"
        let companionBase = companionFolderPath(for: item.name)
        let path = (trashDir as NSString).appendingPathComponent(prefix + companionBase)
        return fileManager.fileExists(atPath: path) ? path : nil
    }

    nonisolated private func trashCompanionPathNonisolated(for item: TrashItem, workspace: String, fm: FileManager) -> String? {
        let trashDir = (workspace as NSString).appendingPathComponent(".trash")
        let prefix = String(item.id.prefix(while: { $0 != "_" })) + "_"
        let companionBase = companionFolderPath(for: item.name)
        let path = (trashDir as NSString).appendingPathComponent(prefix + companionBase)
        return fm.fileExists(atPath: path) ? path : nil
    }

    nonisolated private func companionFolderPath(for mdPath: String) -> String {
        guard mdPath.hasSuffix(".md") else { return mdPath }
        return String(mdPath.dropLast(3))
    }

    nonisolated private func isCompanionFolder(_ folderName: String, siblings: Set<String>) -> Bool {
        siblings.contains("\(folderName).md")
    }

    nonisolated func isDatabaseFolder(at path: String) -> Bool {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        return FileManager.default.fileExists(atPath: schemaPath)
    }

    func updateDatabaseDisplayName(at path: String, name: String) throws {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        let data = try Data(contentsOf: URL(fileURLWithPath: schemaPath))
        var schema = try JSONDecoder().decode(DatabaseSchema.self, from: data)
        schema.name = name

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let updated = try encoder.encode(schema)
        try updated.write(to: URL(fileURLWithPath: schemaPath), options: .atomic)
    }

    nonisolated private func parseIconFromFile(at path: String) -> String? {
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var buffer = [UInt8](repeating: 0, count: 256)
        let byteCount = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return Darwin.read(fd, baseAddress, rawBuffer.count)
        }

        guard byteCount > 0 else { return nil }
        guard let head = String(bytes: buffer.prefix(byteCount), encoding: .utf8) else { return nil }
        // Manual prefix scan — avoids regex allocation per file
        guard let startRange = head.range(of: "<!-- icon:") else { return nil }
        let afterPrefix = startRange.upperBound
        guard let endRange = head.range(of: " -->", range: afterPrefix..<head.endIndex) else { return nil }
        let inner = head[afterPrefix..<endRange.lowerBound].trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? nil : inner
    }

    private func loadRecentWorkspaces() {
        recentWorkspaces = UserDefaults.standard.stringArray(forKey: recentWorkspacesKey) ?? []
    }

    private func addToRecentWorkspaces(_ path: String) {
        recentWorkspaces.removeAll { $0 == path }
        recentWorkspaces.insert(path, at: 0)
        if recentWorkspaces.count > maxRecentWorkspaces {
            recentWorkspaces = Array(recentWorkspaces.prefix(maxRecentWorkspaces))
        }
        UserDefaults.standard.set(recentWorkspaces, forKey: recentWorkspacesKey)
    }

    private func uniqueFilename(in directory: String, base: String, ext: String) -> String {
        var name = "\(base).\(ext)"
        var counter = 2
        while fileManager.fileExists(atPath: (directory as NSString).appendingPathComponent(name)) {
            name = "\(base) \(counter).\(ext)"
            counter += 1
        }
        return name
    }

    private func uniqueDirectoryPath(in directory: String, base: String) -> String {
        var folderName = base
        var counter = 2
        var path = (directory as NSString).appendingPathComponent(folderName)
        while fileManager.fileExists(atPath: path) {
            folderName = "\(base) \(counter)"
            path = (directory as NSString).appendingPathComponent(folderName)
            counter += 1
        }
        return path
    }

    private func sanitizeDatabaseFolderName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Untitled Database" : trimmed
        let sanitized = fallback.replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
        return sanitized.isEmpty ? "Untitled Database" : sanitized
    }

    // MARK: - MCP Servers

    nonisolated func parseMCPServers() -> [MCPServerInfo] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = (home as NSString).appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else {
            return []
        }
        return servers.compactMap { key, value in
            guard let config = value as? [String: Any],
                  let command = config["command"] as? String else { return nil }
            let args = (config["args"] as? [String]) ?? []
            let displayCommand = args.isEmpty ? command : "\(command) \(args.joined(separator: " "))"
            return MCPServerInfo(name: key, command: displayCommand)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - App Data Directories (Icons & Covers)

    private static let appSupportBase: URL = {
        guard let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory is unavailable for the current user domain.")
        }
        return url
    }()

    private static var appSupportDirectory: String {
        appSupportBase.appendingPathComponent("Bugbook").path
    }

    static var iconsDirectory: String {
        let path = (appSupportDirectory as NSString).appendingPathComponent("icons")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    static var coversDirectory: String {
        let path = (appSupportDirectory as NSString).appendingPathComponent("covers")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    /// Copy an image file to the icons directory. Returns the saved file path, or nil on failure.
    static func saveIcon(from sourceURL: URL) -> String? {
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destPath = (iconsDirectory as NSString).appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(atPath: sourceURL.path, toPath: destPath)
            return destPath
        } catch {
            return nil
        }
    }

    /// Copy an image file to the covers directory. Returns the saved file path, or nil on failure.
    static func saveCover(from sourceURL: URL) -> String? {
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destPath = (coversDirectory as NSString).appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(atPath: sourceURL.path, toPath: destPath)
            return destPath
        } catch {
            return nil
        }
    }
}
