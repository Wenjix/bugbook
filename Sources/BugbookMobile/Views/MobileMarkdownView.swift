import SwiftUI

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

            // Wiki link (standalone line)
            if let name = parseWikiLink(line) {
                blocks.append(MdBlock(type: .wikiLink(name: name), content: ""))
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

    var body: some View {
        if let url = URL(string: urlString), urlString.hasPrefix("http") {
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
    }
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
            ImageBlockView(alt: alt, urlString: url)

        case .wikiLink(let name):
            Text(name)
                .foregroundStyle(.blue)
        }
    }
}
