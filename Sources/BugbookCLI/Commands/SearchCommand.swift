import ArgumentParser
import Foundation
import BugbookCore

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

    @Option(name: .long, help: "Search mode: bm25 (keyword, default), semantic, hybrid")
    var mode: String = "bm25"

    @Option(name: .long, help: "Force search engine: qmd (default) or local")
    var engine: String = "qmd"

    func run() throws {
        let workspace = options.resolvedWorkspace
        guard FileManager.default.fileExists(atPath: workspace) else {
            throw CLIError.fileNotFound(workspace)
        }

        if engine != "local", let qmdPath = QmdBackend.find() {
            let backend = QmdBackend(binary: qmdPath, workspace: workspace)
            do {
                backend.ensureCollection()
                let results = try backend.search(
                    query: query, limit: limit, mode: mode,
                    filesOnly: filesOnly, tag: tag
                )
                if !results.isEmpty {
                    try outputJSON([
                        "results": results,
                        "total_count": results.count,
                        "engine": "qmd",
                        "mode": mode,
                    ])
                    return
                }
                fputs("Warning: qmd search returned no results, falling back to local\n", stderr)
            } catch {
                fputs("Warning: qmd search failed (\(error)), falling back to local\n", stderr)
            }
        }

        let results = localSearch(
            query: query, workspace: workspace, limit: limit,
            filesOnly: filesOnly, tag: tag
        )
        try outputJSON(["results": results, "total_count": results.count, "engine": "local"])
    }
}

// MARK: - qmd Backend

private struct QmdBackend {
    let binary: String
    let workspace: String

    var collectionName: String {
        let name = URL(fileURLWithPath: workspace).lastPathComponent
        return name.isEmpty ? "bugbook" : name
    }

