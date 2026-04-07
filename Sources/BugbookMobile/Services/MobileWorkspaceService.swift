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
    private let hiddenTreeFolders: Set<String> = ["attachments", "inbox", "raw"]

    init() {
        // Start with local path immediately so the UI renders
        let localPath = localWorkspacePath()
        if !fileManager.fileExists(atPath: localPath) {
            try? fileManager.createDirectory(atPath: localPath, withIntermediateDirectories: true)
        }
        workspacePath = localPath

        // Resolve iCloud in the background — url(forUbiquityContainerIdentifier:) can block
        Task.detached(priority: .utility) { [weak self] in
            guard let iCloudPath = Self.resolveICloudWorkspacePath() else { return }
            guard let self else { return }
            await self.applyResolvedICloudWorkspacePath(iCloudPath)
        }
    }

    // MARK: - Workspace Resolution

    private func localWorkspacePath() -> String {
        WorkspaceResolver.localFallbackWorkspacePath()
    }

    private nonisolated static func resolveICloudWorkspacePath() -> String? {
        WorkspaceResolver.resolveICloudWorkspacePath()
    }

    private func applyResolvedICloudWorkspacePath(_ iCloudPath: String) {
        workspacePath = iCloudPath
        isICloudAvailable = true
        Task { await refreshFilesAsync() }
    }

    // MARK: - File Tree Building

    func refreshFiles() {
        Task { await refreshFilesAsync() }
    }

    func refreshFilesAsync() async {
        guard !workspacePath.isEmpty else {
            files = []
            return
        }
        let path = workspacePath
        let built = await Task.detached(priority: .userInitiated) {
            Self.buildTreeStatic(at: path, preserveFolders: false, depth: 0)
        }.value
        files = built
    }

    func buildHierarchicalFileTree() async -> [MobileNoteFile] {
        let path = workspacePath
        return await Task.detached(priority: .userInitiated) {
            Self.buildTreeStatic(at: path, preserveFolders: true, depth: 0)
        }.value
    }

    nonisolated private static func buildTreeStatic(at path: String, preserveFolders: Bool, depth: Int) -> [MobileNoteFile] {
        buildTreeImpl(at: path, preserveFolders: preserveFolders, depth: depth,
                      hiddenTreeFolders: ["attachments", "inbox", "raw"], maxTreeDepth: 10)
    }

    nonisolated private static func buildTreeImpl(at path: String, preserveFolders: Bool, depth: Int,
                                      hiddenTreeFolders: Set<String>, maxTreeDepth: Int) -> [MobileNoteFile] {
        let fm = FileManager.default
        guard depth < maxTreeDepth else { return [] }
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        let siblingNames = Set(contents)
        var folders: [MobileNoteFile] = []
        var noteFiles: [MobileNoteFile] = []

        for name in contents {
            if name.hasPrefix(".") || name.hasPrefix("_") { continue }
            if name == "Daily Notes" || name == "Templates" { continue }
            if hiddenTreeFolders.contains(name.lowercased()) { continue }
            // Filter internal/legacy folders that shouldn't appear in the file tree
            if ["assets", "logseq", "journals", "pages", "whiteboards"].contains(name) { continue }

            let fullPath = (path as NSString).appendingPathComponent(name)
            if WorkspacePathRules.shouldIgnoreAbsolutePath(fullPath) { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                if isDatabaseFolderStatic(at: fullPath, fm: fm) {
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
                } else if siblingNames.contains("\(name).md") {
                    // companion folder — skip
                    continue
                } else {
                    let children = buildTreeImpl(at: fullPath, preserveFolders: preserveFolders, depth: depth + 1,
                                                 hiddenTreeFolders: hiddenTreeFolders, maxTreeDepth: maxTreeDepth)
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
                let icon = parseIconFromFileStatic(at: fullPath)
                let companionPath = String(fullPath.dropLast(3))
                var children: [MobileNoteFile]?
                if fm.fileExists(atPath: companionPath) {
                    children = buildTreeImpl(at: companionPath, preserveFolders: preserveFolders, depth: depth + 1,
                                             hiddenTreeFolders: hiddenTreeFolders, maxTreeDepth: maxTreeDepth)
                }

                let modDate = (try? fm.attributesOfItem(atPath: fullPath)[.modificationDate]) as? Date

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

    nonisolated private static func isDatabaseFolderStatic(at path: String, fm: FileManager) -> Bool {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        return fm.fileExists(atPath: schemaPath)
    }

    nonisolated private static func parseIconFromFileStatic(at path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { fh.closeFile() }
        let data = fh.readData(ofLength: 512)
        guard let head = String(data: data, encoding: .utf8) else { return nil }
        guard let range = head.range(of: "<!-- icon:(.*?) -->", options: .regularExpression) else { return nil }
        let match = String(head[range])
        let inner = match.dropFirst(10).dropLast(4).trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? nil : inner
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

    func recentFiles(limit: Int = 10) async -> [MobileNoteFile] {
        let path = workspacePath
        return await Task.detached(priority: .userInitiated) {
            let allFiles = Self.collectAllFilesStatic(at: path)
            let sorted = allFiles.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
            return Array(sorted.prefix(limit))
        }.value
    }

    nonisolated private static func collectAllFilesStatic(at path: String) -> [MobileNoteFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [MobileNoteFile] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let name = url.lastPathComponent
            if name.hasPrefix("_") { continue }

            let relativePath = String(url.path.dropFirst(path.count))
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
