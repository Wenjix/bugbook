import Foundation

enum MarkdownBlockParser {

    // MARK: - Parse

    static func parse(_ markdown: String) -> [Block] {
        guard !markdown.isEmpty else {
            return [Block(type: .paragraph)]
        }

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [Block] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

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
                blocks.append(Block(type: .codeBlock, text: codeLines.joined(separator: "\n"), language: language))
                continue
            }

            // Horizontal rule
            if isHorizontalRule(line) {
                blocks.append(Block(type: .horizontalRule, text: line))
                i += 1
                continue
            }

            // Heading
            if let (level, text) = parseHeading(line) {
                blocks.append(Block(type: .heading, text: text, headingLevel: level))
                i += 1
                continue
            }

            // Task item (must come before bullet)
            if let (depth, checked, text) = parseTaskItem(line) {
                blocks.append(Block(type: .taskItem, text: text, listDepth: depth, isChecked: checked))
                i += 1
                continue
            }

            // Bullet list item
            if let (depth, text) = parseBulletItem(line) {
                blocks.append(Block(type: .bulletListItem, text: text, listDepth: depth))
                i += 1
                continue
            }

            // Numbered list item
            if let (depth, text) = parseNumberedItem(line) {
                blocks.append(Block(type: .numberedListItem, text: text, listDepth: depth))
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
                blocks.append(Block(type: .blockquote, text: text))
                i += 1
                continue
            }

            // Image
            if let (alt, src, width) = parseImage(line) {
                blocks.append(Block(type: .image, imageSource: src, imageAlt: alt, imageWidth: width))
                i += 1
                continue
            }

            // Database embed
            if let path = parseDatabaseEmbed(line) {
                blocks.append(Block(type: .databaseEmbed, databasePath: path))
                i += 1
                continue
            }

            // Column block
            if line.trimmingCharacters(in: .whitespaces) == "<!-- columns -->" {
                var columnChildren: [Block] = []
                i += 1
                while i < lines.count {
                    let colLine = lines[i]
                    if colLine.trimmingCharacters(in: .whitespaces) == "<!-- /columns -->" {
                        i += 1
                        break
                    }
                    if colLine.trimmingCharacters(in: .whitespaces) == "<!-- column-separator -->" {
                        i += 1
                        continue
                    }
                    // Parse each line inside columns as a child block
                    let childBlocks = parse(colLine)
                    columnChildren.append(contentsOf: childBlocks)
                    i += 1
                }
                blocks.append(Block(type: .column, children: columnChildren))
                continue
            }

            // Color comment (applies to next block)
            if let (textColor, bgColor) = parseColorComment(line) {
                i += 1
                if i < lines.count {
                    // Parse the next line as a block and apply colors
                    let nextLine = lines[i]
                    var nextBlocks = parse(nextLine)
                    if !nextBlocks.isEmpty {
                        nextBlocks[0].textColor = textColor
                        nextBlocks[0].backgroundColor = bgColor
                        blocks.append(contentsOf: nextBlocks)
                    }
                    i += 1
                }
                continue
            }

            // Paragraph (including empty lines)
            blocks.append(Block(type: .paragraph, text: line))
            i += 1
        }

        if blocks.isEmpty {
            blocks.append(Block(type: .paragraph))
        }

        return blocks
    }

    // MARK: - Serialize

    static func serialize(_ blocks: [Block]) -> String {
        var lines: [String] = []

        for (i, block) in blocks.enumerated() {
            // Emit color comment before blocks that have non-default colors
            let hasColor = block.textColor != .default || block.backgroundColor != .default
            if hasColor, block.type != .column {
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
                lines.append(block.text)

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

            case .column:
                lines.append("<!-- columns -->")
                for (ci, child) in block.children.enumerated() {
                    if ci > 0 {
                        lines.append("<!-- column-separator -->")
                    }
                    lines.append(serialize([child]))
                }
                lines.append("<!-- /columns -->")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Line Parsers

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
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") else { return nil }
        guard let colonRange = trimmed.range(of: "database:") else { return nil }
        let pathStart = colonRange.upperBound
        let pathEnd = trimmed.index(trimmed.endIndex, offsetBy: -3)
        guard pathStart < pathEnd else { return nil }
        let path = String(trimmed[pathStart..<pathEnd]).trimmingCharacters(in: .whitespaces)
        return path.isEmpty ? nil : path
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
