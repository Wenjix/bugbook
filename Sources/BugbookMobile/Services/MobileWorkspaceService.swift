import Foundation
import Observation
import BugbookCore

@MainActor
@Observable final class MobileWorkspaceService {
    var workspacePath: String = ""
    var files: [MobileNoteFile] = []
    var isICloudAvailable: Bool = false

    private let fileManager = FileManager.default
    private let maxTreeDepth = 10

    init() {
        let path = resolveWorkspacePath()
        if !fileManager.fileExists(atPath: path) {
            try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        workspacePath = path
        refreshFiles()
    }

    // MARK: - Workspace Resolution

    private func resolveWorkspacePath() -> String {
        // Check the iCloud ubiquity container (iCloud.com.maxforsey.Bugbook)
        // On Mac: ~/Library/Mobile Documents/iCloud~com~maxforsey~Bugbook/Documents/Bugbook
        // On iOS: synced automatically by iCloud
        if let containerURL = fileManager.url(forUbiquityContainerIdentifier: "iCloud.com.bugbook.app") {
            let bugbookDir = containerURL.appendingPathComponent("Documents/Bugbook")
            isICloudAvailable = true
            return bugbookDir.path
        }

        isICloudAvailable = false
        return localWorkspacePath()
    }

    private func localWorkspacePath() -> String {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Bugbook").path
    }

    // MARK: - File Tree Building

    func refreshFiles() {
        guard !workspacePath.isEmpty else {
            files = []
            return
        }
        files = buildTree(at: workspacePath, preserveFolders: false, depth: 0)
    }

    func buildHierarchicalFileTree() -> [MobileNoteFile] {
        buildTree(at: workspacePath, preserveFolders: true, depth: 0)
    }

    private func buildTree(at path: String, preserveFolders: Bool, depth: Int) -> [MobileNoteFile] {
        guard depth < maxTreeDepth else { return [] }
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }

        let siblingNames = Set(contents)
        var folders: [MobileNoteFile] = []
        var noteFiles: [MobileNoteFile] = []

        for name in contents {
            if name.hasPrefix(".") { continue }
            if name == "_schema.json" || name == "_index.json" { continue }
            if name == "Daily Notes" || name == "Templates" { continue }

            let fullPath = (path as NSString).appendingPathComponent(name)
            if WorkspacePathRules.shouldIgnoreAbsolutePath(fullPath) { continue }

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                if isDatabaseFolder(at: fullPath) {
                    var dbName = name
                    let schemaPath = (fullPath as NSString).appendingPathComponent("_schema.json")
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let schemaName = json["name"] as? String {
                        dbName = schemaName
                    }
                    folders.append(MobileNoteFile(
                        path: fullPath,
                        name: dbName,
                        isDatabase: true
                    ))
                } else if isCompanionFolder(name, siblings: siblingNames) {
                    continue
                } else {
                    let children = buildTree(at: fullPath, preserveFolders: preserveFolders, depth: depth + 1)
                    if preserveFolders {
                        folders.append(MobileNoteFile(
                            path: fullPath,
                            name: name,
                            isDirectory: true,
                            children: children
                        ))
                    } else {
                        for child in children {
                            if child.isDatabase {
                                folders.append(child)
                            } else {
                                noteFiles.append(child)
                            }
                        }
                    }
                }
            } else if name.hasSuffix(".md") {
                let icon = parseIconFromFile(at: fullPath)
                let companionPath = companionFolderPath(for: fullPath)
                var children: [MobileNoteFile]?
                if fileManager.fileExists(atPath: companionPath) {
                    children = buildTree(at: companionPath, preserveFolders: preserveFolders, depth: depth + 1)
                }

                let modDate = (try? fileManager.attributesOfItem(atPath: fullPath)[.modificationDate]) as? Date

                noteFiles.append(MobileNoteFile(
                    path: fullPath,
                    name: String(name.dropLast(3)),
                    isDatabase: name.hasSuffix(".db.md"),
                    children: children,
                    icon: icon,
                    modifiedAt: modDate
                ))
            }
        }

        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        noteFiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return folders + noteFiles
    }

    // MARK: - Daily Notes

    func dailyNotePath() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = formatter.string(from: Date()) + ".md"
        let folder = (workspacePath as NSString).appendingPathComponent("Daily Notes")
        return (folder as NSString).appendingPathComponent(filename)
    }

    @discardableResult
    func openOrCreateDailyNote() -> MobileNoteFile? {
        let path = dailyNotePath()
        let folder = (path as NSString).deletingLastPathComponent

        if !fileManager.fileExists(atPath: folder) {
            try? fileManager.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }

        if !fileManager.fileExists(atPath: path) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            let title = formatter.string(from: Date())
            try? "# \(title)\n\n".write(toFile: path, atomically: true, encoding: .utf8)
        }

        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return MobileNoteFile(path: path, name: name)
    }

    // MARK: - Recent Files

    func recentFiles(limit: Int = 10) -> [MobileNoteFile] {
        let allFiles = collectAllFiles(at: workspacePath)
        let sorted = allFiles
            .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        return Array(sorted.prefix(limit))
    }

    private func collectAllFiles(at path: String) -> [MobileNoteFile] {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [MobileNoteFile] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let name = url.lastPathComponent
            if name.hasPrefix("_") { continue }

            let relativePath = String(url.path.dropFirst(workspacePath.count))
            if WorkspacePathRules.shouldIgnoreRelativePath(relativePath) { continue }

            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

            results.append(MobileNoteFile(
                path: url.path,
                name: String(name.dropLast(3)),
                modifiedAt: modDate
            ))
        }
        return results
    }

    // MARK: - File Operations

    func loadFile(at path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    func saveFile(at path: String, content: String) {
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    @discardableResult
    func createNote(named baseName: String = "New Note") -> MobileNoteFile? {
        let sanitized = baseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
        let rootName = sanitized.isEmpty ? "New Note" : sanitized

        var index = 1
        var candidate = "\(rootName).md"
        var path = (workspacePath as NSString).appendingPathComponent(candidate)

        while fileManager.fileExists(atPath: path) {
            index += 1
            candidate = "\(rootName) \(index).md"
            path = (workspacePath as NSString).appendingPathComponent(candidate)
        }

        do {
            try "# \(rootName)\n\n".write(toFile: path, atomically: true, encoding: .utf8)
            let note = MobileNoteFile(path: path, name: String(candidate.dropLast(3)))
            refreshFiles()
            return note
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func isDatabaseFolder(at path: String) -> Bool {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        return fileManager.fileExists(atPath: schemaPath)
    }

    private func isCompanionFolder(_ folderName: String, siblings: Set<String>) -> Bool {
        siblings.contains("\(folderName).md")
    }

    private func companionFolderPath(for mdPath: String) -> String {
        guard mdPath.hasSuffix(".md") else { return mdPath }
        return String(mdPath.dropLast(3))
    }

    func loadFileIcon(at path: String) -> String? { parseIconFromFile(at: path) }

    private func parseIconFromFile(at path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { fh.closeFile() }
        let data = fh.readData(ofLength: 512)
        guard let head = String(data: data, encoding: .utf8) else { return nil }
        guard let range = head.range(of: "<!-- icon:(.*?) -->", options: .regularExpression) else { return nil }
        let match = String(head[range])
        let inner = match.dropFirst(10).dropLast(4).trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? nil : inner
    }
}
