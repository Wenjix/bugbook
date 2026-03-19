import Foundation

enum MarkdownBlockParser {

    // MARK: - Metadata

    struct Metadata {
        var icon: String?
        var coverUrl: String?
        var coverPosition: Double = 50
        var fullWidth: Bool = false
    }

    /// Parse file-level metadata comments from the top of the markdown string.
    /// Returns the metadata and the remaining markdown content after metadata lines.
    static func parseMetadata(_ markdown: String) -> (Metadata, String) {
        var metadata = Metadata()
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var contentStartIndex = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // icon metadata
            if trimmed.hasPrefix("<!-- icon:") && trimmed.hasSuffix("-->") {
                let inner = trimmed.dropFirst(10).dropLast(3).trimmingCharacters(in: .whitespaces)
                if !inner.isEmpty {
                    metadata.icon = inner
                }
                contentStartIndex += 1
                continue
            }

            // cover metadata
            if trimmed.hasPrefix("<!-- cover:") && trimmed.hasSuffix("-->") {
                let inner = trimmed.dropFirst(11).dropLast(3).trimmingCharacters(in: .whitespaces)
                if let atRange = inner.range(of: "@", options: .backwards) {
                    let path = String(inner[..<atRange.lowerBound])
                    let posStr = String(inner[atRange.upperBound...])
                    metadata.coverUrl = path
                    metadata.coverPosition = Double(posStr) ?? 50
                } else {
                    metadata.coverUrl = inner.isEmpty ? nil : inner
                }
                contentStartIndex += 1
                continue
            }

            // full-width metadata
            if trimmed == "<!-- full-width -->" {
                metadata.fullWidth = true
                contentStartIndex += 1
                continue
            }

            // Stop at first non-metadata line
            break
        }

