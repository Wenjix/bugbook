import Foundation
import SwiftUI
import BugbookCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Block Model

private enum MdBlockType {
    case heading(level: Int)
    case paragraph
    case bullet(depth: Int)
    case numbered(depth: Int, number: Int)
    case task(depth: Int, checked: Bool)
    case codeBlock(language: String)
    case blockquote
    case horizontalRule
    case image(alt: String, url: String)
    case wikiLink(name: String)
    case databaseEmbed(path: String)
}

private struct MdBlock: Identifiable {
    let id = UUID()
    let type: MdBlockType
    let content: String
}

// MARK: - Parser

private enum MdParser {

    static func parse(_ markdown: String) -> [MdBlock] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MdBlock] = []
        var i = 0

        // Skip YAML frontmatter
        if i < lines.count && lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            i += 1
            while i < lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "---" { i += 1; break }
                i += 1
            }
        }

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(MdBlock(type: .codeBlock(language: language), content: codeLines.joined(separator: "\n")))
                continue
            }

            // Horizontal rule
            if isHorizontalRule(line) {
                blocks.append(MdBlock(type: .horizontalRule, content: ""))
                i += 1
                continue
            }

            // Heading
            if let (level, text) = parseHeading(line) {
                blocks.append(MdBlock(type: .heading(level: level), content: text))
                i += 1
                continue
            }

            // Task item (before bullet to avoid conflict)
            if let (depth, checked, text) = parseTaskItem(line) {
                blocks.append(MdBlock(type: .task(depth: depth, checked: checked), content: text))
                i += 1
                continue
            }

            // Bullet list
            if let (depth, text) = parseBulletItem(line) {
                blocks.append(MdBlock(type: .bullet(depth: depth), content: text))
                i += 1
                continue
            }

            // Numbered list
            if let (depth, text) = parseNumberedItem(line) {
                // Compute number from consecutive run
                let num = computeNumber(for: blocks, depth: depth)
                blocks.append(MdBlock(type: .numbered(depth: depth, number: num), content: text))
                i += 1
                continue
            }

            // Blockquote
            if line.hasPrefix(">") {
                let text: String
                if line.count > 1, line[line.index(after: line.startIndex)] == " " {
                    text = String(line.dropFirst(2))
                } else {
                    text = String(line.dropFirst(1))
                }
                blocks.append(MdBlock(type: .blockquote, content: text))
                i += 1
                continue
            }

            // Image
            if let (alt, url) = parseImage(line) {
                blocks.append(MdBlock(type: .image(alt: alt, url: url), content: ""))
                i += 1
                continue
            }

            // Database embed
            if let path = parseDatabaseEmbed(line) {
                blocks.append(MdBlock(type: .databaseEmbed(path: path), content: ""))
                i += 1
                continue
            }

            // Wiki link (standalone line)
            if let name = parseWikiLink(line) {
                blocks.append(MdBlock(type: .wikiLink(name: name), content: ""))
                i += 1
                continue
            }

            // Skip non-rendering HTML comments anywhere in the file.
            if isHTMLComment(line) {
                i += 1
                continue
            }

            // Paragraph
            blocks.append(MdBlock(type: .paragraph, content: line))
            i += 1
        }

        return blocks
    }

    // MARK: Line parsers

    private static func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let chars = Set(trimmed.filter { $0 != " " })
        return chars.count == 1 && (chars.contains("-") || chars.contains("*") || chars.contains("_"))
    }

    private static func parseHeading(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6, line.count > level else { return nil }
        let idx = line.index(line.startIndex, offsetBy: level)
        guard line[idx] == " " else { return nil }
        return (level, String(line[line.index(after: idx)...]))
    }

    private static func parseTaskItem(_ line: String) -> (Int, Bool, String)? {
        let stripped = line.drop(while: { $0 == " " })
        let indent = line.count - stripped.count
        let depth = indent / 2
        guard stripped.count >= 6 else { return nil }
        let marker = stripped.first!
        guard marker == "-" || marker == "*" || marker == "+" else { return nil }
        let rest = stripped.dropFirst(1)
        guard rest.hasPrefix(" [") else { return nil }
        let afterBracket = rest.dropFirst(2)
        guard let checkChar = afterBracket.first else { return nil }
        guard checkChar == " " || checkChar == "x" || checkChar == "X" else { return nil }
        let afterCheck = afterBracket.dropFirst(1)
        guard afterCheck.hasPrefix("] ") else { return nil }
        return (depth, checkChar != " ", String(afterCheck.dropFirst(2)))
    }

    private static func parseBulletItem(_ line: String) -> (Int, String)? {
        let stripped = line.drop(while: { $0 == " " })
        let indent = line.count - stripped.count
        let depth = indent / 2
        guard stripped.count >= 2 else { return nil }
        let marker = stripped.first!
        guard marker == "-" || marker == "*" || marker == "+" else { return nil }
        let rest = stripped.dropFirst(1)
        guard rest.hasPrefix(" ") else { return nil }
        return (depth, String(rest.dropFirst(1)))
    }

    private static func parseNumberedItem(_ line: String) -> (Int, String)? {
        let stripped = line.drop(while: { $0 == " " })
        let indent = line.count - stripped.count
        let depth = indent / 2
        var digitEnd = stripped.startIndex
        while digitEnd < stripped.endIndex, stripped[digitEnd].isNumber {
            digitEnd = stripped.index(after: digitEnd)
        }
        guard digitEnd > stripped.startIndex else { return nil }
        guard digitEnd < stripped.endIndex, stripped[digitEnd] == "." else { return nil }
        let afterDot = stripped.index(after: digitEnd)
        guard afterDot < stripped.endIndex, stripped[afterDot] == " " else { return nil }
        return (depth, String(stripped[stripped.index(after: afterDot)...]))
    }

    private static func parseImage(_ line: String) -> (String, String)? {
        guard line.hasPrefix("![") else { return nil }
        guard let altEnd = line.range(of: "](") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<altEnd.lowerBound])
        let srcStart = altEnd.upperBound
        guard let parenEnd = line[srcStart...].firstIndex(of: ")") else { return nil }
        return (alt, String(line[srcStart..<parenEnd]))
    }

    private static func parseWikiLink(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") else { return nil }
        let name = String(trimmed.dropFirst(2).dropLast(2))
        return name.isEmpty ? nil : name
    }

    private static func parseDatabaseEmbed(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("<!--"),
           trimmed.hasSuffix("-->"),
           let marker = trimmed.range(of: "database:") {
            let pathStart = marker.upperBound
            let pathEnd = trimmed.index(trimmed.endIndex, offsetBy: -3)
            guard pathStart < pathEnd else { return nil }
            let path = String(trimmed[pathStart..<pathEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        }

        if let markdownLinkPath = parseDatabaseMarkdownLink(trimmed) {
            return markdownLinkPath
        }

        return parseDatabaseSchemePath(trimmed)
    }

    private static func parseDatabaseMarkdownLink(_ line: String) -> String? {
        guard line.hasPrefix("["),
              line.hasSuffix(")"),
              let split = line.range(of: "](") else { return nil }
        let urlPart = String(line[split.upperBound..<line.index(before: line.endIndex)])
        return parseDatabaseSchemePath(urlPart)
    }

    private static func parseDatabaseSchemePath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("database:") else { return nil }

        var target = String(trimmed.dropFirst("database:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        if target.isEmpty { return nil }

        if target.lowercased().hasPrefix("file://"), let url = URL(string: target) {
            target = url.path
        } else if target.hasPrefix("///") {
            target = "/" + String(target.dropFirst(3))
        } else if target.hasPrefix("//") {
            target = "/" + String(target.dropFirst(2))
        }

        if target.hasPrefix("~") {
            target = (target as NSString).expandingTildeInPath
        }
        if target.contains("%"), let decoded = target.removingPercentEncoding {
            target = decoded
        }
        if target.hasSuffix("/_schema.json") {
            target = (target as NSString).deletingLastPathComponent
        }

        return target
    }

    private static func isHTMLComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<!--") && trimmed.hasSuffix("-->")
    }

    private static func computeNumber(for blocks: [MdBlock], depth: Int) -> Int {
        var count = 1
        for block in blocks.reversed() {
            switch block.type {
            case .numbered(let d, _) where d == depth:
                count += 1
            case .numbered(let d, _) where d > depth:
                continue
            default:
                return count
            }
        }
        return count
    }
}

// MARK: - Inline text rendering

private func renderInlineText(_ text: String) -> Text {
    // Handle wiki-links inline: replace [[Name]] with styled text, then use AttributedString for the rest
    let wikiPattern = #"\[\[([^\]]+)\]\]"#
    guard let regex = try? NSRegularExpression(pattern: wikiPattern) else {
        return attributedText(text)
    }

    let nsText = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

    if matches.isEmpty {
        return attributedText(text)
    }

    var result = Text("")
    var lastEnd = 0

    for match in matches {
        let matchRange = match.range
        let nameRange = match.range(at: 1)

        // Text before this wiki-link
        if matchRange.location > lastEnd {
            let before = nsText.substring(with: NSRange(location: lastEnd, length: matchRange.location - lastEnd))
            result = result + attributedText(before)
        }

        // The wiki-link itself
        let name = nsText.substring(with: nameRange)
        result = result + Text(name).foregroundStyle(.blue)

        lastEnd = matchRange.location + matchRange.length
    }

    // Remaining text after last wiki-link
    if lastEnd < nsText.length {
        let remaining = nsText.substring(from: lastEnd)
        result = result + attributedText(remaining)
    }

    return result
}

private func attributedText(_ text: String) -> Text {
    if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
        return Text(attributed)
    }
    return Text(text)
}

