import Foundation

struct WorkspacePageBlockRecord {
    let id: String
    let stableID: Bool
    let persistedID: String?
    let path: [Int]
    let type: String
    let content: String
    let json: [String: Any]

    func toJSON(includeContent: Bool = true) -> [String: Any] {
        var output = json
        if includeContent {
            output["content"] = content
        }
        return output
    }
}

struct WorkspacePageBlockUpdatePreview {
    let original: WorkspacePageRecord
    let updated: WorkspacePageRecord
    let changed: Bool
    let lineChanges: [[String: Any]]
    let selectedBlockBefore: WorkspacePageBlockRecord
    let selectedBlocksAfter: [WorkspacePageBlockRecord]

    func toJSON() -> [String: Any] {
        var json = updated.toDetailJSON()
        json["dry_run"] = true
        json["changed"] = changed
        json["line_changes"] = lineChanges
        json["selected_block_before"] = selectedBlockBefore.toJSON()
        json["selected_blocks_after"] = selectedBlocksAfter.map { $0.toJSON() }
        return json
    }
}

func blockUpdateSummaryJSON(
    _ preview: WorkspacePageBlockUpdatePreview,
    operation: String,
    dryRun: Bool
) -> [String: Any] {
    blockUpdateSummaryJSON(preview.updated, preview: preview, operation: operation, dryRun: dryRun)
}

func blockUpdateSummaryJSON(
    _ record: WorkspacePageRecord,
    preview: WorkspacePageBlockUpdatePreview,
    operation: String,
    dryRun: Bool
) -> [String: Any] {
    var json = pageWriteSummaryJSON(
        record,
        operation: operation,
        changed: preview.changed
    )
    json["selected_block_before"] = preview.selectedBlockBefore.toJSON(includeContent: false)
    json["selected_blocks_after"] = preview.selectedBlocksAfter.map {
        $0.toJSON(includeContent: false)
    }
    if dryRun {
        json["dry_run"] = true
        json["line_changes"] = preview.lineChanges
    }
    return json
}

private struct PageFrontmatterSplit {
    let prefix: String
    let body: String
}

private struct ParsedPageDocument {
    var metadata: ParsedPageDocumentMetadata
    var blocks: [ParsedPageBlock]
}

private enum ParsedPageBlockType: String {
    case paragraph
    case heading
    case bulletListItem = "bullet_list_item"
    case numberedListItem = "numbered_list_item"
    case taskItem = "task_item"
    case codeBlock = "code_block"
    case blockquote
    case horizontalRule = "horizontal_rule"
    case image
    case databaseEmbed = "database_embed"
    case pageLink = "page_link"
    case column
    case toggle
}

private struct ParsedPageBlock {
    var id: String
    var stableID: Bool
    var type: ParsedPageBlockType
    var text: String = ""
    var headingLevel: Int = 1
    var listDepth: Int = 0
    var isChecked: Bool = false
    var language: String = ""
    var imageSource: String = ""
    var imageAlt: String = ""
    var imageWidth: Int?
    var databasePath: String = ""
    var pageLinkName: String = ""
    var commonmarkLinkDestination: String?
    var textColor: String?
    var backgroundColor: String?
    var children: [ParsedPageBlock] = []
    var columnIndex: Int = 0
    var isExpanded: Bool = true
}

private struct ParsedPageDocumentMetadata {
    var icon: String?
    var coverURL: String?
    var coverPosition: Double = 50
    var fullWidth: Bool = false

    func toJSON() -> [String: Any] {
        var json: [String: Any] = [
            "cover_position": coverPosition,
            "full_width": fullWidth,
        ]
        if let icon, !icon.isEmpty {
            json["icon"] = icon
        }
        if let coverURL, !coverURL.isEmpty {
            json["cover_url"] = coverURL
        }
        return json
    }
}

private struct ParsedPageBlockLookup {
    let block: ParsedPageBlock
    let path: [Int]
}

private struct ParsedPageBlockMutationResult {
    let before: ParsedPageBlockLookup
    let afterPaths: [[Int]]
}

private struct CommonMarkPageLinkResolver {
    enum Result {
        case resolved(String)
        case downgraded(reason: String, matches: [String])
    }

    private let directMatchesByToken: [String: [WorkspacePageRecord]]
    private let titleMatchesByToken: [String: [WorkspacePageRecord]]
    private let sourceDirectory: String

    init(sourcePage: WorkspacePageRecord, workspace: String) throws {
        let pages = try listWorkspacePages(in: workspace)
        var directLookup: [String: [WorkspacePageRecord]] = [:]
        var titleLookup: [String: [WorkspacePageRecord]] = [:]

        func insert(_ record: WorkspacePageRecord, for token: String, into lookup: inout [String: [WorkspacePageRecord]]) {
            guard !token.isEmpty else {
                return
            }
            if lookup[token]?.contains(where: { $0.relativePath == record.relativePath }) == true {
                return
            }
            lookup[token, default: []].append(record)
        }

        for page in pages {
            insert(page, for: normalizePageLookup(page.relativePath), into: &directLookup)
            insert(page, for: normalizePageLookup((page.relativePath as NSString).deletingPathExtension), into: &directLookup)
            insert(page, for: normalizePageLookup(page.name), into: &directLookup)
            insert(page, for: normalizePageLookup(page.title), into: &titleLookup)
        }

        directMatchesByToken = directLookup
        titleMatchesByToken = titleLookup
        sourceDirectory = (sourcePage.relativePath as NSString).deletingLastPathComponent
    }

    func resolve(_ pageName: String) -> Result {
        let token = normalizePageLookup(pageName)
        guard !token.isEmpty else {
            return .downgraded(reason: "page_not_found", matches: [])
        }
        let matches = (directMatchesByToken[token]?.isEmpty == false)
            ? directMatchesByToken[token]
            : titleMatchesByToken[token]
        guard let matches else {
            return .downgraded(reason: "page_not_found", matches: [])
        }
        if matches.count > 1 {
            return .downgraded(
                reason: "ambiguous_page_reference",
                matches: matches.map(\.relativePath).sorted()
            )
        }
        guard let target = matches.first?.relativePath else {
            return .downgraded(reason: "page_not_found", matches: [])
        }
        return .resolved(relativePath(fromDirectory: sourceDirectory, to: target))
    }
}

private enum PageBlockParser {
    static func parseDocument(_ markdown: String) -> ParsedPageDocument {
        let (metadata, content) = parseMetadata(markdown)
        var blocks = parseBlocks(content)
        _ = compactEmptyParagraphBlocks(in: &blocks)
        return ParsedPageDocument(metadata: metadata, blocks: blocks)
    }