    /// Locate the qmd binary, checking PATH and common install locations.
    static func find() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", "qmd"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        if (try? task.run()) != nil {
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !out.isEmpty { return out }
            }
        }
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        for path in [
            "\(home)/.bun/bin/qmd",
            "\(home)/.npm-global/bin/qmd",
            "\(home)/.local/bin/qmd",
            "/usr/local/bin/qmd",
            "/opt/homebrew/bin/qmd",
        ] where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    /// Register workspace as a qmd collection and build the FTS index.
    /// collection add only registers the path; update actually indexes the files.
    func ensureCollection() {
        func run(_ args: [String]) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: binary)
            task.arguments = args
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
        // v2: collection name derived from directory, no --name flag
        run(["collection", "add", workspace])
        run(["update"])
    }

    func search(query: String, limit: Int, mode: String, filesOnly: Bool, tag: String?) throws -> [[String: Any]] {
        var results: [[String: Any]]
        switch mode {
        case "semantic":
            results = try runCLISearch(tool: "vsearch", query: query, limit: limit)
        case "hybrid":
            // v2: `qmd query` handles hybrid search locally (expansion + reranking)
            results = try runCLISearch(tool: "query", query: query, limit: limit)
        default: // bm25
            results = try runCLISearch(tool: "search", query: query, limit: limit)
        }

        if let tag = tag {
            results = applyTagFilter(results, tag: tag)
        }

        results = results.filter { result in
            guard let file = result["file"] as? String else { return false }
            return !WorkspacePathRules.shouldIgnoreRelativePath(file)
        }

        if filesOnly {
            var seen = Set<String>()
            results = results.compactMap { r in
                guard let file = r["file"] as? String, seen.insert(file).inserted else { return nil }
                return ["file": file, "name": r["name"] as Any]
            }
        }

        return Array(results.prefix(limit))
    }

    // MARK: CLI search (bm25 / semantic)

    private func runCLISearch(tool: String, query: String, limit: Int) throws -> [[String: Any]] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = [tool, query, "--json", "-n", "\(limit)", "-c", collectionName]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw CLIError.invalidInput("qmd \(tool) exited \(task.terminationStatus)")
        }
        return parseQmdData(pipe.fileHandleForReading.readDataToEndOfFile())
    }

    // MARK: Response parsing

    // qmd CLI outputs a JSON array; MCP response wraps in {"results": [...]}
    private func parseQmdData(_ data: Data) -> [[String: Any]] {
        let parsed = try? JSONSerialization.jsonObject(with: data)
        if let arr = parsed as? [[String: Any]] {
            return arr.compactMap { mapResult($0) }
        }
        if let obj = parsed as? [String: Any],
           let raw = obj["results"] as? [[String: Any]] {
            return raw.compactMap { mapResult($0) }
        }
        return []
    }

    /// Map a qmd result object to BugbookCLI's search result format.
    private func mapResult(_ r: [String: Any]) -> [String: Any]? {
        // CLI uses "path", MCP uses "file"
        guard let rawPath = (r["path"] as? String) ?? (r["file"] as? String) else { return nil }

        let relativePath = normalizedRelativePath(rawPath)
        let name: String
        if let title = r["title"] as? String, !title.isEmpty {
            name = title
        } else {
            name = pageDisplayName(fromPath: relativePath)
        }

        var result: [String: Any] = ["file": relativePath, "name": name]

        // Line number: explicit field or parse from snippet header "@@ -{N},{count} @@"
        if let line = r["line"] as? Int {
            result["line"] = line
        } else if let snippet = r["snippet"] as? String,
                  let line = parseSnippetLineNumber(snippet) {
            result["line"] = line
        }

        if let snippet = r["snippet"] as? String {
            let cleaned = stripSnippetLineNumbers(snippet)
            let firstLine = cleaned.components(separatedBy: "\n")
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? cleaned
            result["text"] = firstLine.trimmingCharacters(in: .whitespaces)
            result["context"] = cleaned
        }

        if let score = r["score"] { result["score"] = score }

        return result
    }

    /// Strip workspace and qmd:// virtual path prefixes to get a clean relative path.
    private func normalizedRelativePath(_ path: String) -> String {
        var p = path
        // Strip qmd://collectionName/ prefix
        if p.hasPrefix("qmd://") {
            p = String(p.dropFirst(6))
            if let slash = p.firstIndex(of: "/") {
                p = String(p[p.index(after: slash)...])
            }
        }
        // Strip absolute workspace prefix
        if p.hasPrefix(workspace) {
            p = String(p.dropFirst(workspace.count))
            if p.hasPrefix("/") { p = String(p.dropFirst()) }
        }
        return p
    }

    /// Parse line number from diff-style snippet header: "@@ -{N},{count} @@" or just use prefix "N: text".
    private func parseSnippetLineNumber(_ snippet: String) -> Int? {
        // Diff header: "@@ -42,5 @@"
        if let range = snippet.range(of: #"@@ -(\d+)"#, options: .regularExpression) {
            let match = String(snippet[range])
            let digits = match.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .first(where: { !$0.isEmpty })
            return digits.flatMap { Int($0) }
        }
        // Numbered lines: "42: first line of snippet"
        if let colon = snippet.firstIndex(of: ":") {
            let prefix = String(snippet[snippet.startIndex..<colon])
            return Int(prefix.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// Remove "N: " line-number prefixes added by qmd to snippet content.
    private func stripSnippetLineNumbers(_ snippet: String) -> String {
        let lines = snippet.components(separatedBy: "\n")
        let stripped = lines.map { line -> String in
            // Match "42: actual content" or "@@ -42,5 @@" header
            if line.hasPrefix("@@") { return "" }
            if let colon = line.firstIndex(of: ":") {
                let prefix = String(line[line.startIndex..<colon])
                if prefix.trimmingCharacters(in: .whitespaces).allSatisfy(\.isNumber) {
                    return String(line[line.index(after: colon)...]).trimmingCharacters(in: .init(charactersIn: " "))
                }
            }
            return line
        }
        return stripped.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: Tag post-filter

    private func applyTagFilter(_ results: [[String: Any]], tag: String) -> [[String: Any]] {
        let pattern = #"(?:^|\s)#"# + NSRegularExpression.escapedPattern(for: tag) + #"(?:\s|$|/)"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .anchorsMatchLines]
        ) else { return results }

        var cache: [String: Bool] = [:]
        return results.filter { r in
            guard let rel = r["file"] as? String else { return false }
            let full = (workspace as NSString).appendingPathComponent(rel)
            if let cached = cache[full] { return cached }
            guard let content = try? String(contentsOfFile: full, encoding: .utf8) else {
                cache[full] = false; return false
            }
            let matched = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
            cache[full] = matched
            return matched
        }
    }
}

// MARK: - Local Search (fallback when qmd is not installed)

private func localSearch(
    query: String, workspace: String, limit: Int, filesOnly: Bool, tag: String?
) -> [[String: Any]] {
    let fm = FileManager.default
    var results: [[String: Any]] = []
    var seenFiles: Set<String> = []
    let queryLower = query.lowercased()

    walkWorkspaceMarkdownFiles(in: workspace, includeStructuredContent: true, fileManager: fm) { filePath, relativePath in
        guard results.count < limit else { return }
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

        if let tag = tag {
            let tagPattern = #"(?:^|\s)#"# + NSRegularExpression.escapedPattern(for: tag) + #"(?:\s|$|/)"#
            guard let tagRegex = try? NSRegularExpression(
                pattern: tagPattern, options: [.caseInsensitive, .anchorsMatchLines]
            ) else { return }
            let fullRange = NSRange(content.startIndex..., in: content)
            if tagRegex.firstMatch(in: content, range: fullRange) == nil { return }
        }

        let lines = content.components(separatedBy: "\n")
        let pageName = pageDisplayName(fromPath: filePath)

        if filesOnly {
            if lines.contains(where: { $0.lowercased().contains(queryLower) }),
               seenFiles.insert(filePath).inserted {
                results.append(["file": relativePath, "name": pageName])
            }
        } else {
            for (lineNum, line) in lines.enumerated() {
                guard results.count < limit else { break }
                if line.lowercased().contains(queryLower) {
                    let ctxStart = max(0, lineNum - 1)
                    let ctxEnd = min(lines.count - 1, lineNum + 1)
                    results.append([
                        "file": relativePath,
                        "name": pageName,
                        "line": lineNum + 1,
                        "text": line.trimmingCharacters(in: .whitespaces),
                        "context": lines[ctxStart...ctxEnd].joined(separator: "\n"),
                    ])
                }
            }
        }
    }
    return results
}