// MARK: - Block Views

private struct HeadingBlockView: View {
    let level: Int
    let content: String

    var body: some View {
        renderInlineText(content)
            .font(headingFont)
            .fontWeight(.bold)
    }

    private var headingFont: Font {
        switch level {
        case 1: .largeTitle
        case 2: .title
        default: .title3
        }
    }
}

private struct BulletBlockView: View {
    let depth: Int
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
            renderInlineText(content)
        }
        .padding(.leading, CGFloat(depth) * 20)
    }
}

private struct NumberedBlockView: View {
    let depth: Int
    let number: Int
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(number).")
                .monospacedDigit()
            renderInlineText(content)
        }
        .padding(.leading, CGFloat(depth) * 20)
    }
}

private struct TaskBlockView: View {
    let depth: Int
    let checked: Bool
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? .green : .secondary)
                .font(.body)
            renderInlineText(content)
                .strikethrough(checked)
                .foregroundStyle(checked ? .secondary : .primary)
        }
        .padding(.leading, CGFloat(depth) * 20)
    }
}

private struct CodeBlockView: View {
    let language: String
    let content: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !language.isEmpty {
                Text(language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct BlockquoteBlockView: View {
    let content: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary)
                .frame(width: 3)
            renderInlineText(content)
                .italic()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct ImageBlockView: View {
    let alt: String
    let urlString: String
    let pagePath: String?
    let workspacePath: String?

    private var remoteURL: URL? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              !scheme.isEmpty,
              !url.isFileURL else {
            return nil
        }
        return url
    }

    private var localImagePath: String? {
        resolveWorkspaceAttachmentPath(
            urlString,
            pagePath: pagePath,
            workspacePath: workspacePath
        )
    }

    var body: some View {
        #if canImport(UIKit)
        if let localImagePath,
           let image = UIImage(contentsOfFile: localImagePath) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let url = remoteURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    Label(alt.isEmpty ? "Image failed to load" : alt, systemImage: "photo")
                        .foregroundStyle(.secondary)
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
        } else if !alt.isEmpty {
            Label(alt, systemImage: "photo")
                .foregroundStyle(.secondary)
        }
        #else
        if let url = remoteURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    Label(alt.isEmpty ? "Image failed to load" : alt, systemImage: "photo")
                        .foregroundStyle(.secondary)
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
        } else if !alt.isEmpty {
            Label(alt, systemImage: "photo")
                .foregroundStyle(.secondary)
        }
        #endif
    }
}

