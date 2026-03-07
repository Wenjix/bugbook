import Foundation
import BugbookCore
import Yams

struct WorkspacePageRecord {
    let path: String
    let relativePath: String
    let name: String
    let title: String
    let content: String
    let body: String
    let frontmatter: [String: Any]
    let tags: [String]
    let wikilinks: [String]
    let modifiedAt: String?

    func toSummaryJSON() -> [String: Any] {
        var json: [String: Any] = [
            "path": path,
            "relative_path": relativePath,
            "name": name,
            "title": title,
            "tags": tags,
            "wikilinks": wikilinks,
        ]
        if let type = frontmatter["type"] as? String {
            json["type"] = type
        }
        if let modifiedAt {
            json["modified_at"] = modifiedAt
        }
        return json
    }

    func toDetailJSON(includeContent: Bool = true) -> [String: Any] {
        var json = toSummaryJSON()
        json["frontmatter"] = jsonCompatibleObject(frontmatter)
        if includeContent {
            json["content"] = content
            json["body"] = body
        }
        return json
    }
}

private struct WorkspacePageLookupCandidate {
    let path: String
    let relativePath: String
    let name: String
}

func listWorkspacePages(
    in workspace: String,
    pathPrefix: String? = nil,
    type: String? = nil,
    tag: String? = nil
) throws -> [WorkspacePageRecord] {
    var pages: [WorkspacePageRecord] = []
    walkWorkspaceMarkdownFiles(in: workspace, includeStructuredContent: false) { filePath, relativePath in
        guard let record = try? loadWorkspacePage(at: filePath, relativeTo: workspace, relativePathOverride: relativePath) else {
            return
        }
        pages.append(record)
    }

    if let pathPrefix, !pathPrefix.isEmpty {
        let normalized = normalizePageLookup(pathPrefix)
        pages = pages.filter { normalizePageLookup($0.relativePath).hasPrefix(normalized) }
    }

    if let type, !type.isEmpty {
        let expected = type.lowercased()
        pages = pages.filter { ($0.frontmatter["type"] as? String)?.lowercased() == expected }
    }

    if let tag, !tag.isEmpty {
        let expected = tag.lowercased()
        pages = pages.filter { $0.tags.contains(where: { $0.lowercased() == expected }) }
    }

    return pages.sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
}

func resolveWorkspacePage(_ query: String, workspace: String) throws -> WorkspacePageRecord {
    let path = try resolveWorkspacePagePath(query, workspace: workspace)
    return try loadWorkspacePage(at: path, relativeTo: workspace)
}

func resolveWorkspacePagePath(_ query: String, workspace: String) throws -> String {
    let expanded = (query as NSString).expandingTildeInPath
    let normalizedWorkspace = normalizePath(workspace)

    if expanded.hasPrefix("/") {
        let candidate = normalizePath(expanded)
        guard isPathInsideWorkspace(candidate, workspace: normalizedWorkspace) else {
            throw CLIError.invalidInput("Page path must be inside workspace: \(query)")
        }
        guard FileManager.default.fileExists(atPath: candidate) else {
            throw CLIError.fileNotFound(candidate)
        }
        guard candidate.hasSuffix(".md"), !WorkspacePathRules.shouldIgnoreAbsolutePath(candidate) else {
            throw CLIError.invalidInput("Not a visible page: \(query)")
        }
        return candidate
    }

    for direct in directPageCandidates(for: query, workspace: normalizedWorkspace) {
        if FileManager.default.fileExists(atPath: direct),
           direct.hasSuffix(".md"),
           !WorkspacePathRules.shouldIgnoreAbsolutePath(direct) {
            return direct
        }
    }

    let matches = try workspacePageMatches(for: query, workspace: normalizedWorkspace)

    if matches.count == 1, let match = matches.first {
        return match.path
    }

    if matches.isEmpty {
        throw CLIError.invalidInput("Page not found: \(query)")
    }

    let options = matches.map(\.relativePath).sorted().joined(separator: ", ")
    throw CLIError.invalidInput("Page reference is ambiguous: \(query). Matches: \(options)")
}

