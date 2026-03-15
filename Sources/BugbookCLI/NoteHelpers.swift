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

    func toDetailJSON(includeContent: Bool = true, includeInternalComments: Bool = false) -> [String: Any] {
        var json = toSummaryJSON()
        json["frontmatter"] = jsonCompatibleObject(frontmatter)
        if includeContent {
            json["content"] = presentedMarkdown(content, includeInternalComments: includeInternalComments)
            json["body"] = presentedMarkdown(body, includeInternalComments: includeInternalComments)
        }
        return json
    }
}

struct WorkspacePageSectionRecord {
    let title: String
    let level: Int
    let headingLine: Int
    let bodyLine: Int
    let endLine: Int
    let content: String
    let body: String

    func toJSON(includeContent: Bool = true, includeInternalComments: Bool = false) -> [String: Any] {
        var json: [String: Any] = [
            "title": title,
            "level": level,
            "heading_line": headingLine,
            "body_line": bodyLine,
            "end_line": endLine,
        ]
        if includeContent {
            json["content"] = presentedMarkdown(content, includeInternalComments: includeInternalComments)
            json["body"] = presentedMarkdown(body, includeInternalComments: includeInternalComments)
        }
        return json
    }
}

struct WorkspacePageUpdatePreview {
    let original: WorkspacePageRecord
    let updated: WorkspacePageRecord
    let changed: Bool
    let lineChanges: [[String: Any]]
    let selectedSectionBefore: WorkspacePageSectionRecord?
    let selectedSectionAfter: WorkspacePageSectionRecord?
    let emptyParagraphsRemoved: Int
    let formatWarnings: [WorkspacePageFormatWarning]

    func toJSON() -> [String: Any] {
        var json = updated.toDetailJSON()
        json["dry_run"] = true
        json["changed"] = changed
        json["line_changes"] = lineChanges
        if let selectedSectionAfter {
            json["selected_section"] = selectedSectionAfter.toJSON()
        }
        if let selectedSectionBefore {
            json["selected_section_before"] = selectedSectionBefore.toJSON()
        }
        return json
    }
}

struct WorkspacePageFormatWarning {
    let kind: String
    let blockID: String
    let pageName: String
    let reason: String
    let matches: [String]
    let message: String

    func toJSON() -> [String: Any] {
        var json: [String: Any] = [
            "kind": kind,
            "block_id": blockID,
            "page_name": pageName,
            "reason": reason,
            "message": message,
        ]
        if !matches.isEmpty {
            json["matches"] = matches
        }
        return json
    }
}

func pageWriteSummaryJSON(
    _ record: WorkspacePageRecord,
    operation: String,
    changed: Bool? = nil
) -> [String: Any] {
    var json = record.toSummaryJSON()
    json["operation"] = operation
    if operation == "create" {
        json["created"] = true
    } else {
        json["updated"] = true
    }
    if let changed {
        json["changed"] = changed
    }
    return json
}

func pageUpdateSummaryJSON(
    _ preview: WorkspacePageUpdatePreview,
    dryRun: Bool
) -> [String: Any] {
    pageMutationSummaryJSON(preview, operation: "update", dryRun: dryRun)
}

func pageMutationSummaryJSON(
    _ record: WorkspacePageRecord,
    preview: WorkspacePageUpdatePreview,
    operation: String,
    dryRun: Bool
) -> [String: Any] {
    var json = pageWriteSummaryJSON(
        record,
        operation: operation,
        changed: preview.changed
    )
    if let selectedSectionAfter = preview.selectedSectionAfter {
        json["selected_section"] = selectedSectionAfter.toJSON(includeContent: false)
    }
    if let selectedSectionBefore = preview.selectedSectionBefore {
        json["selected_section_before"] = selectedSectionBefore.toJSON(includeContent: false)
    }
    if dryRun {
        json["dry_run"] = true
        json["line_changes"] = preview.lineChanges
    }
    return json
}