private struct DatabaseEmbedSummary {
    let resolvedPath: String?
    let title: String
    let subtitle: String
}

private struct DatabaseEmbedCardView: View {
    let storedPath: String
    let pagePath: String?
    let workspacePath: String?

    private var summary: DatabaseEmbedSummary {
        let resolvedPath = resolveMobileDatabaseEmbedPath(
            storedPath,
            pagePath: pagePath,
            workspacePath: workspacePath
        )
        let title = resolvedPath.flatMap { mobileDatabaseDisplayName(at: $0) } ?? mobileDatabaseFallbackName(from: storedPath)
        let subtitle: String

        if let resolvedPath {
            let rowCount = mobileDatabaseRowCount(at: resolvedPath)
            subtitle = "\(rowCount) item\(rowCount == 1 ? "" : "s")"
        } else {
            subtitle = "Database unavailable"
        }

        return DatabaseEmbedSummary(
            resolvedPath: resolvedPath,
            title: title,
            subtitle: subtitle
        )
    }

    var body: some View {
        Group {
            if let resolvedPath = summary.resolvedPath {
                NavigationLink {
                    MobileDatabaseView(dbPath: resolvedPath)
                } label: {
                    cardLabel(showChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                cardLabel(showChevron: false)
            }
        }
    }

    private func cardLabel(showChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tablecells")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.mobileTextSecondary)
                .frame(width: 36, height: 36)
                .background(Color.mobileCardBg)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.mobileTextPrimary)
                    .lineLimit(1)

                Text(summary.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mobileTextMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mobileUtilityIcon)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mobileBgSecondary)
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.mobileBorder, lineWidth: 0.5)
        }
    }
}