        let remainingLines = Array(lines.dropFirst(contentStartIndex))
        let remaining = remainingLines.joined(separator: "\n")
        return (metadata, remaining)
    }

    /// Serialize metadata to comment lines prepended to content.
    static func serializeMetadata(_ metadata: Metadata) -> String {
        var lines: [String] = []
        if let icon = metadata.icon, !icon.isEmpty {
            lines.append("<!-- icon:\(icon) -->")
        }
        if let cover = metadata.coverUrl, !cover.isEmpty {
            let pos = Int(metadata.coverPosition)
            lines.append("<!-- cover:\(cover)@\(pos) -->")
        }
        if metadata.fullWidth {
            lines.append("<!-- full-width -->")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Parse

    static func parse(_ markdown: String) -> [Block] {
        guard !markdown.isEmpty else {
            return [Block(type: .paragraph)]
        }

        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count > 1, lines.last == "" {
            lines.removeLast()
        }
        var blocks: [Block] = []
        var i = 0
        var pendingBlockID: UUID?
        var pendingColors: (BlockColor, BlockColor)?

        func makeBlock(
            type: BlockType = .paragraph,
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
            children: [Block] = [],
            columnIndex: Int = 0,
            isExpanded: Bool = true
        ) -> Block {
            let colors = pendingColors ?? (.default, .default)
            let block = Block(
                id: pendingBlockID ?? UUID(),
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
                textColor: colors.0,
                backgroundColor: colors.1,
                children: children,
                columnIndex: columnIndex,
                isExpanded: isExpanded
            )
            pendingBlockID = nil
            pendingColors = nil
            return block
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let blockID = parseBlockIDComment(line) {
                pendingBlockID = blockID
                i += 1
                continue
            }

            if let colors = parseColorComment(line) {
                pendingColors = colors
                i += 1
                continue
            }

            // Code fence
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
                blocks.append(makeBlock(type: .codeBlock, text: codeLines.joined(separator: "\n"), language: language))
                continue
            }

            // Horizontal rule
            if isHorizontalRule(line) {
                blocks.append(makeBlock(type: .horizontalRule, text: line))
                i += 1
                continue
            }

            // Heading
            if let (level, text) = parseHeading(line) {
                blocks.append(makeBlock(type: .heading, text: text, headingLevel: level))
                i += 1
                continue
            }

            // Task item (must come before bullet)
            if let (depth, checked, text) = parseTaskItem(line) {
                blocks.append(makeBlock(type: .taskItem, text: text, listDepth: depth, isChecked: checked))
                i += 1
                continue
            }

            // Bullet list item
            if let (depth, text) = parseBulletItem(line) {
                blocks.append(makeBlock(type: .bulletListItem, text: text, listDepth: depth))
                i += 1
                continue
            }

            // Numbered list item
            if let (depth, text) = parseNumberedItem(line) {
                blocks.append(makeBlock(type: .numberedListItem, text: text, listDepth: depth))
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
                blocks.append(makeBlock(type: .blockquote, text: text))
                i += 1
                continue
            }

            // Image
            if let (alt, src, width) = parseImage(line) {
                blocks.append(makeBlock(type: .image, imageSource: src, imageAlt: alt, imageWidth: width))
                i += 1
                continue
            }

            // Database embed
            if let path = parseDatabaseEmbed(line) {
                blocks.append(makeBlock(type: .databaseEmbed, databasePath: path))
                i += 1
                continue
            }

            // Wiki link (page link) — line is exactly [[Page Name]]
            if let name = parseWikiLink(line) {
                if let dbPath = parseDatabaseSchemePath(name) {
                    blocks.append(makeBlock(type: .databaseEmbed, databasePath: dbPath))
                } else {
                    blocks.append(makeBlock(type: .pageLink, pageLinkName: name))
                }
                i += 1
                continue
            }

            // Page link comment — <!-- bugbook-page-link: Name -->
            if let name = parsePageLinkComment(line) {
                blocks.append(makeBlock(type: .pageLink, pageLinkName: name))
                i += 1
                continue
            }

            // Toggle block
            if trimmed == "<!-- toggle -->" || trimmed == "<!-- toggle collapsed -->" {
                let collapsed = trimmed.contains("collapsed")
                i += 1
                // First line is the toggle title
                let title = i < lines.count ? lines[i] : ""
                i += 1
                // Remaining lines until <!-- /toggle --> are children
                var childLines: [String] = []
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces) == "<!-- /toggle -->" {
                        i += 1
                        break
                    }
                    childLines.append(lines[i])
                    i += 1
                }
                let children = childLines.isEmpty ? [] : parse(childLines.joined(separator: "\n"))
                blocks.append(makeBlock(type: .toggle, text: title, children: children, isExpanded: !collapsed))
                continue
            }

            // Heading toggle block
            if let headingToggleLevel = parseHeadingToggleComment(trimmed) {
                let collapsed = trimmed.contains("collapsed")
                i += 1
                let title = i < lines.count ? lines[i] : ""
                i += 1
                var childLines: [String] = []
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces) == "<!-- /toggle-heading -->" {
                        i += 1
                        break
                    }
                    childLines.append(lines[i])
                    i += 1
                }
                let children = childLines.isEmpty ? [] : parse(childLines.joined(separator: "\n"))
                blocks.append(makeBlock(type: .headingToggle, text: title, headingLevel: headingToggleLevel, children: children, isExpanded: !collapsed))
                continue
            }

            // Canvas block
            if trimmed == "<!-- canvas -->" {
                i += 1
                var jsonLines: [String] = []
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces) == "<!-- /canvas -->" {
                        i += 1
                        break
                    }
                    jsonLines.append(lines[i])
                    i += 1
                }
                let json = jsonLines.joined(separator: "\n")
                blocks.append(makeBlock(type: .canvas, text: json))
                continue
            }

            // Column block
            if trimmed == "<!-- columns -->" {
                var allChildren: [Block] = []
                var currentColumnIndex = 0
                var currentColumnLines: [String] = []
                i += 1
                while i < lines.count {
                    let colLine = lines[i]
                    if colLine.trimmingCharacters(in: .whitespaces) == "<!-- /columns -->" {
                        i += 1
                        break
                    }
                    if colLine.trimmingCharacters(in: .whitespaces) == "<!-- column-separator -->" {
                        // Parse accumulated lines for current column
                        if !currentColumnLines.isEmpty {
                            let columnContent = currentColumnLines.joined(separator: "\n")
                            var columnBlocks = parse(columnContent)
                            for j in columnBlocks.indices {
                                columnBlocks[j].columnIndex = currentColumnIndex
                            }
                            allChildren.append(contentsOf: columnBlocks)
                        }
                        currentColumnLines = []
                        currentColumnIndex += 1
                        i += 1
                        continue
                    }
                    currentColumnLines.append(colLine)
                    i += 1
                }
                // Parse remaining lines for last column
                if !currentColumnLines.isEmpty {
                    let columnContent = currentColumnLines.joined(separator: "\n")
                    var columnBlocks = parse(columnContent)
                    for j in columnBlocks.indices {
                        columnBlocks[j].columnIndex = currentColumnIndex
                    }
                    allChildren.append(contentsOf: columnBlocks)
                }
                blocks.append(makeBlock(type: .column, children: allChildren))
                continue
            }

            // Meeting block
            if trimmed == "<!-- meeting -->" {
                i += 1
                var title = ""
                var transcript = ""
                var summary = ""
                var actionItems = ""
                var section = ""
                while i < lines.count {
                    let mLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if mLine == "<!-- /meeting -->" {
                        i += 1
                        break
                    }
                    if mLine.hasPrefix("<!-- meeting-title:") && mLine.hasSuffix("-->") {
                        title = String(mLine.dropFirst(19).dropLast(3)).trimmingCharacters(in: .whitespaces)
                    } else if mLine == "<!-- meeting-summary -->" {
                        section = "summary"
                    } else if mLine == "<!-- meeting-actions -->" {
                        section = "actions"
                    } else if mLine == "<!-- meeting-transcript -->" {
                        section = "transcript"
                    } else {
                        switch section {
                        case "summary":
                            summary += (summary.isEmpty ? "" : "\n") + lines[i]
                        case "actions":
                            actionItems += (actionItems.isEmpty ? "" : "\n") + lines[i]
                        case "transcript":
                            transcript += (transcript.isEmpty ? "" : "\n") + lines[i]
                        default:
                            break
                        }
                    }
                    i += 1
                }
                var meetingBlock = makeBlock(type: .meeting)
                meetingBlock.meetingTitle = title
                meetingBlock.meetingTranscript = transcript
                meetingBlock.meetingSummary = summary
                meetingBlock.meetingActionItems = actionItems
                meetingBlock.meetingState = .complete
                blocks.append(meetingBlock)
                continue
            }

            // Paragraph (including empty lines)
            blocks.append(makeBlock(type: .paragraph, text: unescapeParagraphText(line)))
            i += 1
        }

        if blocks.isEmpty {
            blocks.append(Block(type: .paragraph))
        }

        return blocks
    }

    // MARK: - Serialize

    static func serialize(_ blocks: [Block], includeBlockIDComments: Bool = false) -> String {
        var lines: [String] = []

        for (i, block) in blocks.enumerated() {
            if includeBlockIDComments {
                lines.append("<!-- block-id: \(block.id.uuidString.lowercased()) -->")
            }

            // Emit color comment before blocks that have non-default colors
            let hasColor = block.textColor != .default || block.backgroundColor != .default
            if hasColor, block.type != .column, block.type != .toggle, block.type != .headingToggle, block.type != .canvas {
                var parts: [String] = []
                if block.textColor != .default {
                    parts.append("color:\(block.textColor.rawValue)")
                }
                if block.backgroundColor != .default {
                    parts.append("bg:\(block.backgroundColor.rawValue)")
                }
                lines.append("<!-- \(parts.joined(separator: " ")) -->")
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
                let num = computeNumberedPosition(at: i, depth: block.listDepth, in: blocks)
                lines.append("\(indent)\(num). \(block.text)")

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
                if let width = block.imageWidth {
                    line += "{width=\(width)}"
                }
                lines.append(line)

            case .databaseEmbed:
                lines.append("<!-- database: \(block.databasePath) -->")

            case .pageLink:
                lines.append("[[\(block.pageLinkName)]]")

            case .toggle:
                lines.append(block.isExpanded ? "<!-- toggle -->" : "<!-- toggle collapsed -->")
                lines.append(block.text)
                if !block.children.isEmpty {
                    lines.append(serialize(block.children, includeBlockIDComments: includeBlockIDComments))
                }
                lines.append("<!-- /toggle -->")

            case .headingToggle:
                let level = max(1, min(3, block.headingLevel))
                let collapsed = block.isExpanded ? "" : " collapsed"
                lines.append("<!-- toggle-heading \(level)\(collapsed) -->")
                lines.append(block.text)
                if !block.children.isEmpty {
                    lines.append(serialize(block.children, includeBlockIDComments: includeBlockIDComments))
                }
                lines.append("<!-- /toggle-heading -->")

            case .canvas:
                lines.append("<!-- canvas -->")
                if !block.text.isEmpty {
                    lines.append(block.text)
                }
                lines.append("<!-- /canvas -->")

            case .column:
                lines.append("<!-- columns -->")
                let maxCol = block.children.map(\.columnIndex).max() ?? 0
                for colIdx in 0...maxCol {
                    if colIdx > 0 {
                        lines.append("<!-- column-separator -->")
                    }
                    let colBlocks = block.children.filter { $0.columnIndex == colIdx }
                    if !colBlocks.isEmpty {
                        lines.append(serialize(colBlocks, includeBlockIDComments: includeBlockIDComments))
                    }
                }
                lines.append("<!-- /columns -->")

            case .meeting:
                // Only serialize completed meetings; recording/processing blocks are transient
                guard block.meetingState == .complete else { break }
                lines.append("<!-- meeting -->")
                if !block.meetingTitle.isEmpty {
                    lines.append("<!-- meeting-title: \(block.meetingTitle) -->")
                }
                if !block.meetingSummary.isEmpty {
                    lines.append("<!-- meeting-summary -->")
                    lines.append(block.meetingSummary)
                }
                if !block.meetingActionItems.isEmpty {
                    lines.append("<!-- meeting-actions -->")
                    lines.append(block.meetingActionItems)
                }
                if !block.meetingTranscript.isEmpty {
                    lines.append("<!-- meeting-transcript -->")
                    lines.append(block.meetingTranscript)
                }
                lines.append("<!-- /meeting -->")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Line Parsers

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
        if trimmed == "<!-- toggle -->"
            || trimmed == "<!-- toggle collapsed -->"
            || trimmed == "<!-- /toggle -->"
            || trimmed == "<!-- /toggle-heading -->"
            || trimmed == "<!-- columns -->"
            || trimmed == "<!-- column-separator -->"
            || trimmed == "<!-- /columns -->"
            || trimmed == "<!-- canvas -->"
            || trimmed == "<!-- /canvas -->" {
            return true
        }
        if parseHeadingToggleComment(trimmed) != nil { return true }
        return false
    }

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
        let text = String(line[line.index(after: idx)...])
        return (level, text)
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
        let text = String(afterCheck.dropFirst(2))
        return (depth, checkChar != " ", text)
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

    private static func parseImage(_ line: String) -> (String, String, Int?)? {
        guard line.hasPrefix("![") else { return nil }
        guard let altEndRange = line.range(of: "](") else { return nil }
        let altStart = line.index(line.startIndex, offsetBy: 2)
        let alt = String(line[altStart..<altEndRange.lowerBound])
        let srcStart = altEndRange.upperBound
        guard let parenEnd = line[srcStart...].firstIndex(of: ")") else { return nil }
        let src = String(line[srcStart..<parenEnd])

        var width: Int? = nil
        let afterParen = line.index(after: parenEnd)
        if afterParen < line.endIndex {
            let rest = String(line[afterParen...])
            if rest.hasPrefix("{width="), rest.hasSuffix("}") {
                let numStr = rest.dropFirst(7).dropLast(1)
                width = Int(numStr)
            }
        }
        return (alt, src, width)
    }

    private static func parseDatabaseEmbed(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->"),
           let colonRange = trimmed.range(of: "database:") {
            let pathStart = colonRange.upperBound
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

        var target = String(trimmed.dropFirst("database:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

        guard target.hasPrefix("/") else { return nil }
        return target
    }

    private static func parseWikiLink(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") else { return nil }
        let name = String(trimmed.dropFirst(2).dropLast(2))
        return name.isEmpty ? nil : name
    }

    private static func parseHeadingToggleComment(_ trimmed: String) -> Int? {
        guard trimmed.hasPrefix("<!-- toggle-heading"), trimmed.hasSuffix("-->") else { return nil }
        let inner = trimmed.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespaces)
        // inner is like "toggle-heading 2" or "toggle-heading 2 collapsed"
        guard inner.hasPrefix("toggle-heading") else { return nil }
        let rest = inner.dropFirst("toggle-heading".count).trimmingCharacters(in: .whitespaces)
        // rest is like "2" or "2 collapsed"
        let parts = rest.split(separator: " ", maxSplits: 1)
        guard let levelStr = parts.first, let level = Int(levelStr), level >= 1, level <= 3 else { return nil }
        return level
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

    private static func parseBlockIDComment(_ line: String) -> UUID? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") else { return nil }
        let inner = trimmed.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespaces)
        guard inner.lowercased().hasPrefix("block-id:") else { return nil }
        let raw = String(inner.dropFirst("block-id:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: raw)
    }

    private static func parseColorComment(_ line: String) -> (BlockColor, BlockColor)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") else { return nil }
        let inner = trimmed.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespaces)
        // Must contain color: or bg: but not "database:" or "columns"
        guard inner.contains("color:") || inner.contains("bg:") else { return nil }
        guard !inner.contains("database:") else { return nil }

        var textColor: BlockColor = .default
        var bgColor: BlockColor = .default
        let parts = inner.split(separator: " ")
        for part in parts {
            if part.hasPrefix("color:") {
                let value = String(part.dropFirst(6))
                textColor = BlockColor(rawValue: value) ?? .default
            } else if part.hasPrefix("bg:") {
                let value = String(part.dropFirst(3))
                bgColor = BlockColor(rawValue: value) ?? .default
            }
        }
        // Only return if at least one non-default color was found
        guard textColor != .default || bgColor != .default else { return nil }
        return (textColor, bgColor)
    }

    // MARK: - Tag Extraction

    /// Extract inline #tags from text. Returns unique tag strings without the # prefix.
    static func extractTags(from text: String) -> [String] {
        let pattern = #"(?:^|\s)#([\w/]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var tags: [String] = []
        var seen = Set<String>()
        for match in matches {
            if let tagRange = Range(match.range(at: 1), in: text) {
                let tag = String(text[tagRange])
                if seen.insert(tag).inserted {
                    tags.append(tag)
                }
            }
        }
        return tags
    }

    // MARK: - Helpers

    private static func computeNumberedPosition(at index: Int, depth: Int, in blocks: [Block]) -> Int {
        var count = 1
        var i = index - 1
        while i >= 0 {
            let prev = blocks[i]
            if prev.type == .numberedListItem, prev.listDepth == depth {
                count += 1
                i -= 1
            } else if prev.type == .numberedListItem, prev.listDepth > depth {
                // Nested items don't break the sequence
                i -= 1
            } else {
                break
            }
        }
        return count
    }
}