func createWorkspacePage(
    rawPath: String,
    workspace: String,
    title: String? = nil,
    content: String? = nil
) throws -> WorkspacePageRecord {
    let pagePath = try normalizePageDestination(rawPath, workspace: workspace)
    guard !FileManager.default.fileExists(atPath: pagePath) else {
        throw CLIError.invalidInput("Page already exists: \(pagePath)")
    }

    let dir = (pagePath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    let pageTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        ?? pageDisplayName(fromPath: pagePath)
    let pageContent = content ?? "# \(pageTitle)\n\n"
    try pageContent.write(toFile: pagePath, atomically: true, encoding: .utf8)
    return try loadWorkspacePage(at: pagePath, relativeTo: workspace)
}

func updateWorkspacePage(
    query: String,
    workspace: String,
    replacementContent: String? = nil,
    prependContent: String? = nil,
    appendContent: String? = nil
) throws -> WorkspacePageRecord {
    if replacementContent != nil && (prependContent != nil || appendContent != nil) {
        throw CLIError.invalidInput("Use --content-file by itself, or use --prepend-file/--append-file without --content-file")
    }

    let existing = try resolveWorkspacePage(query, workspace: workspace)
    var nextContent = replacementContent ?? existing.content

    if let prependContent, !prependContent.isEmpty {
        nextContent = prependContent + nextContent
    }
    if let appendContent, !appendContent.isEmpty {
        nextContent += appendContent
    }

    try nextContent.write(toFile: existing.path, atomically: true, encoding: .utf8)
    return try loadWorkspacePage(at: existing.path, relativeTo: workspace)
}

func deleteWorkspacePage(query: String, workspace: String, recursive: Bool) throws -> [String: Any] {
    let page = try resolveWorkspacePage(query, workspace: workspace)
    let fm = FileManager.default
    let companion = companionFolderPath(for: page.path)
    var deletedPaths = [page.path]

    if fm.fileExists(atPath: companion) {
        let contents = (try? fm.contentsOfDirectory(atPath: companion)) ?? []
        if !contents.isEmpty && !recursive {
            throw CLIError.invalidInput("Page has companion content. Re-run with --recursive to delete \(companion)")
        }
    }

    try fm.removeItem(atPath: page.path)
    if fm.fileExists(atPath: companion) {
        try fm.removeItem(atPath: companion)
        deletedPaths.append(companion)
    }
    return [
        "deleted": true,
        "page": page.relativePath,
        "paths": deletedPaths,
    ]
}

func embedDatabaseInPage(pageQuery: String, databaseQuery: String, workspace: String) throws -> [String: Any] {
    let (dbPath, schema) = try resolveDatabase(databaseQuery, workspace: workspace)
    return try embedDatabasePathInPage(
        pageQuery: pageQuery,
        databasePath: dbPath,
        workspace: workspace,
        databaseNameOverride: schema.name
    )
}

func embedDatabasePathInPage(
    pageQuery: String,
    databasePath: String,
    workspace: String,
    databaseNameOverride: String? = nil
) throws -> [String: Any] {
    let page = try resolveWorkspacePage(pageQuery, workspace: workspace)
    let normalizedDatabasePath = normalizePath(databasePath)
    let marker = "<!-- database: \(normalizedDatabasePath) -->"
    let alreadyPresent = page.content
        .components(separatedBy: .newlines)
        .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == marker }

    if alreadyPresent {
        return [
            "embedded": false,
            "already_present": true,
            "page": page.relativePath,
            "database_path": normalizedDatabasePath,
            "database_name": databaseNameOverride ?? pageDisplayName(fromPath: normalizedDatabasePath),
        ]
    }

    let nextContent = appendedMarkdownBlock(marker, to: page.content)
    try nextContent.write(toFile: page.path, atomically: true, encoding: .utf8)

    let updatedPage = try loadWorkspacePage(at: page.path, relativeTo: workspace)
    return [
        "embedded": true,
        "already_present": false,
        "page": updatedPage.relativePath,
        "database_path": normalizedDatabasePath,
        "database_name": databaseNameOverride ?? pageDisplayName(fromPath: normalizedDatabasePath),
    ]
}