private func resolveMobileDatabaseEmbedPath(
    _ storedPath: String,
    pagePath: String?,
    workspacePath: String?,
    fileManager: FileManager = .default
) -> String? {
    let normalizedStoredPath = normalizeMobileDatabasePath(storedPath)
    guard !normalizedStoredPath.isEmpty else { return nil }

    if mobileIsDatabaseFolderPath(normalizedStoredPath, fileManager: fileManager) {
        return normalizedStoredPath
    }

    let storedName = (normalizedStoredPath as NSString).lastPathComponent
    var candidates: [String] = []

    if let pagePath {
        let pageContainer = pagePath.hasSuffix(".md") ? String(pagePath.dropLast(3)) : pagePath
        if !storedName.isEmpty {
            candidates.append((pageContainer as NSString).appendingPathComponent(storedName))
        }
        candidates.append(contentsOf: mobileMatchingDatabaseChildren(
            named: storedName,
            in: pageContainer,
            fileManager: fileManager
        ))
    }

    if let workspacePath, !workspacePath.isEmpty {
        if !storedName.isEmpty {
            candidates.append((workspacePath as NSString).appendingPathComponent(storedName))
        }
        if let uniqueMatch = mobileFindUniqueDatabasePath(
            named: storedName,
            in: workspacePath,
            fileManager: fileManager
        ) {
            candidates.append(uniqueMatch)
        }
    }

    var seen: Set<String> = []
    for candidate in candidates.map({ ($0 as NSString).standardizingPath }) where seen.insert(candidate).inserted {
        if mobileIsDatabaseFolderPath(candidate, fileManager: fileManager) {
            return candidate
        }
    }

    return nil
}

private func normalizeMobileDatabasePath(_ path: String) -> String {
    var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)

    if normalized.hasPrefix("~") {
        normalized = (normalized as NSString).expandingTildeInPath
    }
    if normalized.contains("%"), let decoded = normalized.removingPercentEncoding {
        normalized = decoded
    }
    if normalized.hasSuffix("/_schema.json") {
        normalized = (normalized as NSString).deletingLastPathComponent
    }

    return (normalized as NSString).standardizingPath
}

private func mobileMatchingDatabaseChildren(
    named name: String,
    in directory: String,
    fileManager: FileManager
) -> [String] {
    guard !name.isEmpty,
          fileManager.fileExists(atPath: directory),
          let entries = try? fileManager.contentsOfDirectory(atPath: directory) else {
        return []
    }

    return entries.compactMap { entryName in
        let childPath = (directory as NSString).appendingPathComponent(entryName)
        guard mobileIsDatabaseFolderPath(childPath, fileManager: fileManager) else { return nil }

        let folderNameMatches = entryName.localizedCaseInsensitiveCompare(name) == .orderedSame
        let schemaNameMatches = mobileDatabaseDisplayName(at: childPath, fileManager: fileManager)?
            .localizedCaseInsensitiveCompare(name) == .orderedSame

        return (folderNameMatches || schemaNameMatches) ? childPath : nil
    }
}

