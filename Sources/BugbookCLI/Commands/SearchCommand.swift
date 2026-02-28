import ArgumentParser
import Foundation

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Full-text search across all markdown files in the workspace"
    )

    @OptionGroup var options: Bugbook.Options

    @Argument(help: "Search query text")
    var query: String

    @Option(help: "Maximum number of results (default 50)")
    var limit: Int = 50

    @Flag(name: .long, help: "Only return unique file paths, no line details")
    var filesOnly: Bool = false

    @Option(name: .long, help: "Filter to files containing #tag")
    var tag: String?

    func run() throws {
        let workspace = options.resolvedWorkspace
        let fm = FileManager.default

        guard fm.fileExists(atPath: workspace) else {
            throw CLIError.fileNotFound(workspace)
        }

        var results: [[String: Any]] = []
        var seenFiles: Set<String> = []
        let queryLower = query.lowercased()

        walkMarkdownFiles(in: workspace, fileManager: fm) { filePath, relativePath in
            guard results.count < limit else { return }

            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

            // Tag filter: skip files that don't contain the tag (word-boundary match)
            if let tag = tag {
                let tagPattern = #"(?:^|\s)#"# + NSRegularExpression.escapedPattern(for: tag) + #"(?:\s|$|/)"#
                guard let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive, .anchorsMatchLines]) else { return }
                let fullRange = NSRange(content.startIndex..., in: content)
                if tagRegex.firstMatch(in: content, range: fullRange) == nil { return }
            }

            let lines = content.components(separatedBy: "\n")
            let pageName = pageNameFromPath(filePath)

            if filesOnly {
                // Check if any line matches
                let matches = lines.contains { $0.lowercased().contains(queryLower) }
                if matches && !seenFiles.contains(filePath) {
                    seenFiles.insert(filePath)
                    results.append([
                        "file": relativePath,
                        "name": pageName,
                    ])
                }
            } else {
                for (lineNum, line) in lines.enumerated() {
                    guard results.count < limit else { break }
                    if line.lowercased().contains(queryLower) {
                        let contextStart = max(0, lineNum - 1)
                        let contextEnd = min(lines.count - 1, lineNum + 1)
                        let context = lines[contextStart...contextEnd].joined(separator: "\n")

                        results.append([
                            "file": relativePath,
                            "name": pageName,
                            "line": lineNum + 1,
                            "text": line.trimmingCharacters(in: .whitespaces),
                            "context": context,
                        ])
                    }
                }
            }
        }

        try outputJSON([
            "results": results,
            "total_count": results.count,
        ])
    }
}

// MARK: - Helpers

private func walkMarkdownFiles(in directory: String, fileManager: FileManager, handler: (String, String) -> Void) {
    guard let enumerator = fileManager.enumerator(atPath: directory) else { return }

    while let relativePath = enumerator.nextObject() as? String {
        // Skip hidden files/dirs
        let components = relativePath.components(separatedBy: "/")
        if components.contains(where: { $0.hasPrefix(".") }) { continue }

        // Skip schema/index files
        let filename = (relativePath as NSString).lastPathComponent
        if filename == "_schema.json" || filename == "_index.json" { continue }

        // Only .md files
        guard filename.hasSuffix(".md") else { continue }

        let fullPath = (directory as NSString).appendingPathComponent(relativePath)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }

        handler(fullPath, relativePath)
    }
}

private func pageNameFromPath(_ path: String) -> String {
    let filename = (path as NSString).lastPathComponent
    if filename.hasSuffix(".md") {
        return String(filename.dropLast(3))
    }
    return filename
}