func pageMutationSummaryJSON(
    _ preview: WorkspacePageUpdatePreview,
    operation: String,
    dryRun: Bool
) -> [String: Any] {
    pageMutationSummaryJSON(preview.updated, preview: preview, operation: operation, dryRun: dryRun)
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
        // Fall back to database row pages (structured content directories)
        let rowMatches = try workspacePageMatches(for: query, workspace: normalizedWorkspace, includeStructuredContent: true)
        if rowMatches.count == 1, let match = rowMatches.first {
            return match.path
        }
        if rowMatches.isEmpty {
            throw CLIError.invalidInput("Page not found: \(query)")
        }
        let rowOptions = rowMatches.map(\.relativePath).sorted().joined(separator: ", ")
        throw CLIError.invalidInput("Page reference is ambiguous: \(query). Matches: \(rowOptions)")
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
    section: String? = nil,
    sectionLine: Int? = nil,
    createSectionIfMissing: Bool = false,
    sectionLevel: Int? = nil,
    replacementContent: String? = nil,
    prependContent: String? = nil,
    appendContent: String? = nil
) throws -> WorkspacePageRecord {
    let preview = try previewWorkspacePageUpdate(
        query: query,
        workspace: workspace,
        section: section,
        sectionLine: sectionLine,
        createSectionIfMissing: createSectionIfMissing,
        sectionLevel: sectionLevel,
        replacementContent: replacementContent,
        prependContent: prependContent,
        appendContent: appendContent
    )

    try preview.updated.content.write(toFile: preview.original.path, atomically: true, encoding: .utf8)
    return try loadWorkspacePage(at: preview.original.path, relativeTo: workspace)
}