private func mobileFindUniqueDatabasePath(
    named name: String,
    in workspacePath: String,
    fileManager: FileManager
) -> String? {
    guard !name.isEmpty,
          let enumerator = fileManager.enumerator(atPath: workspacePath) else {
        return nil
    }

    var matches: [String] = []

    while let relativePath = enumerator.nextObject() as? String {
        if WorkspacePathRules.shouldIgnoreRelativePath(relativePath) {
            enumerator.skipDescendants()
            continue
        }

        let fullPath = (workspacePath as NSString).appendingPathComponent(relativePath)
        guard mobileIsDatabaseFolderPath(fullPath, fileManager: fileManager) else { continue }

        let folderName = (fullPath as NSString).lastPathComponent
        let schemaName = mobileDatabaseDisplayName(at: fullPath, fileManager: fileManager)
        if folderName.localizedCaseInsensitiveCompare(name) == .orderedSame
            || schemaName?.localizedCaseInsensitiveCompare(name) == .orderedSame {
            matches.append(fullPath)
            if matches.count > 1 {
                return nil
            }
        }

        enumerator.skipDescendants()
    }

    return matches.first
}

private func mobileDatabaseDisplayName(
    at path: String,
    fileManager: FileManager = .default
) -> String? {
    let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
    guard fileManager.fileExists(atPath: schemaPath),
          let data = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)),
          let schema = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let name = schema["name"] as? String,
          !name.isEmpty else {
        return nil
    }
    return name
}

private func mobileDatabaseRowCount(at path: String, fileManager: FileManager = .default) -> Int {
    guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return 0 }
    return contents.filter { $0.hasSuffix(".md") && !$0.hasPrefix("_") }.count
}

private func mobileIsDatabaseFolderPath(_ path: String, fileManager: FileManager = .default) -> Bool {
    let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
    return fileManager.fileExists(atPath: schemaPath)
}

private func mobileDatabaseFallbackName(from storedPath: String) -> String {
    let rawName = ((storedPath as NSString).lastPathComponent as NSString).deletingPathExtension
    let cleaned = rawName
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "Database" : cleaned
}

// MARK: - Grouped block helpers

private struct GroupedBlock: Identifiable {
    let id = UUID()
    let blocks: [MdBlock]

    enum GroupKind {
        case blockquote
        case single
    }
    let kind: GroupKind
}

private func groupBlocks(_ blocks: [MdBlock]) -> [GroupedBlock] {
    var result: [GroupedBlock] = []
    var quoteAccumulator: [MdBlock] = []

    func flushQuotes() {
        if !quoteAccumulator.isEmpty {
            result.append(GroupedBlock(blocks: quoteAccumulator, kind: .blockquote))
            quoteAccumulator = []
        }
    }

    for block in blocks {
        switch block.type {
        case .blockquote:
            quoteAccumulator.append(block)
        default:
            flushQuotes()
            result.append(GroupedBlock(blocks: [block], kind: .single))
        }
    }
    flushQuotes()
    return result
}

// MARK: - Main View

struct MobileMarkdownView: View {
    let content: String
    let pagePath: String?
    let workspacePath: String?

    init(content: String, pagePath: String? = nil, workspacePath: String? = nil) {
        self.content = content
        self.pagePath = pagePath
        self.workspacePath = workspacePath
    }

    private var parsedGroups: [GroupedBlock] {
        groupBlocks(MdParser.parse(content))
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(parsedGroups) { group in
                switch group.kind {
                case .blockquote:
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(group.blocks) { block in
                            BlockquoteBlockView(content: block.content)
                        }
                    }
                case .single:
                    if let block = group.blocks.first {
                        blockView(for: block)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: MdBlock) -> some View {
        switch block.type {
        case .heading(let level):
            HeadingBlockView(level: level, content: block.content)
                .padding(.top, level == 1 ? 12 : 8)

        case .paragraph:
            if block.content.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer().frame(height: 4)
            } else {
                renderInlineText(block.content)
            }

        case .bullet(let depth):
            BulletBlockView(depth: depth, content: block.content)

        case .numbered(let depth, let number):
            NumberedBlockView(depth: depth, number: number, content: block.content)

        case .task(let depth, let checked):
            TaskBlockView(depth: depth, checked: checked, content: block.content)

        case .codeBlock(let language):
            CodeBlockView(language: language, content: block.content)

        case .blockquote:
            BlockquoteBlockView(content: block.content)

        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)

        case .image(let alt, let url):
            ImageBlockView(
                alt: alt,
                urlString: url,
                pagePath: pagePath,
                workspacePath: workspacePath
            )

        case .wikiLink(let name):
            Text(name)
                .foregroundStyle(.blue)

        case .databaseEmbed(let path):
            DatabaseEmbedCardView(
                storedPath: path,
                pagePath: pagePath,
                workspacePath: workspacePath
            )
        }
    }
}