func backlinksForPage(query: String, workspace: String) throws -> [[String: Any]] {
    let linkTargets: Set<String>
    if let page = try? resolveWorkspacePage(query, workspace: workspace) {
        linkTargets = Set([page.name, page.title].map(normalizePageLookup).filter { !$0.isEmpty })
    } else {
        linkTargets = Set([normalizePageLookup(pageDisplayName(fromPath: query))].filter { !$0.isEmpty })
    }

    var backlinks: [[String: Any]] = []
    var seen = Set<String>()
    walkWorkspaceMarkdownFiles(in: workspace, includeStructuredContent: false) { filePath, relativePath in
        guard let record = try? loadWorkspacePage(at: filePath, relativeTo: workspace, relativePathOverride: relativePath) else {
            return
        }
        let matches = record.wikilinks.filter { linkTargets.contains(normalizePageLookup($0)) }
        guard !matches.isEmpty else {
            return
        }
        guard seen.insert(record.path).inserted else { return }
        var json = record.toSummaryJSON()
        json["matches"] = matches
        backlinks.append(json)
    }

    return backlinks.sorted {
        let lhs = ($0["title"] as? String) ?? ""
        let rhs = ($1["title"] as? String) ?? ""
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
}

private func workspacePageMatches(for query: String, workspace: String) throws -> [WorkspacePageLookupCandidate] {
    let candidates = collectWorkspacePageLookupCandidates(in: workspace)
    let needle = normalizePageLookup(query)

    let directMatches = candidates.filter { candidate in
        normalizePageLookup(candidate.relativePath) == needle
            || normalizePageLookup((candidate.relativePath as NSString).deletingPathExtension) == needle
            || normalizePageLookup(candidate.name) == needle
    }

    if !directMatches.isEmpty {
        return directMatches
    }

    return candidates.filter { candidate in
        guard let title = try? pageTitleAtPath(candidate.path, fallback: candidate.name) else {
            return false
        }
        return normalizePageLookup(title) == needle
    }
}

private func collectWorkspacePageLookupCandidates(in workspace: String) -> [WorkspacePageLookupCandidate] {
    var candidates: [WorkspacePageLookupCandidate] = []
    walkWorkspaceMarkdownFiles(in: workspace, includeStructuredContent: false) { filePath, relativePath in
        candidates.append(
            WorkspacePageLookupCandidate(
                path: filePath,
                relativePath: relativePath,
                name: pageDisplayName(fromPath: filePath)
            )
        )
    }
    return candidates
}

func walkWorkspaceMarkdownFiles(
    in workspace: String,
    includeStructuredContent: Bool,
    fileManager: FileManager = .default,
    handler: (String, String) -> Void
) {
    let excludedDirs = includeStructuredContent ? Set<String>() : excludedContentDirectories(in: workspace, fileManager: fileManager)
    guard let enumerator = fileManager.enumerator(atPath: workspace) else { return }

    while let relativePath = enumerator.nextObject() as? String {
        if WorkspacePathRules.shouldIgnoreRelativePath(relativePath) { continue }
        let filename = (relativePath as NSString).lastPathComponent
        guard filename.hasSuffix(".md") else { continue }

        let parentDir = (relativePath as NSString).deletingLastPathComponent
        if !includeStructuredContent, excludedDirs.contains(parentDir) { continue }

        let fullPath = (workspace as NSString).appendingPathComponent(relativePath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            continue
        }

        handler(fullPath, relativePath)
    }
}

func loadWorkspacePage(
    at path: String,
    relativeTo workspace: String,
    relativePathOverride: String? = nil
) throws -> WorkspacePageRecord {
    let normalizedPath = normalizePath(path)
    let normalizedWorkspace = normalizePath(workspace)
    let relativePath = relativePathOverride ?? relativePath(from: normalizedPath, workspace: normalizedWorkspace)
    let content = try String(contentsOfFile: normalizedPath, encoding: .utf8)
    let (frontmatter, body) = parsePageFrontmatter(content)
    let name = pageDisplayName(fromPath: normalizedPath)
    let title = pageTitle(body: body, fallback: name, frontmatter: frontmatter)
    let tags = pageTags(frontmatter: frontmatter, body: body)
    let wikilinks = extractWikiLinks(from: body)

    let attrs = try? FileManager.default.attributesOfItem(atPath: normalizedPath)
    let modifiedAt = (attrs?[.modificationDate] as? Date).map(iso8601String(from:))

    return WorkspacePageRecord(
        path: normalizedPath,
        relativePath: relativePath,
        name: name,
        title: title,
        content: content,
        body: body,
        frontmatter: frontmatter,
        tags: tags,
        wikilinks: wikilinks,
        modifiedAt: modifiedAt
    )
}

func readTextInput(from source: String) throws -> String {
    if source == "-" {
        var input = ""
        while let line = readLine(strippingNewline: false) {
            input += line
        }
        return input
    }

    let path = (source as NSString).expandingTildeInPath
    return try String(contentsOfFile: path, encoding: .utf8)
}

private func appendedMarkdownBlock(_ block: String, to content: String) -> String {
    let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedBlock.isEmpty else { return content }

    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return trimmedBlock + "\n"
    }

    var result = content
    if !result.hasSuffix("\n") {
        result += "\n"
    }
    if !result.hasSuffix("\n\n") {
        result += "\n"
    }

    result += trimmedBlock
    if !result.hasSuffix("\n") {
        result += "\n"
    }

    return result
}

