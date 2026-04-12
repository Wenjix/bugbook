import ArgumentParser
import Foundation

struct Context: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "context",
        abstract: "Gather context by traversing wikilinks from a page, or read folder context"
    )

    @OptionGroup var options: Dahso.Options

    @Argument(help: "Page path, relative path, or page name (omit when using --folder)")
    var page: String?

    @Option(name: .long, help: "Maximum link traversal depth")
    var depth: Int = 2

    @Option(name: .long, help: "Read or generate _context.md for this folder path (relative to workspace or absolute)")
    var folder: String?

    func run() throws {
        guard depth >= 0 else {
            throw CLIError.invalidInput("Depth must be non-negative")
        }

        let workspace = options.resolvedWorkspace

        if let folderArg = folder {
            try runFolderMode(folderArg: folderArg, workspace: workspace)
            return
        }

        guard let pageName = page else {
            throw CLIError.invalidInput("Provide a page name or use --folder <path>")
        }

        let record = try resolveWorkspacePage(pageName, workspace: workspace)

        var visited = Set<String>()
        var pages: [(name: String, content: String)] = []
        var folderContexts: [(folder: String, hint: String)] = []

        try traverse(
            record: record,
            workspace: workspace,
            remainingDepth: depth,
            visited: &visited,
            pages: &pages,
            folderContexts: &folderContexts
        )

        var output = pages.map { "--- Page: \($0.name) ---\n\($0.content)" }.joined(separator: "\n\n")

        if !folderContexts.isEmpty {
            let deduplicated = deduplicate(folderContexts)
            let contextSection = deduplicated
                .map { "--- Folder: \($0.folder) ---\n\($0.hint)" }
                .joined(separator: "\n\n")
            output = "=== Folder Context ===\n\n\(contextSection)\n\n=== Pages ===\n\n\(output)"
        }

        FileHandle.standardOutput.write(Data(output.utf8))
    }

    // MARK: - Folder mode

    private func runFolderMode(folderArg: String, workspace: String) throws {
        let folderPath = resolveFolderPath(folderArg, workspace: workspace)
        let contextPath = (folderPath as NSString).appendingPathComponent("_context.md")

        if FileManager.default.fileExists(atPath: contextPath) {
            let content = try String(contentsOfFile: contextPath, encoding: .utf8)
            FileHandle.standardOutput.write(Data(content.utf8))
            return
        }

        // Generate a basic context from folder contents
        let generated = generateFolderContext(at: folderPath, workspace: workspace)
        FileHandle.standardOutput.write(Data(generated.utf8))
    }

    // MARK: - Page traversal

    private func traverse(
        record: WorkspacePageRecord,
        workspace: String,
        remainingDepth: Int,
        visited: inout Set<String>,
        pages: inout [(name: String, content: String)],
        folderContexts: inout [(folder: String, hint: String)]
    ) throws {
        guard visited.insert(record.path).inserted else { return }

        let content = presentedMarkdown(record.content)
        pages.append((name: record.title, content: content))

        // Check for _context.md in this page's parent folder
        let parentDir = (record.path as NSString).deletingLastPathComponent
        let contextPath = (parentDir as NSString).appendingPathComponent("_context.md")
        if FileManager.default.fileExists(atPath: contextPath),
           let hint = try? String(contentsOfFile: contextPath, encoding: .utf8) {
            let folderName = relativePath(from: parentDir, workspace: workspace)
            folderContexts.append((folder: folderName.isEmpty ? "/" : folderName, hint: hint.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        guard remainingDepth > 0 else { return }

        for name in record.wikilinks {
            guard let linked = try? resolveWorkspacePage(name, workspace: workspace) else { continue }
            guard !visited.contains(linked.path) else { continue }
            try traverse(
                record: linked,
                workspace: workspace,
                remainingDepth: remainingDepth - 1,
                visited: &visited,
                pages: &pages,
                folderContexts: &folderContexts
            )
        }
    }

    // MARK: - Helpers

    private func resolveFolderPath(_ folderArg: String, workspace: String) -> String {
        let expanded = (folderArg as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return normalizePath(expanded)
        }
        return normalizePath((workspace as NSString).appendingPathComponent(folderArg))
    }

    private func generateFolderContext(at folderPath: String, workspace: String) -> String {
        let fm = FileManager.default
        var titles: [String] = []

        if let items = try? fm.contentsOfDirectory(atPath: folderPath) {
            for item in items.sorted() {
                guard item.hasSuffix(".md"), !item.hasPrefix("_"), !item.hasPrefix(".") else { continue }
                let filePath = (folderPath as NSString).appendingPathComponent(item)
                let name = (item as NSString).deletingPathExtension
                // Try to read the first heading, fall back to file name
                if let content = try? String(contentsOfFile: filePath, encoding: .utf8),
                   let heading = extractFirstHeading(from: content) {
                    titles.append(heading)
                } else {
                    titles.append(name)
                }
            }
        }

        let folderName = (folderPath as NSString).lastPathComponent
        let pageCount = titles.count
        let pageWord = pageCount == 1 ? "page" : "pages"

        if titles.isEmpty {
            return "# \(folderName)\n\nEmpty folder. 0 pages.\n"
        }

        let titleList = titles.map { "- \($0)" }.joined(separator: "\n")
        return "# \(folderName)\n\n\(pageCount) \(pageWord):\n\(titleList)\n"
    }

    private func extractFirstHeading(from content: String) -> String? {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func deduplicate(_ items: [(folder: String, hint: String)]) -> [(folder: String, hint: String)] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.folder).inserted }
    }
}
