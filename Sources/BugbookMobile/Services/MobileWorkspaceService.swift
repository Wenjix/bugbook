import Foundation

@MainActor
final class MobileWorkspaceService: ObservableObject {
    @Published var workspacePath: String = ""
    @Published var files: [MobileNoteFile] = []

    private let fileManager = FileManager.default

    init() {
        let path = defaultWorkspacePath()
        if !fileManager.fileExists(atPath: path) {
            try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        workspacePath = path
        refreshFiles()
    }

    func refreshFiles() {
        guard !workspacePath.isEmpty else {
            files = []
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: workspacePath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            files = []
            return
        }

        var notes: [MobileNoteFile] = []

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }

            let name = url.lastPathComponent
            if name.hasPrefix("_") { continue }

            let displayName = String(name.dropLast(3))
            notes.append(MobileNoteFile(path: url.path, name: displayName))
        }

        files = notes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

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

    private func defaultWorkspacePath() -> String {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Bugbook").path
    }
}
