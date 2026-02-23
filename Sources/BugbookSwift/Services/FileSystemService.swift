import Foundation
import AppKit

@MainActor
class FileSystemService: ObservableObject {
    @Published var workspacePath: String?
    @Published var recentWorkspaces: [String] = []

    private let fileManager = FileManager.default
    private let recentWorkspacesKey = "recentWorkspaces"
    private let maxRecentWorkspaces = 20

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
            if name == "_schema.md" || name == "_index.json" { continue }

            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                if isDatabaseFolder(at: fullPath) {
                    // Database folder - read display name from schema
                    var dbName = name
                    let schemaPath = (fullPath as NSString).appendingPathComponent("_schema.md")
                    if let schemaContent = try? String(contentsOfFile: schemaPath, encoding: .utf8) {
                        if schemaContent.hasPrefix("---") {
                            if let endIdx = schemaContent.range(of: "\n---", range: schemaContent.index(schemaContent.startIndex, offsetBy: 3)..<schemaContent.endIndex) {
                                let yamlStr = String(schemaContent[schemaContent.index(schemaContent.startIndex, offsetBy: 4)..<endIdx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if let data = yamlStr.data(using: .utf8),
                                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let schemaName = parsed["name"] as? String {
                                    dbName = schemaName
                                }
                            }
                        }
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
                    // Regular directory - recurse
                    let children = buildFileTree(at: fullPath, depth: depth + 1)
                    folders.append(FileEntry(
                        id: fullPath,
                        name: name,
                        path: fullPath,
                        isDirectory: true,
                        isDatabase: false,
                        icon: nil,
                        children: children
                    ))
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

    func createNewFile(in directory: String, name: String = "Untitled") throws -> String {
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

        let parentName = (pagePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
        try "# \(sanitizedName)\n<!-- parent:\(parentName) -->\n\n".write(toFile: filePath, atomically: true, encoding: .utf8)
        return filePath
    }

    func createDatabase(in directory: String, name: String) throws -> String {
        let folderPath = (directory as NSString).appendingPathComponent(name)
        try fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true)

        // Write _schema.md with default JSON schema in YAML frontmatter
        let schemaContent = """
        ---
        {"name":"\(name)","properties":{"Name":{"type":"text","isPrimary":true},"Tags":{"type":"multi_select","options":[]},"Status":{"type":"select","options":["Not Started","In Progress","Done"]}}}
        ---
        """
        let schemaPath = (folderPath as NSString).appendingPathComponent("_schema.md")
        try schemaContent.write(toFile: schemaPath, atomically: true, encoding: .utf8)

        // Write empty _index.json
        let indexPath = (folderPath as NSString).appendingPathComponent("_index.json")
        try "[]".write(toFile: indexPath, atomically: true, encoding: .utf8)

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
                // Folder segment - link to parent page .md if it exists
                let parentPagePath = (currentPath as NSString).deletingLastPathComponent
                let pagePath = (parentPagePath as NSString).appendingPathComponent("\(part).md")
                breadcrumbs.append(BreadcrumbItem(
                    id: currentPath,
                    name: part,
                    path: pagePath,
                    icon: parseIconFromFile(at: pagePath)
                ))
            } else {
                // The file itself
                let displayName = part.hasSuffix(".md") ? String(part.dropLast(3)) : part
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

    // MARK: - Helpers

    private func companionFolderPath(for mdPath: String) -> String {
        guard mdPath.hasSuffix(".md") else { return mdPath }
        return String(mdPath.dropLast(3))
    }

    private func isCompanionFolder(_ folderName: String, siblings: Set<String>) -> Bool {
        siblings.contains("\(folderName).md")
    }

    private func isDatabaseFolder(at path: String) -> Bool {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.md")
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
}