    static func parseBlocks(_ markdown: String) -> [ParsedPageBlock] {
        guard !markdown.isEmpty else {
            return [ParsedPageBlock(id: newBlockID(), stableID: false, type: .paragraph)]
        }

        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count > 1, lines.last == "" {
            lines.removeLast()
        }
        var blocks: [ParsedPageBlock] = []
        var index = 0
        var pendingBlockID: String?
        var pendingStableID = false
        var pendingTextColor: String?
        var pendingBackgroundColor: String?

        func makeBlock(
            type: ParsedPageBlockType = .paragraph,
            text: String = "",
            headingLevel: Int = 1,
            listDepth: Int = 0,
            isChecked: Bool = false,
            language: String = "",
            imageSource: String = "",
            imageAlt: String = "",
            imageWidth: Int? = nil,
            databasePath: String = "",
            pageLinkName: String = "",
            children: [ParsedPageBlock] = [],
            columnIndex: Int = 0,
            isExpanded: Bool = true
        ) -> ParsedPageBlock {
            let block = ParsedPageBlock(
                id: pendingBlockID ?? newBlockID(),
                stableID: pendingStableID,
                type: type,
                text: text,
                headingLevel: headingLevel,
                listDepth: listDepth,
                isChecked: isChecked,
                language: language,
                imageSource: imageSource,
                imageAlt: imageAlt,
                imageWidth: imageWidth,
                databasePath: databasePath,
                pageLinkName: pageLinkName,
                textColor: pendingTextColor,
                backgroundColor: pendingBackgroundColor,
                children: children,
                columnIndex: columnIndex,
                isExpanded: isExpanded
            )
            pendingBlockID = nil
            pendingStableID = false
            pendingTextColor = nil
            pendingBackgroundColor = nil
            return block
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let blockID = parseBlockIDComment(line) {
                pendingBlockID = blockID
                pendingStableID = true
                index += 1
                continue
            }

            if let (textColor, backgroundColor) = parseColorComment(line) {
                pendingTextColor = textColor
                pendingBackgroundColor = backgroundColor
                index += 1
                continue
            }

            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    if lines[index].hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(makeBlock(type: .codeBlock, text: codeLines.joined(separator: "\n"), language: language))
                continue
            }

            if isHorizontalRule(line) {
                blocks.append(makeBlock(type: .horizontalRule, text: line))
                index += 1
                continue
            }

            if let (level, text) = parseHeading(line) {
                blocks.append(makeBlock(type: .heading, text: text, headingLevel: level))
                index += 1
                continue
            }

            if let (depth, checked, text) = parseTaskItem(line) {
                blocks.append(makeBlock(type: .taskItem, text: text, listDepth: depth, isChecked: checked))
                index += 1
                continue
            }

            if let (depth, text) = parseBulletItem(line) {
                blocks.append(makeBlock(type: .bulletListItem, text: text, listDepth: depth))
                index += 1
                continue
            }

            if let (depth, text) = parseNumberedItem(line) {
                blocks.append(makeBlock(type: .numberedListItem, text: text, listDepth: depth))
                index += 1
                continue
            }

            if line.hasPrefix(">") {
                let text: String
                if line.count > 1, line[line.index(after: line.startIndex)] == " " {
                    text = String(line.dropFirst(2))
                } else {
                    text = String(line.dropFirst(1))
                }
                blocks.append(makeBlock(type: .blockquote, text: text))
                index += 1
                continue
            }

            if let (alt, src, width) = parseImage(line) {
                blocks.append(makeBlock(type: .image, imageSource: src, imageAlt: alt, imageWidth: width))
                index += 1
                continue
            }

            if let path = parseDatabaseEmbed(line) {
                blocks.append(makeBlock(type: .databaseEmbed, databasePath: path))
                index += 1
                continue
            }

            if let name = parseWikiLink(line) {
                if let dbPath = parseDatabaseSchemePath(name) {
                    blocks.append(makeBlock(type: .databaseEmbed, databasePath: dbPath))
                } else {
                    blocks.append(makeBlock(type: .pageLink, pageLinkName: name))
                }
                index += 1
                continue
            }

            if let name = parsePageLinkComment(line) {
                blocks.append(makeBlock(type: .pageLink, pageLinkName: name))
                index += 1
                continue
            }

            if trimmed == "<!-- toggle -->" || trimmed == "<!-- toggle collapsed -->" {
                let collapsed = trimmed.contains("collapsed")
                index += 1
                let title = index < lines.count ? lines[index] : ""
                index += 1

                var childLines: [String] = []
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces) == "<!-- /toggle -->" {
                        index += 1
                        break
                    }
                    childLines.append(lines[index])
                    index += 1
                }