private func normalizePageDestination(_ rawPath: String, workspace: String) throws -> String {
    let normalizedWorkspace = normalizePath(workspace)
    let expanded = (rawPath as NSString).expandingTildeInPath
    let absoluteBase = expanded.hasPrefix("/")
        ? normalizePath(expanded)
        : normalizePath((normalizedWorkspace as NSString).appendingPathComponent(rawPath))

    guard isPathInsideWorkspace(absoluteBase, workspace: normalizedWorkspace) else {
        throw CLIError.invalidInput("Page path must be inside workspace: \(rawPath)")
    }

    let directory = (absoluteBase as NSString).deletingLastPathComponent
    let filename = (absoluteBase as NSString).lastPathComponent
    guard !filename.isEmpty else {
        throw CLIError.invalidInput("Page path must include a file name")
    }

    let ext = (filename as NSString).pathExtension
    let baseName = ext.isEmpty ? filename : (filename as NSString).deletingPathExtension
    let sanitizedBase = sanitizePageFileName(baseName)
    let finalFilename = "\(sanitizedBase).md"
    return normalizePath((directory as NSString).appendingPathComponent(finalFilename))
}

private func directPageCandidates(for query: String, workspace: String) -> [String] {
    let candidates = [
        query,
        query.hasSuffix(".md") ? query : "\(query).md",
    ]

    return Array(Set(candidates.map { candidate in
        normalizePath((workspace as NSString).appendingPathComponent(candidate))
    }))
}

private func excludedContentDirectories(in workspace: String, fileManager: FileManager) -> Set<String> {
    guard let enumerator = fileManager.enumerator(atPath: workspace) else { return [] }
    var excluded = Set<String>()

    while let relativePath = enumerator.nextObject() as? String {
        if WorkspacePathRules.shouldIgnoreRelativePath(relativePath) { continue }
        let filename = (relativePath as NSString).lastPathComponent
        if filename == "_schema.json" || filename == "_canvas.json" {
            excluded.insert((relativePath as NSString).deletingLastPathComponent)
        }
    }

    return excluded
}

func relativePath(from path: String, workspace: String) -> String {
    guard path.hasPrefix(workspace) else { return path }
    var relative = String(path.dropFirst(workspace.count))
    if relative.hasPrefix("/") {
        relative.removeFirst()
    }
    return relative
}

func isPathInsideWorkspace(_ path: String, workspace: String) -> Bool {
    path == workspace || path.hasPrefix(workspace + "/")
}

func normalizePath(_ path: String) -> String {
    (path as NSString).standardizingPath
}