func previewWorkspacePageUpdate(
    query: String,
    workspace: String,
    section: String? = nil,
    sectionLine: Int? = nil,
    createSectionIfMissing: Bool = false,
    sectionLevel: Int? = nil,
    replacementContent: String? = nil,
    prependContent: String? = nil,
    appendContent: String? = nil
) throws -> WorkspacePageUpdatePreview {
    if replacementContent != nil && (prependContent != nil || appendContent != nil) {
        throw CLIError.invalidInput("Use --content-file by itself, or use --prepend-file/--append-file without --content-file")
    }

    let existing = try resolveWorkspacePage(query, workspace: workspace)
    var nextContent = replacementContent ?? existing.content
    let trimmedSection = section?.trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedSectionBefore: WorkspacePageSectionRecord?
    if createSectionIfMissing && sectionLine == nil {
        selectedSectionBefore = try? resolveWorkspacePageSection(
            existing,
            headingQuery: trimmedSection,
            sectionLine: nil
        )
    } else {
        selectedSectionBefore = try resolveWorkspacePageSection(
            existing,
            headingQuery: trimmedSection,
            sectionLine: sectionLine
        )
    }

    if (trimmedSection?.isEmpty == false) || sectionLine != nil {
        nextContent = try updateMarkdownSection(
            in: existing.content,
            headingQuery: trimmedSection,
            sectionLine: sectionLine,
            createSectionIfMissing: createSectionIfMissing,
            sectionLevel: sectionLevel,
            replacementContent: replacementContent,
            prependContent: prependContent,
            appendContent: appendContent
        )
    } else {
        if let prependContent, !prependContent.isEmpty {
            nextContent = prependContent + nextContent
        }
        if let appendContent, !appendContent.isEmpty {
            nextContent += appendContent
        }
    }

    let updated = workspacePageRecord(from: existing, content: nextContent)
    let selectedSectionAfter = try resolveWorkspacePageSection(
        updated,
        headingQuery: trimmedSection,
        sectionLine: sectionLine
    )
    return WorkspacePageUpdatePreview(
        original: existing,
        updated: updated,
        changed: existing.content != nextContent,
        lineChanges: structuredLineChanges(from: existing.content, to: nextContent),
        selectedSectionBefore: selectedSectionBefore,
        selectedSectionAfter: selectedSectionAfter,
        emptyParagraphsRemoved: 0,
        formatWarnings: []
    )
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

func pageHeadingsJSON(for page: WorkspacePageRecord) -> [String: Any] {
    [
        "page": page.relativePath,
        "title": page.title,
        "headings": markdownHeadingsJSON(in: page.content),
    ]
}

func presentedMarkdown(_ markdown: String, includeInternalComments: Bool = false) -> String {
    if includeInternalComments {
        return markdown
    }
    return stripInternalBlockIDComments(from: markdown)
}

func stripInternalBlockIDComments(from markdown: String) -> String {
    guard markdown.contains("<!-- block-id:") else {
        return markdown
    }

    let hadTrailingNewline = markdown.hasSuffix("\n")
    let filteredLines = markdown
        .components(separatedBy: .newlines)
        .filter { !isInternalBlockIDCommentLine($0) }

    let output = filteredLines.joined(separator: "\n")
    if hadTrailingNewline, !output.isEmpty, !output.hasSuffix("\n") {
        return output + "\n"
    }
    return output
}

func resolveWorkspacePageSection(
    _ page: WorkspacePageRecord,
    headingQuery: String? = nil,
    sectionLine: Int? = nil
) throws -> WorkspacePageSectionRecord? {
    let trimmedHeadingQuery = headingQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
    let headingSpecifier = trimmedHeadingQuery.map(parseHeadingSpecifier)
    let hasHeadingQuery = headingSpecifier?.title.isEmpty == false
    guard hasHeadingQuery || sectionLine != nil else {
        return nil
    }

    let split = splitRawFrontmatter(from: page.content)
    let bodyLines = split.body.components(separatedBy: .newlines)
    let prefixLineCount = lineCount(in: split.prefix)
    guard let section = try resolveMarkdownSection(
        in: bodyLines,
        headingQuery: hasHeadingQuery ? headingSpecifier?.title : nil,
        headingLevel: headingSpecifier?.explicitLevel,
        sectionLine: sectionLine,
        prefixLineCount: prefixLineCount
    ) else {
        if let sectionLine {
            throw CLIError.invalidInput("Heading not found at line: \(sectionLine)")
        }
        throw CLIError.invalidInput("Heading not found: \(trimmedHeadingQuery ?? "")")
    }

    return workspacePageSectionRecord(from: section, bodyLines: bodyLines, prefixLineCount: prefixLineCount)
}

private func workspacePageMatches(for query: String, workspace: String, includeStructuredContent: Bool = false) throws -> [WorkspacePageLookupCandidate] {
    let candidates = collectWorkspacePageLookupCandidates(in: workspace, includeStructuredContent: includeStructuredContent)
    let needle = normalizePageLookup(query)

    let directMatches = candidates.filter { candidate in
        normalizePageLookup(candidate.relativePath) == needle
            || normalizePageLookup((candidate.relativePath as NSString).deletingPathExtension) == needle
            || normalizePageLookup(candidate.name) == needle
            || normalizePageLookup(stripRowIDSuffix(candidate.name)) == needle
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

private func collectWorkspacePageLookupCandidates(in workspace: String, includeStructuredContent: Bool = false) -> [WorkspacePageLookupCandidate] {
    var candidates: [WorkspacePageLookupCandidate] = []
    walkWorkspaceMarkdownFiles(in: workspace, includeStructuredContent: includeStructuredContent) { filePath, relativePath in
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

private func prependedMarkdownBlock(_ block: String, to content: String) -> String {
    let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedBlock.isEmpty else { return content }

    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return trimmedBlock + "\n"
    }

    var result = trimmedBlock
    if !result.hasSuffix("\n") {
        result += "\n"
    }
    if !result.hasSuffix("\n\n") {
        result += "\n"
    }

    let trimmedContent = content.trimmingCharacters(in: .newlines)
    result += trimmedContent
    if !result.hasSuffix("\n") {
        result += "\n"
    }
    return result
}

private struct RawFrontmatterSplit {
    let prefix: String
    let body: String
}

private struct MarkdownHeadingSection {
    let headingIndex: Int
    let bodyStartIndex: Int
    let endIndex: Int
    let title: String
    let level: Int
}

private struct HeadingSpecifier {
    let title: String
    let explicitLevel: Int?
}

private func updateMarkdownSection(
    in content: String,
    headingQuery: String?,
    sectionLine: Int?,
    createSectionIfMissing: Bool,
    sectionLevel: Int?,
    replacementContent: String?,
    prependContent: String?,
    appendContent: String?
) throws -> String {
    let split = splitRawFrontmatter(from: content)
    let bodyLines = split.body.components(separatedBy: .newlines)
    let prefixLineCount = lineCount(in: split.prefix)
    let headingSpecifier = headingQuery.map(parseHeadingSpecifier)

    let existingSection = try resolveMarkdownSection(
        in: bodyLines,
        headingQuery: headingSpecifier?.title,
        headingLevel: headingSpecifier?.explicitLevel,
        sectionLine: sectionLine,
        prefixLineCount: prefixLineCount
    )
    let currentBody = existingSection.map { Array(bodyLines[$0.bodyStartIndex..<$0.endIndex]).joined(separator: "\n") } ?? ""
    var nextSectionBody = replacementContent ?? currentBody

    if let prependContent, !prependContent.isEmpty {
        nextSectionBody = prependedMarkdownBlock(prependContent, to: nextSectionBody)
    }
    if let appendContent, !appendContent.isEmpty {
        nextSectionBody = appendedMarkdownBlock(appendContent, to: nextSectionBody)
    }

    guard let section = existingSection else {
        if let sectionLine {
            throw CLIError.invalidInput("Heading not found at line: \(sectionLine)")
        }
        guard let headingSpecifier, let headingQuery else {
            throw CLIError.invalidInput("Section selector is required")
        }
        if !createSectionIfMissing {
            throw CLIError.invalidInput("Heading not found: \(headingQuery)")
        }
        let level = max(1, min(6, sectionLevel ?? headingSpecifier.explicitLevel ?? 2))
        let headingLine = "\(String(repeating: "#", count: level)) \(headingSpecifier.title)"
        let sectionMarkdown = nextSectionBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? headingLine
            : "\(headingLine)\n\n\(nextSectionBody.trimmingCharacters(in: .whitespacesAndNewlines))"
        return split.prefix + appendedMarkdownBlock(sectionMarkdown, to: split.body)
    }

    var updatedLines = Array(bodyLines[..<section.bodyStartIndex])
    if !nextSectionBody.isEmpty {
        updatedLines.append(contentsOf: nextSectionBody.components(separatedBy: .newlines))
    }
    if section.endIndex < bodyLines.count {
        updatedLines.append(contentsOf: bodyLines[section.endIndex...])
    }

    return split.prefix + updatedLines.joined(separator: "\n")
}

private func splitRawFrontmatter(from content: String) -> RawFrontmatterSplit {
    guard content.hasPrefix("---") else {
        return RawFrontmatterSplit(prefix: "", body: content)
    }

    let lines = content.components(separatedBy: .newlines)
    guard lines.first == "---" else {
        return RawFrontmatterSplit(prefix: "", body: content)
    }

    for index in 1..<lines.count where lines[index] == "---" {
        let prefix = Array(lines[0...index]).joined(separator: "\n") + "\n"
        let body = lines.dropFirst(index + 1).joined(separator: "\n")
        return RawFrontmatterSplit(prefix: prefix, body: body)
    }

    return RawFrontmatterSplit(prefix: "", body: content)
}

private func resolveMarkdownSection(
    in lines: [String],
    headingQuery: String? = nil,
    headingLevel: Int? = nil,
    sectionLine: Int? = nil,
    prefixLineCount: Int = 0
) throws -> MarkdownHeadingSection? {
    let sections = markdownSections(in: lines)

    if let sectionLine {
        guard sectionLine > 0 else {
            throw CLIError.invalidInput("Section line must be greater than 0")
        }
        return sections.first { prefixLineCount + $0.headingIndex + 1 == sectionLine }
    }

    guard let headingQuery else {
        return nil
    }

    let normalizedQuery = normalizeHeadingQuery(headingQuery)
    let matches = sections.filter { section in
        guard normalizeHeadingQuery(section.title) == normalizedQuery else {
            return false
        }
        if let headingLevel {
            return section.level == headingLevel
        }
        return true
    }

    if matches.isEmpty {
        return nil
    }
    if matches.count > 1 {
        let labels = matches.map { section in
            let line = prefixLineCount + section.headingIndex + 1
            return "\(String(repeating: "#", count: section.level)) \(section.title) @ line \(line)"
        }.joined(separator: ", ")
        throw CLIError.invalidInput("Heading reference is ambiguous: \(headingQuery). Matches: \(labels)")
    }

    return matches[0]
}

private func markdownSections(in lines: [String]) -> [MarkdownHeadingSection] {
    var matches: [MarkdownHeadingSection] = []
    for index in lines.indices {
        guard let (level, title) = parseMarkdownHeadingLine(lines[index]) else {
            continue
        }

        var endIndex = lines.count
        if index + 1 < lines.count {
            for candidate in (index + 1)..<lines.count {
                guard let (candidateLevel, _) = parseMarkdownHeadingLine(lines[candidate]) else { continue }
                if candidateLevel <= level {
                    endIndex = candidate
                    break
                }
            }
        }

        matches.append(
            MarkdownHeadingSection(
                headingIndex: index,
                bodyStartIndex: index + 1,
                endIndex: endIndex,
                title: title,
                level: level
            )
        )
    }
    return matches
}

private func parseMarkdownHeadingLine(_ line: String) -> (Int, String)? {
    guard line.hasPrefix("#") else { return nil }
    var level = 0
    for character in line {
        if character == "#" {
            level += 1
        } else {
            break
        }
    }
    guard level >= 1, level <= 6, line.count > level else { return nil }
    let index = line.index(line.startIndex, offsetBy: level)
    guard line[index] == " " else { return nil }
    return (level, String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines))
}

private func normalizeHeadingQuery(_ value: String) -> String {
    var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.hasPrefix("#") {
        trimmed.removeFirst()
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed.lowercased()
}

private func parseHeadingSpecifier(_ value: String) -> HeadingSpecifier {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    var level = 0
    for character in trimmed {
        if character == "#" {
            level += 1
        } else {
            break
        }
    }

    if level > 0, level <= 6, trimmed.count > level {
        let index = trimmed.index(trimmed.startIndex, offsetBy: level)
        if trimmed[index] == " " {
            let title = String(trimmed[trimmed.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return HeadingSpecifier(title: title, explicitLevel: level)
            }
        }
    }

    return HeadingSpecifier(title: trimmed, explicitLevel: nil)
}

private func markdownHeadingsJSON(in content: String) -> [[String: Any]] {
    let split = splitRawFrontmatter(from: content)
    let bodyLines = split.body.components(separatedBy: .newlines)
    let prefixLineCount = lineCount(in: split.prefix)
    var headings: [[String: Any]] = []

    for index in bodyLines.indices {
        guard let (level, title) = parseMarkdownHeadingLine(bodyLines[index]) else { continue }
        let line = prefixLineCount + index + 1
        headings.append([
            "level": level,
            "title": title,
            "line": line,
            "body_line": line + 1,
        ])
    }

    return headings
}

private func lineCount(in content: String) -> Int {
    guard !content.isEmpty else { return 0 }
    let components = content.components(separatedBy: .newlines)
    return content.hasSuffix("\n") ? max(components.count - 1, 0) : components.count
}

private func isInternalBlockIDCommentLine(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") else { return false }
    let inner = trimmed.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespaces)
    guard inner.lowercased().hasPrefix("block-id:") else { return false }
    let raw = String(inner.dropFirst("block-id:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return UUID(uuidString: raw) != nil
}

func structuredLineChanges(from before: String, to after: String) -> [[String: Any]] {
    let beforeLines = before.components(separatedBy: .newlines)
    let afterLines = after.components(separatedBy: .newlines)
    return afterLines.difference(from: beforeLines).map { change in
        switch change {
        case .remove(let offset, let element, _):
            return [
                "op": "remove",
                "line": offset + 1,
                "text": element,
            ]
        case .insert(let offset, let element, _):
            return [
                "op": "insert",
                "line": offset + 1,
                "text": element,
            ]
        }
    }
}

private func workspacePageSectionRecord(
    from section: MarkdownHeadingSection,
    bodyLines: [String],
    prefixLineCount: Int
) -> WorkspacePageSectionRecord {
    let content = Array(bodyLines[section.headingIndex..<section.endIndex]).joined(separator: "\n")
    let body = Array(bodyLines[section.bodyStartIndex..<section.endIndex]).joined(separator: "\n")
    let headingLine = prefixLineCount + section.headingIndex + 1
    let bodyLine = prefixLineCount + section.bodyStartIndex + 1
    let endLine = prefixLineCount + max(section.endIndex, section.headingIndex + 1)

    return WorkspacePageSectionRecord(
        title: section.title,
        level: section.level,
        headingLine: headingLine,
        bodyLine: bodyLine,
        endLine: endLine,
        content: content,
        body: body
    )
}

func workspacePageRecord(from existing: WorkspacePageRecord, content: String) -> WorkspacePageRecord {
    let (frontmatter, body) = parsePageFrontmatter(content)
    let title = pageTitle(body: body, fallback: existing.name, frontmatter: frontmatter)
    let tags = pageTags(frontmatter: frontmatter, body: body)
    let wikilinks = extractWikiLinks(from: body)

    return WorkspacePageRecord(
        path: existing.path,
        relativePath: existing.relativePath,
        name: existing.name,
        title: title,
        content: content,
        body: body,
        frontmatter: frontmatter,
        tags: tags,
        wikilinks: wikilinks,
        modifiedAt: existing.modifiedAt
    )
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

func relativePath(fromDirectory sourceDirectory: String, to targetPath: String) -> String {
    let sourceComponents = sourceDirectory
        .replacingOccurrences(of: "\\", with: "/")
        .split(separator: "/")
        .map(String.init)
    let targetComponents = targetPath
        .replacingOccurrences(of: "\\", with: "/")
        .split(separator: "/")
        .map(String.init)

    var commonLength = 0
    while commonLength < sourceComponents.count,
          commonLength < targetComponents.count,
          sourceComponents[commonLength] == targetComponents[commonLength] {
        commonLength += 1
    }

    var parts = Array(repeating: "..", count: sourceComponents.count - commonLength)
    parts.append(contentsOf: targetComponents[commonLength...])
    return parts.isEmpty ? "." : parts.joined(separator: "/")
}

private func sanitizePageFileName(_ value: String) -> String {
    let sanitized = value.replacingOccurrences(
        of: "[/\\\\?%*:|\"<>]",
        with: "-",
        options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? "Untitled" : sanitized
}

func companionFolderPath(for pagePath: String) -> String {
    (pagePath as NSString).deletingPathExtension
}

func pageDisplayName(fromPath path: String) -> String {
    let filename = (path as NSString).lastPathComponent
    return filename.hasSuffix(".md") ? String(filename.dropLast(3)) : filename
}

private func stripRowIDSuffix(_ name: String) -> String {
    // Database row filenames have the format "Name (row_id)" — strip the trailing " (id)" for matching
    guard let range = name.range(of: #" \([a-zA-Z0-9_]+\)$"#, options: .regularExpression) else {
        return name
    }
    return String(name[name.startIndex..<range.lowerBound])
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