                blocks.append(
                    makeBlock(
                        type: .toggle,
                        text: title,
                        children: childLines.isEmpty ? [] : parseBlocks(childLines.joined(separator: "\n")),
                        isExpanded: !collapsed
                    )
                )
                continue
            }

            if trimmed == "<!-- columns -->" {
                var allChildren: [ParsedPageBlock] = []
                var currentColumnIndex = 0
                var currentColumnLines: [String] = []
                index += 1

                while index < lines.count {
                    let columnLine = lines[index]
                    let columnTrimmed = columnLine.trimmingCharacters(in: .whitespaces)
                    if columnTrimmed == "<!-- /columns -->" {
                        index += 1
                        break
                    }
                    if columnTrimmed == "<!-- column-separator -->" {
                        if !currentColumnLines.isEmpty {
                            var columnBlocks = parseBlocks(currentColumnLines.joined(separator: "\n"))
                            for childIndex in columnBlocks.indices {
                                columnBlocks[childIndex].columnIndex = currentColumnIndex
                            }
                            allChildren.append(contentsOf: columnBlocks)
                        }
                        currentColumnLines = []
                        currentColumnIndex += 1
                        index += 1
                        continue
                    }
                    currentColumnLines.append(columnLine)
                    index += 1
                }

                if !currentColumnLines.isEmpty {
                    var columnBlocks = parseBlocks(currentColumnLines.joined(separator: "\n"))
                    for childIndex in columnBlocks.indices {
                        columnBlocks[childIndex].columnIndex = currentColumnIndex
                    }
                    allChildren.append(contentsOf: columnBlocks)
                }

                blocks.append(makeBlock(type: .column, children: allChildren))
                continue
            }

            blocks.append(makeBlock(type: .paragraph, text: unescapeParagraphText(line)))
            index += 1
        }

        if blocks.isEmpty {
            return [ParsedPageBlock(id: newBlockID(), stableID: false, type: .paragraph)]
        }

        return blocks
    }

    static func serializeDocument(
        _ document: ParsedPageDocument,
        includeBlockIDComments: Bool = true,
        style: PageMarkdownFormatStyle = .bugbook
    ) -> String {
        let metadata = serializeMetadata(document.metadata)
        let body = serialize(
            document.blocks,
            includeBlockIDComments: includeBlockIDComments,
            style: style
        )
        if metadata.isEmpty {
            return body
        }
        if body.isEmpty {
            return metadata
        }
        let separator = style == .commonmark ? "\n\n" : "\n"
        return metadata + separator + body
    }

    static func serializeBlocks(
        _ blocks: [ParsedPageBlock],
        includeBlockIDComments: Bool = false,
        style: PageMarkdownFormatStyle = .bugbook
    ) -> String {
        serialize(blocks, includeBlockIDComments: includeBlockIDComments, style: style)
    }

    private static func parseMetadata(_ markdown: String) -> (ParsedPageDocumentMetadata, String) {
        var metadata = ParsedPageDocumentMetadata()
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var contentStartIndex = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("<!-- icon:") && trimmed.hasSuffix("-->") {
                let inner = trimmed.dropFirst(10).dropLast(3).trimmingCharacters(in: .whitespaces)
                metadata.icon = inner.isEmpty ? nil : inner
                contentStartIndex += 1
                continue
            }

            if trimmed.hasPrefix("<!-- cover:") && trimmed.hasSuffix("-->") {
                let inner = trimmed.dropFirst(11).dropLast(3).trimmingCharacters(in: .whitespaces)
                if let atRange = inner.range(of: "@", options: .backwards) {
                    metadata.coverURL = String(inner[..<atRange.lowerBound])
                    metadata.coverPosition = Double(inner[atRange.upperBound...]) ?? 50
                } else {
                    metadata.coverURL = inner.isEmpty ? nil : inner
                }
                contentStartIndex += 1
                continue
            }

            if trimmed == "<!-- full-width -->" {
                metadata.fullWidth = true
                contentStartIndex += 1
                continue
            }

            break
        }

        let remaining = Array(lines.dropFirst(contentStartIndex)).joined(separator: "\n")
        return (metadata, remaining)
    }

    private static func serializeMetadata(_ metadata: ParsedPageDocumentMetadata) -> String {
        var lines: [String] = []
        if let icon = metadata.icon, !icon.isEmpty {
            lines.append("<!-- icon:\(icon) -->")
        }
        if let cover = metadata.coverURL, !cover.isEmpty {
            lines.append("<!-- cover:\(cover)@\(Int(metadata.coverPosition)) -->")
        }
        if metadata.fullWidth {
            lines.append("<!-- full-width -->")
        }
        return lines.joined(separator: "\n")
    }

    private static func serialize(
        _ blocks: [ParsedPageBlock],
        includeBlockIDComments: Bool,
        style: PageMarkdownFormatStyle
    ) -> String {
        serializeLines(
            blocks,
            includeBlockIDComments: includeBlockIDComments,
            style: style
        ).joined(separator: "\n")
    }

    private static func serializeLines(
        _ blocks: [ParsedPageBlock],
        includeBlockIDComments: Bool,
        style: PageMarkdownFormatStyle
    ) -> [String] {
        let chunks = blocks.enumerated().map { index, block in
            serializeChunk(
                block,
                at: index,
                in: blocks,
                includeBlockIDComments: includeBlockIDComments,
                style: style
            )
        }

        switch style {
        case .bugbook:
            return chunks.flatMap { $0 }
        case .commonmark:
            var lines: [String] = []
            for index in chunks.indices {
                if index > 0,
                   shouldInsertCommonMarkBlankLine(between: blocks[index - 1], and: blocks[index]),
                   !lines.isEmpty,
                   lines.last != "" {
                    lines.append("")
                }
                lines.append(contentsOf: chunks[index])
            }
            return lines
        }
    }

    private static func serializeChunk(
        _ block: ParsedPageBlock,
        at index: Int,
        in siblings: [ParsedPageBlock],
        includeBlockIDComments: Bool,
        style: PageMarkdownFormatStyle
    ) -> [String] {
        var lines: [String] = []

        if includeBlockIDComments, style == .bugbook {
            lines.append("<!-- block-id: \(block.id) -->")
        }

        let hasColor = block.textColor != nil || block.backgroundColor != nil
        if hasColor, style == .bugbook, block.type != .column, block.type != .toggle {
            var parts: [String] = []
            if let textColor = block.textColor, !textColor.isEmpty {
                parts.append("color:\(textColor)")
            }
            if let backgroundColor = block.backgroundColor, !backgroundColor.isEmpty {
                parts.append("bg:\(backgroundColor)")
            }
            if !parts.isEmpty {
                lines.append("<!-- \(parts.joined(separator: " ")) -->")
            }
        }

        switch block.type {
        case .paragraph:
            lines.append(escapedParagraphText(block.text))

        case .heading:
            let hashes = String(repeating: "#", count: max(1, min(6, block.headingLevel)))
            lines.append("\(hashes) \(block.text)")

        case .bulletListItem:
            let indent = String(repeating: "  ", count: block.listDepth)
            lines.append("\(indent)- \(block.text)")

        case .numberedListItem:
            let indent = String(repeating: "  ", count: block.listDepth)
            let number = computeNumberedPosition(at: index, depth: block.listDepth, in: siblings)
            lines.append("\(indent)\(number). \(block.text)")

        case .taskItem:
            let indent = String(repeating: "  ", count: block.listDepth)
            let check = block.isChecked ? "x" : " "
            lines.append("\(indent)- [\(check)] \(block.text)")

        case .blockquote:
            lines.append("> \(block.text)")

        case .codeBlock:
            lines.append("```\(block.language)")
            lines.append(block.text)
            lines.append("```")

        case .horizontalRule:
            lines.append("---")

        case .image:
            var line = "![\(block.imageAlt)](\(block.imageSource))"
            if let imageWidth = block.imageWidth {
                line += "{width=\(imageWidth)}"
            }
            lines.append(line)

        case .databaseEmbed:
            switch style {
            case .bugbook:
                lines.append("<!-- database: \(block.databasePath) -->")
            case .commonmark:
                lines.append("**Bugbook database:** \(pageDisplayName(fromPath: block.databasePath))")
            }

        case .pageLink:
            switch style {
            case .bugbook:
                lines.append("[[\(block.pageLinkName)]]")
            case .commonmark:
                if let destination = block.commonmarkLinkDestination, !destination.isEmpty {
                    lines.append("[\(escapeMarkdownLinkText(block.pageLinkName))](<\(destination)>)")
                } else {
                    lines.append(escapedParagraphText(block.pageLinkName))
                }
            }

        case .toggle:
            switch style {
            case .bugbook:
                lines.append(block.isExpanded ? "<!-- toggle -->" : "<!-- toggle collapsed -->")
                lines.append(block.text)
                if !block.children.isEmpty {
                    lines.append(contentsOf: serializeLines(
                        block.children,
                        includeBlockIDComments: includeBlockIDComments,
                        style: style
                    ))
                }
                lines.append("<!-- /toggle -->")
            case .commonmark:
                lines.append(block.isExpanded ? "<details open>" : "<details>")
                lines.append("<summary>\(escapeHTML(block.text))</summary>")
                if !block.children.isEmpty {
                    lines.append("")
                    lines.append(contentsOf: serializeLines(
                        block.children,
                        includeBlockIDComments: false,
                        style: style
                    ))
                    if lines.last != "" {
                        lines.append("")
                    }
                }
                lines.append("</details>")
            }

        case .column:
            let maxColumn = block.children.map(\.columnIndex).max() ?? 0
            switch style {
            case .bugbook:
                lines.append("<!-- columns -->")
                for columnIndex in 0...maxColumn {
                    if columnIndex > 0 {
                        lines.append("<!-- column-separator -->")
                    }
                    let columnBlocks = block.children.filter { $0.columnIndex == columnIndex }
                    if !columnBlocks.isEmpty {
                        lines.append(contentsOf: serializeLines(
                            columnBlocks,
                            includeBlockIDComments: includeBlockIDComments,
                            style: style
                        ))
                    }
                }
                lines.append("<!-- /columns -->")
            case .commonmark:
                var emittedColumn = false
                for columnIndex in 0...maxColumn {
                    let columnBlocks = block.children.filter { $0.columnIndex == columnIndex }
                    guard !columnBlocks.isEmpty else { continue }
                    if emittedColumn {
                        if !lines.isEmpty, lines.last != "" {
                            lines.append("")
                        }
                        lines.append("---")
                        lines.append("")
                    }
                    lines.append(contentsOf: serializeLines(
                        columnBlocks,
                        includeBlockIDComments: false,
                        style: style
                    ))
                    emittedColumn = true
                }
            }
        }

        return lines
    }

    private static func shouldInsertCommonMarkBlankLine(
        between previous: ParsedPageBlock,
        and next: ParsedPageBlock
    ) -> Bool {
        if isListItem(previous), isListItem(next) {
            return false
        }
        if previous.type == .blockquote, next.type == .blockquote {
            return false
        }
        return true
    }

    private static func isListItem(_ block: ParsedPageBlock) -> Bool {
        switch block.type {
        case .bulletListItem, .numberedListItem, .taskItem:
            return true
        default:
            return false
        }
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeMarkdownLinkText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let characters = Set(trimmed.filter { $0 != " " })
        return characters.count == 1 && (characters.contains("-") || characters.contains("*") || characters.contains("_"))
    }

    private static func escapedParagraphText(_ text: String) -> String {
        let (leadingSpaces, remainder) = splitLeadingSpaces(text)
        let slashCount = leadingBackslashCount(in: remainder)
        let tail = String(remainder.dropFirst(slashCount))
        guard paragraphNeedsProtection(leadingSpaces + tail) else {
            return text
        }
        return leadingSpaces + String(repeating: "\\", count: slashCount + 1) + tail
    }

    private static func unescapeParagraphText(_ line: String) -> String {
        let (leadingSpaces, remainder) = splitLeadingSpaces(line)
        let slashCount = leadingBackslashCount(in: remainder)
        guard slashCount > 0 else {
            return line
        }
        let tail = String(remainder.dropFirst(slashCount))
        guard paragraphNeedsProtection(leadingSpaces + tail) else {
            return line
        }
        return leadingSpaces + String(repeating: "\\", count: slashCount - 1) + tail
    }

    private static func splitLeadingSpaces(_ line: String) -> (String, String) {
        let prefix = line.prefix(while: { $0 == " " })
        return (String(prefix), String(line.dropFirst(prefix.count)))
    }

    private static func leadingBackslashCount(in text: String) -> Int {
        text.prefix(while: { $0 == "\\" }).count
    }

    private static func paragraphNeedsProtection(_ line: String) -> Bool {
        guard !line.isEmpty else {
            return false
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if parseBlockIDComment(line) != nil || parseColorComment(line) != nil {
            return true
        }
        if line.hasPrefix("```") || isHorizontalRule(line) || parseHeading(line) != nil {
            return true
        }
        if parseTaskItem(line) != nil || parseBulletItem(line) != nil || parseNumberedItem(line) != nil {
            return true
        }
        if line.hasPrefix(">") || parseImage(line) != nil || parseDatabaseEmbed(line) != nil || parseWikiLink(line) != nil || parsePageLinkComment(line) != nil {
            return true
        }
        return trimmed == "<!-- toggle -->"
            || trimmed == "<!-- toggle collapsed -->"
            || trimmed == "<!-- /toggle -->"
            || trimmed == "<!-- columns -->"
            || trimmed == "<!-- column-separator -->"
            || trimmed == "<!-- /columns -->"
    }

    private static func parseHeading(_ line: String) -> (Int, String)? {
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
        return (level, String(line[line.index(after: index)...]))
    }

    private static func parseTaskItem(_ line: String) -> (Int, Bool, String)? {
        let stripped = line.drop(while: { $0 == " " })
        let depth = (line.count - stripped.count) / 2
        guard stripped.count >= 6 else { return nil }
        guard let marker = stripped.first, marker == "-" || marker == "*" || marker == "+" else { return nil }
        let rest = stripped.dropFirst()
        guard rest.hasPrefix(" [") else { return nil }
        let afterBracket = rest.dropFirst(2)
        guard let check = afterBracket.first, check == " " || check == "x" || check == "X" else { return nil }
        let afterCheck = afterBracket.dropFirst()
        guard afterCheck.hasPrefix("] ") else { return nil }
        return (depth, check != " ", String(afterCheck.dropFirst(2)))
    }

    private static func parseBulletItem(_ line: String) -> (Int, String)? {
        let stripped = line.drop(while: { $0 == " " })
        let depth = (line.count - stripped.count) / 2
        guard stripped.count >= 2 else { return nil }
        guard let marker = stripped.first, marker == "-" || marker == "*" || marker == "+" else { return nil }
        let rest = stripped.dropFirst()
        guard rest.hasPrefix(" ") else { return nil }
        return (depth, String(rest.dropFirst()))
    }

    private static func parseNumberedItem(_ line: String) -> (Int, String)? {
        let stripped = line.drop(while: { $0 == " " })
        let depth = (line.count - stripped.count) / 2

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

    private static func parseImage(_ line: String) -> (String, String, Int?)? {
        guard line.hasPrefix("![") else { return nil }
        guard let altEnd = line.range(of: "](") else { return nil }
        let altStart = line.index(line.startIndex, offsetBy: 2)
        let alt = String(line[altStart..<altEnd.lowerBound])
        let srcStart = altEnd.upperBound
        guard let parenEnd = line[srcStart...].firstIndex(of: ")") else { return nil }
        let src = String(line[srcStart..<parenEnd])

        var width: Int?
        let afterParen = line.index(after: parenEnd)
        if afterParen < line.endIndex {
            let rest = String(line[afterParen...])
            if rest.hasPrefix("{width="), rest.hasSuffix("}") {
                width = Int(rest.dropFirst(7).dropLast(1))
            }
        }

        return (alt, src, width)
    }

    private static func parseDatabaseEmbed(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->"),
           let marker = trimmed.range(of: "database:") {
            let pathStart = marker.upperBound
            let pathEnd = trimmed.index(trimmed.endIndex, offsetBy: -3)
            guard pathStart < pathEnd else { return nil }
            let path = String(trimmed[pathStart..<pathEnd]).trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? nil : path
        }

        if let markdownLinkPath = parseDatabaseMarkdownLink(trimmed) {
            return markdownLinkPath
        }

        return parseDatabaseSchemePath(trimmed)
    }

    private static func parseDatabaseMarkdownLink(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              trimmed.hasSuffix(")"),
              let split = trimmed.range(of: "](") else { return nil }
        let urlPart = String(trimmed[split.upperBound..<trimmed.index(before: trimmed.endIndex)])
        return parseDatabaseSchemePath(urlPart)
    }

    private static func parseDatabaseSchemePath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("database:") else { return nil }

        var target = String(trimmed.dropFirst("database:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        if target.isEmpty { return nil }

        if target.hasPrefix("///") {
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

        guard target.hasPrefix("/") else { return nil }
        return target
    }

    private static func parseWikiLink(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") else { return nil }
        let name = String(trimmed.dropFirst(2).dropLast(2))
        return name.isEmpty ? nil : name
    }

    private static func parsePageLinkComment(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") else { return nil }
        let prefixes = ["bugbook-page-link:", "page-link:"]
        for prefix in prefixes {
            if let marker = trimmed.range(of: prefix) {
                let nameStart = marker.upperBound
                let nameEnd = trimmed.index(trimmed.endIndex, offsetBy: -3)
                guard nameStart < nameEnd else { return nil }
                let name = String(trimmed[nameStart..<nameEnd]).trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    private static func parseBlockIDComment(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") else { return nil }
        let inner = trimmed.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespaces)
        guard inner.lowercased().hasPrefix("block-id:") else { return nil }
        let raw = String(inner.dropFirst("block-id:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: raw)?.uuidString.lowercased()
    }

    private static func parseColorComment(_ line: String) -> (String?, String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") else { return nil }
        let inner = trimmed.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespaces)
        guard inner.contains("color:") || inner.contains("bg:") else { return nil }
        guard !inner.contains("database:") else { return nil }

        var textColor: String?
        var backgroundColor: String?
        for part in inner.split(separator: " ") {
            if part.hasPrefix("color:") {
                let value = String(part.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                textColor = value.isEmpty ? nil : value
            } else if part.hasPrefix("bg:") {
                let value = String(part.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                backgroundColor = value.isEmpty ? nil : value
            }
        }

        if textColor == nil, backgroundColor == nil {
            return nil
        }
        return (textColor, backgroundColor)
    }

    private static func computeNumberedPosition(
        at index: Int,
        depth: Int,
        in blocks: [ParsedPageBlock]
    ) -> Int {
        var number = 1
        guard index > 0 else { return number }
        for previousIndex in stride(from: index - 1, through: 0, by: -1) {
            let previous = blocks[previousIndex]
            guard previous.type == .numberedListItem else {
                if previous.type != .paragraph || !previous.text.isEmpty {
                    break
                }
                continue
            }
            if previous.listDepth < depth {
                break
            }
            if previous.listDepth == depth {
                number += 1
            }
        }
        return number
    }
}

func parsedPageDocumentJSON(from markdown: String) -> [String: Any] {
    let document = PageBlockParser.parseDocument(markdown)
    return [
        "document_metadata": document.metadata.toJSON(),
        "blocks": parsedPageBlocksJSON(document.blocks),
    ]
}

func previewWorkspacePageFormat(
    query: String,
    workspace: String,
    style: PageMarkdownFormatStyle
) throws -> WorkspacePageUpdatePreview {
    let existing = try resolveWorkspacePage(query, workspace: workspace)
    let (split, document) = parseWorkspacePageDocument(from: existing.content)
    let persistBlockIDComments = style == .bugbook && documentHasPersistedBlockIDs(document.blocks)

    var formattedBlocks = document.blocks
    var formatWarnings: [WorkspacePageFormatWarning] = []
    let emptyParagraphsRemoved = compactEmptyParagraphBlocks(in: &formattedBlocks)
    if style == .commonmark, parsedPageBlocksContainPageLinks(formattedBlocks) {
        let resolver = try CommonMarkPageLinkResolver(sourcePage: existing, workspace: workspace)
        let resolution = resolveCommonMarkPageLinks(in: formattedBlocks, using: resolver)
        formattedBlocks = resolution.blocks
        formatWarnings = resolution.warnings
    }
    let formattedDocument = ParsedPageDocument(metadata: document.metadata, blocks: formattedBlocks)
    let nextContent = split.prefix + PageBlockParser.serializeDocument(
        formattedDocument,
        includeBlockIDComments: persistBlockIDComments,
        style: style
    )
    let updated = workspacePageRecord(from: existing, content: nextContent)

    return WorkspacePageUpdatePreview(
        original: existing,
        updated: updated,
        changed: existing.content != nextContent,
        lineChanges: structuredLineChanges(from: existing.content, to: nextContent),
        selectedSectionBefore: nil,
        selectedSectionAfter: nil,
        emptyParagraphsRemoved: emptyParagraphsRemoved,
        formatWarnings: formatWarnings
    )
}

func previewWorkspacePageCompact(
    query: String,
    workspace: String
) throws -> WorkspacePageUpdatePreview {
    try previewWorkspacePageFormat(
        query: query,
        workspace: workspace,
        style: .bugbook
    )
}

func ensureWorkspacePageBlockIDs(query: String, workspace: String) throws -> [String: Any] {
    let existing = try resolveWorkspacePage(query, workspace: workspace)
    let (split, document) = parseWorkspacePageDocument(from: existing.content)
    var normalizedBlocks = document.blocks
    let changed = normalizeStableBlockIDs(in: &normalizedBlocks)
    let normalizedDocument = ParsedPageDocument(metadata: document.metadata, blocks: normalizedBlocks)

    let finalRecord: WorkspacePageRecord
    let finalDocument: ParsedPageDocument
    if changed {
        let nextContent = split.prefix + PageBlockParser.serializeDocument(normalizedDocument, includeBlockIDComments: true)
        try nextContent.write(toFile: existing.path, atomically: true, encoding: .utf8)
        finalRecord = try loadWorkspacePage(at: existing.path, relativeTo: workspace)
        finalDocument = parseWorkspacePageDocument(from: finalRecord.content).document
    } else {
        finalRecord = existing
        finalDocument = normalizedDocument
    }

    return [
        "page": finalRecord.relativePath,
        "title": finalRecord.title,
        "changed": changed,
        "stable_block_ids": true,
        "block_count": parsedPageBlockCount(finalDocument.blocks),
        "blocks": parsedPageBlocksJSON(finalDocument.blocks),
    ]
}

func stripWorkspacePageBlockIDs(query: String, workspace: String) throws -> [String: Any] {
    let existing = try resolveWorkspacePage(query, workspace: workspace)
    let (split, document) = parseWorkspacePageDocument(from: existing.content)
    let changed = documentHasPersistedBlockIDs(document.blocks)

    let finalRecord: WorkspacePageRecord
    if changed {
        let nextContent = split.prefix + PageBlockParser.serializeDocument(document, includeBlockIDComments: false)
        try nextContent.write(toFile: existing.path, atomically: true, encoding: .utf8)
        finalRecord = try loadWorkspacePage(at: existing.path, relativeTo: workspace)
    } else {
        finalRecord = existing
    }

    return [
        "page": finalRecord.relativePath,
        "title": finalRecord.title,
        "changed": changed,
        "stable_block_ids": false,
        "block_count": parsedPageBlockCount(document.blocks),
    ]
}

func resolveWorkspacePageBlock(_ page: WorkspacePageRecord, selector: String) throws -> WorkspacePageBlockRecord {
    let document = parseWorkspacePageDocument(from: page.content).document
    return try lookupBlock(in: document.blocks, selector: selector)
}

private func lookupBlock(in blocks: [ParsedPageBlock], selector: String) throws -> WorkspacePageBlockRecord {
    let matches = findParsedPageBlocks(in: blocks, selector: selector)
    guard let lookup = matches.first else {
        throw CLIError.invalidInput("Block not found: \(selector)")
    }
    if parsePathSelector(selector) == nil, matches.count > 1 {
        throw CLIError.invalidInput(
            "Block selector is ambiguous because multiple blocks share persisted ID \(selector). Run `page ensure-block-ids` or use a path: selector."
        )
    }
    return workspacePageBlockRecord(from: lookup)
}

func previewWorkspacePageBlockUpdate(
    query: String,
    workspace: String,
    blockSelector: String,
    replacementContent: String? = nil,
    prependContent: String? = nil,
    appendContent: String? = nil
) throws -> WorkspacePageBlockUpdatePreview {
    if replacementContent != nil && (prependContent != nil || appendContent != nil) {
        throw CLIError.invalidInput("Use --content-file by itself, or use --prepend-file/--append-file without --content-file")
    }

    let existing = try resolveWorkspacePage(query, workspace: workspace)
    let (split, document) = parseWorkspacePageDocument(from: existing.content)
    let beforeBlock = try lookupBlock(in: document.blocks, selector: blockSelector)
    let persistBlockIDComments = documentHasPersistedBlockIDs(document.blocks)

    var updatedBlocks = document.blocks
    if persistBlockIDComments {
        _ = normalizeStableBlockIDs(in: &updatedBlocks)
    }
    var usedIDs = collectBlockIDs(in: updatedBlocks)

    let replacementBlocks = replacementContent.map(parseReplacementBlocks)
    let prependBlocks = prependContent.map(parseInsertedBlocks) ?? []
    let appendBlocks = appendContent.map(parseInsertedBlocks) ?? []

    guard let mutation = applyBlockMutation(
        in: &updatedBlocks,
        selector: blockSelector,
        replacementBlocks: replacementBlocks,
        prependBlocks: prependBlocks,
        appendBlocks: appendBlocks,
        usedIDs: &usedIDs
    ) else {
        throw CLIError.invalidInput("Block not found: \(blockSelector)")
    }

    if persistBlockIDComments {
        _ = normalizeStableBlockIDs(in: &updatedBlocks)
    }

    let updatedDocument = ParsedPageDocument(metadata: document.metadata, blocks: updatedBlocks)
    let nextContent = split.prefix + PageBlockParser.serializeDocument(
        updatedDocument,
        includeBlockIDComments: persistBlockIDComments
    )
    let updatedRecord = workspacePageRecord(from: existing, content: nextContent)
    let selectedBlocksAfter = try mutation.afterPaths.map { path in
        try lookupBlock(in: updatedBlocks, selector: pathSelector(path))
    }

    return WorkspacePageBlockUpdatePreview(
        original: existing,
        updated: updatedRecord,
        changed: existing.content != nextContent,
        lineChanges: structuredLineChanges(from: existing.content, to: nextContent),
        selectedBlockBefore: beforeBlock,
        selectedBlocksAfter: selectedBlocksAfter
    )
}

func previewWorkspacePageBlockTextUpdate(
    query: String,
    workspace: String,
    blockSelector: String,
    textContent: String
) throws -> WorkspacePageBlockUpdatePreview {
    let existing = try resolveWorkspacePage(query, workspace: workspace)
    let (split, document) = parseWorkspacePageDocument(from: existing.content)
    let beforeBlock = try lookupBlock(in: document.blocks, selector: blockSelector)
    let persistBlockIDComments = documentHasPersistedBlockIDs(document.blocks)

    var updatedBlocks = document.blocks
    if persistBlockIDComments {
        _ = normalizeStableBlockIDs(in: &updatedBlocks)
    }

    guard let afterPath = try updateParsedPageBlockText(
        in: &updatedBlocks,
        selector: blockSelector,
        newText: textContent
    ) else {
        throw CLIError.invalidInput("Block not found: \(blockSelector)")
    }

    if persistBlockIDComments {
        _ = normalizeStableBlockIDs(in: &updatedBlocks)
    }

    let updatedDocument = ParsedPageDocument(metadata: document.metadata, blocks: updatedBlocks)
    let nextContent = split.prefix + PageBlockParser.serializeDocument(
        updatedDocument,
        includeBlockIDComments: persistBlockIDComments
    )
    let updatedRecord = workspacePageRecord(from: existing, content: nextContent)
    let selectedBlockAfter = try lookupBlock(in: updatedBlocks, selector: pathSelector(afterPath))

    return WorkspacePageBlockUpdatePreview(
        original: existing,
        updated: updatedRecord,
        changed: existing.content != nextContent,
        lineChanges: structuredLineChanges(from: existing.content, to: nextContent),
        selectedBlockBefore: beforeBlock,
        selectedBlocksAfter: [selectedBlockAfter]
    )
}

func previewWorkspacePageBlockMove(
    query: String,
    workspace: String,
    blockSelector: String,
    destinationSelector: String,
    placeBefore: Bool
) throws -> WorkspacePageBlockUpdatePreview {
    let existing = try resolveWorkspacePage(query, workspace: workspace)
    let (split, document) = parseWorkspacePageDocument(from: existing.content)
    let beforeBlock = try lookupBlock(in: document.blocks, selector: blockSelector)
    _ = try lookupBlock(in: document.blocks, selector: destinationSelector)
    let persistBlockIDComments = documentHasPersistedBlockIDs(document.blocks)

    var updatedBlocks = document.blocks
    if persistBlockIDComments {
        _ = normalizeStableBlockIDs(in: &updatedBlocks)
    }

    guard let afterPath = try moveParsedPageBlock(
        in: &updatedBlocks,
        sourceSelector: blockSelector,
        destinationSelector: destinationSelector,
        placeBefore: placeBefore
    ) else {
        throw CLIError.invalidInput("Block not found: \(blockSelector)")
    }

    if persistBlockIDComments {
        _ = normalizeStableBlockIDs(in: &updatedBlocks)
    }

    let updatedDocument = ParsedPageDocument(metadata: document.metadata, blocks: updatedBlocks)
    let nextContent = split.prefix + PageBlockParser.serializeDocument(
        updatedDocument,
        includeBlockIDComments: persistBlockIDComments
    )
    let updatedRecord = workspacePageRecord(from: existing, content: nextContent)
    let selectedBlockAfter = try lookupBlock(in: updatedBlocks, selector: pathSelector(afterPath))

    return WorkspacePageBlockUpdatePreview(
        original: existing,
        updated: updatedRecord,
        changed: existing.content != nextContent,
        lineChanges: structuredLineChanges(from: existing.content, to: nextContent),
        selectedBlockBefore: beforeBlock,
        selectedBlocksAfter: [selectedBlockAfter]
    )
}

func updateWorkspacePageBlock(
    query: String,
    workspace: String,
    blockSelector: String,
    replacementContent: String? = nil,
    prependContent: String? = nil,
    appendContent: String? = nil
) throws -> WorkspacePageRecord {
    let preview = try previewWorkspacePageBlockUpdate(
        query: query,
        workspace: workspace,
        blockSelector: blockSelector,
        replacementContent: replacementContent,
        prependContent: prependContent,
        appendContent: appendContent
    )

    try preview.updated.content.write(toFile: preview.original.path, atomically: true, encoding: .utf8)
    return try loadWorkspacePage(at: preview.original.path, relativeTo: workspace)
}

func updateWorkspacePageBlockText(
    query: String,
    workspace: String,
    blockSelector: String,
    textContent: String
) throws -> WorkspacePageRecord {
    let preview = try previewWorkspacePageBlockTextUpdate(
        query: query,
        workspace: workspace,
        blockSelector: blockSelector,
        textContent: textContent
    )

    try preview.updated.content.write(toFile: preview.original.path, atomically: true, encoding: .utf8)
    return try loadWorkspacePage(at: preview.original.path, relativeTo: workspace)
}

func updateWorkspacePageBlockMove(
    query: String,
    workspace: String,
    blockSelector: String,
    destinationSelector: String,
    placeBefore: Bool
) throws -> WorkspacePageRecord {
    let preview = try previewWorkspacePageBlockMove(
        query: query,
        workspace: workspace,
        blockSelector: blockSelector,
        destinationSelector: destinationSelector,
        placeBefore: placeBefore
    )

    try preview.updated.content.write(toFile: preview.original.path, atomically: true, encoding: .utf8)
    return try loadWorkspacePage(at: preview.original.path, relativeTo: workspace)
}

private func parseWorkspacePageDocument(from content: String) -> (split: PageFrontmatterSplit, document: ParsedPageDocument) {
    let split = splitPageFrontmatter(from: content)
    return (split, PageBlockParser.parseDocument(split.body))
}

private func parsedPageBlockCount(_ blocks: [ParsedPageBlock]) -> Int {
    blocks.reduce(0) { partialResult, block in
        partialResult + 1 + parsedPageBlockCount(block.children)
    }
}

private func parsedPageBlocksContainPageLinks(_ blocks: [ParsedPageBlock]) -> Bool {
    for block in blocks {
        if block.type == .pageLink || parsedPageBlocksContainPageLinks(block.children) {
            return true
        }
    }
    return false
}

private func documentHasPersistedBlockIDs(_ blocks: [ParsedPageBlock]) -> Bool {
    for block in blocks {
        if block.stableID {
            return true
        }
        if documentHasPersistedBlockIDs(block.children) {
            return true
        }
    }
    return false
}

private func splitPageFrontmatter(from content: String) -> PageFrontmatterSplit {
    guard content.hasPrefix("---") else {
        return PageFrontmatterSplit(prefix: "", body: content)
    }

    let lines = content.components(separatedBy: .newlines)
    guard lines.first == "---" else {
        return PageFrontmatterSplit(prefix: "", body: content)
    }

    for index in 1..<lines.count where lines[index] == "---" {
        let prefix = Array(lines[0...index]).joined(separator: "\n") + "\n"
        let body = lines.dropFirst(index + 1).joined(separator: "\n")
        return PageFrontmatterSplit(prefix: prefix, body: body)
    }

    return PageFrontmatterSplit(prefix: "", body: content)
}

private func collectBlockIDs(in blocks: [ParsedPageBlock]) -> Set<String> {
    var ids = Set<String>()
    for block in blocks {
        ids.insert(block.id)
        ids.formUnion(collectBlockIDs(in: block.children))
    }
    return ids
}

private func resolveCommonMarkPageLinks(
    in blocks: [ParsedPageBlock],
    using resolver: CommonMarkPageLinkResolver,
    pathPrefix: [Int] = []
) -> (blocks: [ParsedPageBlock], warnings: [WorkspacePageFormatWarning]) {
    var resolvedBlocks: [ParsedPageBlock] = []
    var warnings: [WorkspacePageFormatWarning] = []

    for (offset, block) in blocks.enumerated() {
        let path = pathPrefix + [offset]
        var resolved = block
        if block.type == .pageLink {
            switch resolver.resolve(block.pageLinkName) {
            case .resolved(let destination):
                resolved.commonmarkLinkDestination = destination
            case .downgraded(let reason, let matches):
                warnings.append(
                    WorkspacePageFormatWarning(
                        kind: "downgraded_page_link",
                        blockID: blockSelectorID(for: block, path: path),
                        pageName: block.pageLinkName,
                        reason: reason,
                        matches: matches,
                        message: formatWarningMessage(reason: reason, pageName: block.pageLinkName)
                    )
                )
            }
        }
        if !block.children.isEmpty {
            let children = resolveCommonMarkPageLinks(
                in: block.children,
                using: resolver,
                pathPrefix: path
            )
            resolved.children = children.blocks
            warnings.append(contentsOf: children.warnings)
        }
        resolvedBlocks.append(resolved)
    }
    return (resolvedBlocks, warnings)
}

private func formatWarningMessage(reason: String, pageName: String) -> String {
    switch reason {
    case "ambiguous_page_reference":
        return "Page link `\(pageName)` matched multiple workspace pages and was downgraded to plain text."
    default:
        return "Page link `\(pageName)` did not match any workspace page and was downgraded to plain text."
    }
}

private func findParsedPageBlocks(
    in blocks: [ParsedPageBlock],
    selector: String,
    pathPrefix: [Int] = []
) -> [ParsedPageBlockLookup] {
    let selectorPath = parsePathSelector(selector)
    var matches: [ParsedPageBlockLookup] = []

    for (offset, block) in blocks.enumerated() {
        let path = pathPrefix + [offset]
        if let selectorPath {
            if selectorPath == path {
                matches.append(ParsedPageBlockLookup(block: block, path: path))
            }
        } else if block.stableID && block.id == selector {
            matches.append(ParsedPageBlockLookup(block: block, path: path))
        }

        let childMatches = findParsedPageBlocks(in: block.children, selector: selector, pathPrefix: path)
        if !childMatches.isEmpty {
            matches.append(contentsOf: childMatches)
        }
    }

    return matches
}

private func lookupParsedPageBlock(
    in blocks: [ParsedPageBlock],
    selector: String
) throws -> ParsedPageBlockLookup? {
    let matches = findParsedPageBlocks(in: blocks, selector: selector)
    guard let match = matches.first else {
        return nil
    }
    if parsePathSelector(selector) == nil, matches.count > 1 {
        throw CLIError.invalidInput(
            "Block selector is ambiguous because multiple blocks share persisted ID \(selector). Run `page ensure-block-ids` or use a path: selector."
        )
    }
    return match
}

private func parsePathSelector(_ selector: String) -> [Int]? {
    guard selector.hasPrefix("path:") else { return nil }
    let raw = String(selector.dropFirst("path:".count))
    guard !raw.isEmpty else { return nil }
    let components = raw.split(separator: "/")
    guard !components.isEmpty else { return nil }

    var path: [Int] = []
    for component in components {
        guard let value = Int(component) else { return nil }
        path.append(value)
    }
    return path
}

private func isStrictPathPrefix(_ prefix: [Int], of path: [Int]) -> Bool {
    guard prefix.count < path.count else {
        return false
    }
    return Array(path.prefix(prefix.count)) == prefix
}

private func adjustedPathAfterRemoving(_ path: [Int], removedPath: [Int]) -> [Int]? {
    if path == removedPath || isStrictPathPrefix(removedPath, of: path) {
        return nil
    }

    var adjusted = path
    let sharedDepth = zip(path, removedPath).prefix { $0 == $1 }.count
    if sharedDepth < path.count,
       sharedDepth < removedPath.count,
       path[sharedDepth] > removedPath[sharedDepth] {
        adjusted[sharedDepth] -= 1
    }
    return adjusted
}

private func parsedPageBlock(
    at path: [Int],
    in blocks: [ParsedPageBlock]
) -> ParsedPageBlock? {
    guard let index = path.first, blocks.indices.contains(index) else {
        return nil
    }

    let block = blocks[index]
    if path.count == 1 {
        return block
    }

    return parsedPageBlock(at: Array(path.dropFirst()), in: block.children)
}

private func parentType(
    for path: [Int],
    in blocks: [ParsedPageBlock]
) -> ParsedPageBlockType? {
    guard !path.isEmpty else {
        return nil
    }
    return parsedPageBlock(at: path, in: blocks)?.type
}

private func removeParsedPageBlock(
    at path: [Int],
    from blocks: inout [ParsedPageBlock]
) -> ParsedPageBlock? {
    guard let index = path.first else {
        return nil
    }

    if path.count == 1 {
        guard blocks.indices.contains(index) else {
            return nil
        }
        return blocks.remove(at: index)
    }

    guard blocks.indices.contains(index) else {
        return nil
    }
    return removeParsedPageBlock(at: Array(path.dropFirst()), from: &blocks[index].children)
}

private func insertParsedPageBlock(
    _ block: ParsedPageBlock,
    at path: [Int],
    in blocks: inout [ParsedPageBlock]
) -> Bool {
    guard let index = path.first else {
        return false
    }

    if path.count == 1 {
        guard index >= 0, index <= blocks.count else {
            return false
        }
        blocks.insert(block, at: index)
        return true
    }

    guard blocks.indices.contains(index) else {
        return false
    }
    return insertParsedPageBlock(block, at: Array(path.dropFirst()), in: &blocks[index].children)
}

private func moveParsedPageBlock(
    in blocks: inout [ParsedPageBlock],
    sourceSelector: String,
    destinationSelector: String,
    placeBefore: Bool
) throws -> [Int]? {
    guard let source = try lookupParsedPageBlock(in: blocks, selector: sourceSelector) else {
        return nil
    }
    guard let destination = try lookupParsedPageBlock(in: blocks, selector: destinationSelector) else {
        throw CLIError.invalidInput("Block not found: \(destinationSelector)")
    }

    if source.path == destination.path {
        throw CLIError.invalidInput("Source and destination blocks must be different")
    }
    if isStrictPathPrefix(source.path, of: destination.path) {
        throw CLIError.invalidInput("Cannot move a block relative to one of its descendants")
    }

    guard var movedBlock = removeParsedPageBlock(at: source.path, from: &blocks) else {
        return nil
    }
    guard let adjustedDestinationPath = adjustedPathAfterRemoving(destination.path, removedPath: source.path),
          let adjustedDestination = parsedPageBlock(at: adjustedDestinationPath, in: blocks) else {
        return nil
    }

    let destinationParentPath = Array(adjustedDestinationPath.dropLast())
    let destinationParentType = parentType(for: destinationParentPath, in: blocks)
    movedBlock.columnIndex = destinationParentType == .column ? adjustedDestination.columnIndex : 0

    let insertionIndex = adjustedDestinationPath.last! + (placeBefore ? 0 : 1)
    let insertionPath = destinationParentPath + [insertionIndex]
    guard insertParsedPageBlock(movedBlock, at: insertionPath, in: &blocks) else {
        return nil
    }

    return insertionPath
}

private func applyBlockMutation(
    in blocks: inout [ParsedPageBlock],
    selector: String,
    replacementBlocks: [ParsedPageBlock]?,
    prependBlocks: [ParsedPageBlock],
    appendBlocks: [ParsedPageBlock],
    usedIDs: inout Set<String>,
    pathPrefix: [Int] = [],
    parentType: ParsedPageBlockType? = nil
) -> ParsedPageBlockMutationResult? {
    for index in blocks.indices {
        let path = pathPrefix + [index]
        let target = blocks[index]
        let matches: Bool
        if let selectorPath = parsePathSelector(selector) {
            matches = selectorPath == path
        } else {
            matches = target.stableID && target.id == selector
        }

        if matches {
            let before = ParsedPageBlockLookup(block: target, path: path)

            var prefix = prependBlocks
            var suffix = appendBlocks
            if parentType == .column {
                applyColumnIndex(to: &prefix, columnIndex: target.columnIndex)
                applyColumnIndex(to: &suffix, columnIndex: target.columnIndex)
            }
            ensureUniqueBlockIDs(in: &prefix, usedIDs: &usedIDs)
            ensureUniqueBlockIDs(in: &suffix, usedIDs: &usedIDs)

            if let replacementBlocks {
                for removedID in collectBlockIDs(in: [target]) {
                    usedIDs.remove(removedID)
                }

                var replacement = replacementBlocks
                if parentType == .column {
                    applyColumnIndex(to: &replacement, columnIndex: target.columnIndex)
                }
                ensureUniqueBlockIDs(in: &replacement, usedIDs: &usedIDs)

                let replacementStartIndex = index + prefix.count
                let afterPaths = replacement.indices.map { replacementOffset in
                    pathPrefix + [replacementStartIndex + replacementOffset]
                }
                blocks.replaceSubrange(index...index, with: prefix + replacement + suffix)
                return ParsedPageBlockMutationResult(before: before, afterPaths: afterPaths)
            }

            blocks.replaceSubrange(index...index, with: prefix + [target] + suffix)
            return ParsedPageBlockMutationResult(
                before: before,
                afterPaths: [pathPrefix + [index + prefix.count]]
            )
        }

        if !blocks[index].children.isEmpty,
           let result = applyBlockMutation(
            in: &blocks[index].children,
            selector: selector,
            replacementBlocks: replacementBlocks,
            prependBlocks: prependBlocks,
            appendBlocks: appendBlocks,
            usedIDs: &usedIDs,
            pathPrefix: path,
            parentType: blocks[index].type
           ) {
            return result
        }
    }

    return nil
}

private func updateParsedPageBlockText(
    in blocks: inout [ParsedPageBlock],
    selector: String,
    newText: String,
    pathPrefix: [Int] = []
) throws -> [Int]? {
    for index in blocks.indices {
        let path = pathPrefix + [index]
        let matches: Bool
        if let selectorPath = parsePathSelector(selector) {
            matches = selectorPath == path
        } else {
            matches = blocks[index].stableID && blocks[index].id == selector
        }

        if matches {
            guard parsedPageBlockSupportsTextMutation(blocks[index]) else {
                throw CLIError.invalidInput("Block type does not support text-only updates: \(blocks[index].type.rawValue)")
            }
            blocks[index].text = newText
            return path
        }

        if !blocks[index].children.isEmpty,
           let updatedPath = try updateParsedPageBlockText(
            in: &blocks[index].children,
            selector: selector,
            newText: newText,
            pathPrefix: path
           ) {
            return updatedPath
        }
    }

    return nil
}

private func parsedPageBlockSupportsTextMutation(_ block: ParsedPageBlock) -> Bool {
    switch block.type {
    case .paragraph, .heading, .bulletListItem, .numberedListItem, .taskItem, .codeBlock, .blockquote, .toggle:
        return true
    case .horizontalRule, .image, .databaseEmbed, .pageLink, .column:
        return false
    }
}

private func applyColumnIndex(to blocks: inout [ParsedPageBlock], columnIndex: Int) {
    for index in blocks.indices {
        blocks[index].columnIndex = columnIndex
    }
}

private func ensureUniqueBlockIDs(in blocks: inout [ParsedPageBlock], usedIDs: inout Set<String>) {
    for index in blocks.indices {
        if usedIDs.contains(blocks[index].id) {
            blocks[index].id = newBlockID()
            blocks[index].stableID = false
        }
        usedIDs.insert(blocks[index].id)
        if !blocks[index].children.isEmpty {
            ensureUniqueBlockIDs(in: &blocks[index].children, usedIDs: &usedIDs)
        }
    }
}

private func normalizeStableBlockIDs(in blocks: inout [ParsedPageBlock]) -> Bool {
    var changed = false
    var usedIDs = Set<String>()
    normalizeStableBlockIDs(in: &blocks, usedIDs: &usedIDs, changed: &changed)
    return changed
}

private func compactEmptyParagraphBlocks(in blocks: inout [ParsedPageBlock]) -> Int {
    var removedCount = 0
    var compacted: [ParsedPageBlock] = []
    compacted.reserveCapacity(blocks.count)

    for var block in blocks {
        if !block.children.isEmpty {
            removedCount += compactEmptyParagraphBlocks(in: &block.children)
        }
        if block.type == .paragraph,
           block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            removedCount += 1
            continue
        }
        compacted.append(block)
    }

    blocks = compacted
    return removedCount
}

private func normalizeStableBlockIDs(
    in blocks: inout [ParsedPageBlock],
    usedIDs: inout Set<String>,
    changed: inout Bool
) {
    for index in blocks.indices {
        if !blocks[index].stableID || blocks[index].id.isEmpty || usedIDs.contains(blocks[index].id) {
            blocks[index].id = newBlockID()
            blocks[index].stableID = true
            changed = true
        } else {
            blocks[index].stableID = true
        }

        usedIDs.insert(blocks[index].id)
        if !blocks[index].children.isEmpty {
            normalizeStableBlockIDs(in: &blocks[index].children, usedIDs: &usedIDs, changed: &changed)
        }
    }
}

private func parseInsertedBlocks(_ markdown: String) -> [ParsedPageBlock] {
    if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return []
    }
    return PageBlockParser.parseBlocks(markdown)
}

private func parseReplacementBlocks(_ markdown: String) -> [ParsedPageBlock] {
    if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return []
    }
    return PageBlockParser.parseBlocks(markdown)
}

private func workspacePageBlockRecord(from lookup: ParsedPageBlockLookup) -> WorkspacePageBlockRecord {
    let selectorID = blockSelectorID(for: lookup.block, path: lookup.path)
    let json = parsedPageBlockJSON(lookup.block, path: lookup.path)
    let content = PageBlockParser.serializeBlocks([lookup.block], includeBlockIDComments: false)
    return WorkspacePageBlockRecord(
        id: selectorID,
        stableID: lookup.block.stableID,
        persistedID: lookup.block.stableID ? lookup.block.id : nil,
        path: lookup.path,
        type: lookup.block.type.rawValue,
        content: content,
        json: json
    )
}

private func pathSelector(_ path: [Int]) -> String {
    "path:\(path.map(String.init).joined(separator: "/"))"
}

private func blockSelectorID(for block: ParsedPageBlock, path: [Int]) -> String {
    if block.stableID {
        return block.id
    }
    return "path:\(path.map(String.init).joined(separator: "/"))"
}

private func parsedPageBlocksJSON(
    _ blocks: [ParsedPageBlock],
    pathPrefix: [Int] = [],
    includeColumnIndex: Bool = false
) -> [[String: Any]] {
    blocks.enumerated().map { offset, block in
        parsedPageBlockJSON(
            block,
            path: pathPrefix + [offset],
            includeColumnIndex: includeColumnIndex
        )
    }
}

private func parsedPageBlockJSON(
    _ block: ParsedPageBlock,
    path: [Int],
    includeColumnIndex: Bool = false
) -> [String: Any] {
    var json: [String: Any] = [
        "id": blockSelectorID(for: block, path: path),
        "stable_id": block.stableID,
        "path": path,
        "type": block.type.rawValue,
    ]

    if block.stableID {
        json["persisted_id"] = block.id
    }
    if !block.text.isEmpty || block.type == .paragraph || block.type == .heading || block.type == .blockquote || block.type == .toggle {
        json["text"] = block.text
    }
    if block.headingLevel != 1 || block.type == .heading {
        json["heading_level"] = block.headingLevel
    }
    if block.listDepth > 0 || block.type == .bulletListItem || block.type == .numberedListItem || block.type == .taskItem {
        json["list_depth"] = block.listDepth
    }
    if block.type == .taskItem {
        json["checked"] = block.isChecked
    }
    if !block.language.isEmpty {
        json["language"] = block.language
    }
    if !block.imageSource.isEmpty {
        json["image_source"] = block.imageSource
    }
    if !block.imageAlt.isEmpty {
        json["image_alt"] = block.imageAlt
    }
    if let imageWidth = block.imageWidth {
        json["image_width"] = imageWidth
    }
    if !block.databasePath.isEmpty {
        json["database_path"] = block.databasePath
    }
    if !block.pageLinkName.isEmpty {
        json["page_name"] = block.pageLinkName
    }
    if let textColor = block.textColor {
        json["text_color"] = textColor
    }
    if let backgroundColor = block.backgroundColor {
        json["background_color"] = backgroundColor
    }
    if includeColumnIndex {
        json["column_index"] = block.columnIndex
    }
    if block.type == .toggle {
        json["expanded"] = block.isExpanded
    }
    if !block.children.isEmpty {
        json["children"] = block.children.enumerated().map { offset, child in
            parsedPageBlockJSON(
                child,
                path: path + [offset],
                includeColumnIndex: block.type == .column
            )
        }
    }

    return json
}

private func newBlockID() -> String {
    UUID().uuidString.lowercased()
}