private func sanitizePageFileName(_ value: String) -> String {
    let sanitized = value.replacingOccurrences(
        of: "[/\\\\?%*:|\"<>]",
        with: "-",
        options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? "Untitled" : sanitized
}

private func companionFolderPath(for pagePath: String) -> String {
    (pagePath as NSString).deletingPathExtension
}

func pageDisplayName(fromPath path: String) -> String {
    let filename = (path as NSString).lastPathComponent
    return filename.hasSuffix(".md") ? String(filename.dropLast(3)) : filename
}

func normalizePageLookup(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\", with: "/")
        .lowercased()
}

private func pageTitle(body: String, fallback: String, frontmatter: [String: Any]) -> String {
    if let explicit = frontmatter["title"] as? String,
       !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return explicit
    }

    for line in body.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("# ") {
            let heading = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !heading.isEmpty {
                return heading
            }
        }
    }

    return fallback
}

private func pageTags(frontmatter: [String: Any], body: String) -> [String] {
    var tags = Set<String>()

    if let value = frontmatter["tags"] as? [String] {
        value.forEach { tags.insert(normalizeTag($0)) }
    } else if let value = frontmatter["tags"] as? [Any] {
        value.map { String(describing: $0) }.forEach { tags.insert(normalizeTag($0)) }
    } else if let value = frontmatter["tags"] as? String {
        tags.insert(normalizeTag(value))
    }

    let pattern = #"(?<!\w)#([A-Za-z0-9_/-]+)"#
    if let regex = try? NSRegularExpression(pattern: pattern) {
        let range = NSRange(body.startIndex..., in: body)
        for match in regex.matches(in: body, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: body) else { continue }
            tags.insert(normalizeTag(String(body[tagRange])))
        }
    }

    return tags.filter { !$0.isEmpty }.sorted()
}

private func normalizeTag(_ tag: String) -> String {
    tag.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
}

private func extractWikiLinks(from content: String) -> [String] {
    let pattern = #"\[\[([^\]]+)\]\]"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

    let range = NSRange(content.startIndex..., in: content)
    return regex.matches(in: content, range: range).compactMap { match in
        guard let linkRange = Range(match.range(at: 1), in: content) else { return nil }
        return String(content[linkRange])
    }
}

private func parsePageFrontmatter(_ content: String) -> ([String: Any], String) {
    guard content.hasPrefix("---") else {
        return ([:], content)
    }

    let lines = content.components(separatedBy: .newlines)
    guard lines.first == "---" else {
        return ([:], content)
    }

    var frontmatterLines: [String] = []
    var bodyStartIndex: Int?

    for index in 1..<lines.count {
        if lines[index] == "---" {
            bodyStartIndex = index + 1
            break
        }
        frontmatterLines.append(lines[index])
    }

    guard let bodyStartIndex else {
        return ([:], content)
    }

    let body = lines.dropFirst(bodyStartIndex).joined(separator: "\n")
    return (parseFrontmatter(frontmatterLines.joined(separator: "\n")), body)
}

private func parseFrontmatter(_ yaml: String) -> [String: Any] {
    let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [:] }

    let object: Any
    do {
        guard let loaded = try Yams.load(yaml: trimmed) else {
            return [:]
        }
        object = loaded
    } catch {
        return [:]
    }

    guard let dictionary = jsonCompatibleObject(object) as? [String: Any] else {
        return [:]
    }

    return dictionary
}

private func pageTitleAtPath(_ path: String, fallback: String) throws -> String {
    let content = try String(contentsOfFile: path, encoding: .utf8)
    let (frontmatter, body) = parsePageFrontmatter(content)
    return pageTitle(body: body, fallback: fallback, frontmatter: frontmatter)
}

private func jsonCompatibleObject(_ value: Any) -> Any {
    switch value {
    case let dict as [String: Any]:
        return dict.reduce(into: [String: Any]()) { partialResult, entry in
            partialResult[entry.key] = jsonCompatibleObject(entry.value)
        }
    case let dict as [AnyHashable: Any]:
        return dict.reduce(into: [String: Any]()) { partialResult, entry in
            partialResult[String(describing: entry.key)] = jsonCompatibleObject(entry.value)
        }
    case let array as [Any]:
        return array.map(jsonCompatibleObject)
    case let string as String:
        return string
    case let bool as Bool:
        return bool
    case let number as NSNumber:
        return number
    case let date as Date:
        return iso8601String(from: date)
    case is NSNull:
        return NSNull()
    default:
        return String(describing: value)
    }
}
