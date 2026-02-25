import Foundation
import AppKit
import BugbookCore

@MainActor
class FileSystemService: ObservableObject {
    @Published var workspacePath: String?
    @Published var recentWorkspaces: [String] = []

    private let fileManager = FileManager.default
    private let recentWorkspacesKey = "recentWorkspaces"
    private let maxRecentWorkspaces = 20
    private let customOrderPrefix = "sidebarOrder_"

    init() {
        loadRecentWorkspaces()
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
        let docs = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Bugbook")
        return docs.path
    }

    // MARK: - File Tree Building

    func buildFileTree(at path: String, depth: Int = 0) -> [FileEntry] {
        guard depth < 5 else { return [] }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return []
        }

        // Collect sibling names for companion folder detection
        let siblingNames = Set(contents)

        var folders: [FileEntry] = []
        var files: [FileEntry] = []

        for name in contents {
            if name.hasPrefix(".") { continue }
            if name == "_schema.json" || name == "_index.json" { continue }

            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                if isDatabaseFolder(at: fullPath) {
                    // Database folder - read display name from _schema.json
                    var dbName = name
                    let schemaPath = (fullPath as NSString).appendingPathComponent("_schema.json")
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let schemaName = json["name"] as? String {
                        dbName = schemaName
                    }
                    // Treat database as a non-expandable item (like TS version)
                    folders.append(FileEntry(
                        id: fullPath,
                        name: dbName,
                        path: fullPath,
                        isDirectory: false,
                        isDatabase: true,
                        icon: nil,
                        children: nil
                    ))
                } else if isCompanionFolder(name, siblings: siblingNames) {
                    // Companion folder - skip, its contents are handled by the parent .md file
                    continue
                } else {
                    // Regular directory - flatten into parent (no visible folders)
                    let children = buildFileTree(at: fullPath, depth: depth + 1)
                    for child in children {
                        if child.isDatabase {
                            folders.append(child)
                        } else {
                            files.append(child)
                        }
                    }
                }
            } else if name.hasSuffix(".md") {
                let isDbFile = name.hasSuffix(".db.md")
                let icon = parseIconFromFile(at: fullPath)

                // Check for companion folder children
                let companionPath = companionFolderPath(for: fullPath)
                var children: [FileEntry]?
                if fileManager.fileExists(atPath: companionPath) {
                    children = buildFileTree(at: companionPath, depth: depth + 1)
                }

                files.append(FileEntry(
                    id: fullPath,
                    name: name,
                    path: fullPath,
                    isDirectory: false,
                    isDatabase: isDbFile,
                    icon: icon,
                    children: children
                ))
            }
        }

        // Sort: folders first (alphabetical), then files (alphabetical)
        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return folders + files
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
        try "# \n\n".write(toFile: filePath, atomically: true, encoding: .utf8)
        return filePath
    }

    func createFolder(at path: String) throws {
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func renameFile(from oldPath: String, to newPath: String) throws {
        try fileManager.moveItem(atPath: oldPath, toPath: newPath)
    }

    func deleteFile(at path: String) throws {
        try fileManager.removeItem(atPath: path)
        // Also remove companion folder if it exists
        let companion = companionFolderPath(for: path)
        if fileManager.fileExists(atPath: companion) {
            try fileManager.removeItem(atPath: companion)
        }
    }

    func duplicateFile(at path: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let dir = (path as NSString).deletingLastPathComponent
        let originalName = (path as NSString).lastPathComponent
        let baseName = (originalName as NSString).deletingPathExtension

        let newFilename = uniqueFilename(in: dir, base: "\(baseName) copy", ext: "md")
        let newPath = (dir as NSString).appendingPathComponent(newFilename)
        try content.write(toFile: newPath, atomically: true, encoding: .utf8)
        return newPath
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

    func createDatabase(in directory: String, name: String) throws -> String {
        let folderPath = (directory as NSString).appendingPathComponent(name)
        try fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true)

        let defaultViewId = "view_table"
        let now = ISO8601DateFormatter().string(from: Date())
        let schema = DatabaseSchema(
            id: "db_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))",
            name: name,
            version: 1,
            properties: [
                PropertyDefinition(id: "prop_title", name: "Name", type: .title),
                PropertyDefinition(id: "prop_tags", name: "Tags", type: .multiSelect, config: PropertyConfig(options: [])),
                PropertyDefinition(id: "prop_status", name: "Status", type: .select, config: PropertyConfig(options: [
                    SelectOption(id: "opt_not_started", name: "Not Started", color: "gray"),
                    SelectOption(id: "opt_in_progress", name: "In Progress", color: "blue"),
                    SelectOption(id: "opt_done", name: "Done", color: "green"),
                ])),
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
        let match = content[range]
        // Extract between "<!-- icon:" and " -->"
        let start = match.index(match.startIndex, offsetBy: 10)
        let end = match.index(match.endIndex, offsetBy: -4)
        guard start < end else { return nil }
        return String(match[start..<end])
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
        UserDefaults.standard.set(names, forKey: orderKey(for: parentPath))
    }

    /// Sort entries using custom order if available, falling back to directories-first then alphabetical.
    func sortedEntries(_ entries: [FileEntry], parentPath: String) -> [FileEntry] {
        guard let order = customOrder(for: parentPath), !order.isEmpty else {
            return defaultSortedEntries(entries)
        }

        let orderMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return entries.sorted { a, b in
            let idxA = orderMap[a.name]
            let idxB = orderMap[b.name]
            switch (idxA, idxB) {
            case let (.some(ia), .some(ib)):
                return ia < ib
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return defaultCompare(a, b)
            }
        }
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
        var names = siblings.map(\.name)
        guard let currentIndex = names.firstIndex(of: name) else { return }
        names.remove(at: currentIndex)
        let insertAt = min(newIndex, names.count)
        names.insert(name, at: insertAt)
        saveCustomOrder(names, for: parentPath)
    }

    // MARK: - Helpers

    private func companionFolderPath(for mdPath: String) -> String {
        guard mdPath.hasSuffix(".md") else { return mdPath }
        return String(mdPath.dropLast(3))
    }

    private func isCompanionFolder(_ folderName: String, siblings: Set<String>) -> Bool {
        siblings.contains("\(folderName).md")
    }

    private func isDatabaseFolder(at path: String) -> Bool {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        return fileManager.fileExists(atPath: schemaPath)
    }

    private func parseIconFromFile(at path: String) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parseIcon(from: content)
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

    // MARK: - App Data Directories (Icons & Covers)

    private static var appSupportDirectory: String {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BugbookSwift").path
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
