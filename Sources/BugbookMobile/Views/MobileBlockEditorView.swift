import SwiftUI

// MARK: - Editable Block Model

struct EditableBlock: Identifiable, Equatable {
    let id: UUID
    var type: EditableBlockType
    var text: String
    var isChecked: Bool
    var depth: Int
    var codeLanguage: String

    init(id: UUID = UUID(), type: EditableBlockType = .paragraph, text: String = "",
         isChecked: Bool = false, depth: Int = 0, codeLanguage: String = "") {
        self.id = id
        self.type = type
        self.text = text
        self.isChecked = isChecked
        self.depth = depth
        self.codeLanguage = codeLanguage
    }

    static func == (lhs: EditableBlock, rhs: EditableBlock) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type && lhs.text == rhs.text
            && lhs.isChecked == rhs.isChecked && lhs.depth == rhs.depth
            && lhs.codeLanguage == rhs.codeLanguage
    }
}

enum EditableBlockType: Equatable {
    case heading(Int)
    case paragraph
    case bullet
    case numbered
    case task
    case codeBlock
    case blockquote
    case horizontalRule
    case image(alt: String, url: String)
}

// MARK: - Markdown <-> Blocks

enum BlockMarkdownConverter {

    static func parse(_ markdown: String) -> [EditableBlock] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [EditableBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].hasPrefix("```") { i += 1; break }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(EditableBlock(type: .codeBlock, text: codeLines.joined(separator: "\n"), codeLanguage: language))
                continue
            }

            // Horizontal rule
            if isHorizontalRule(line) {
                blocks.append(EditableBlock(type: .horizontalRule))
                i += 1; continue
            }

            // Heading
            if let (level, text) = parseHeading(line) {
                blocks.append(EditableBlock(type: .heading(level), text: text))
                i += 1; continue
            }

            // Task item
            if let (depth, checked, text) = parseTaskItem(line) {
                blocks.append(EditableBlock(type: .task, text: text, isChecked: checked, depth: depth))
                i += 1; continue
            }

            // Bullet
            if let (depth, text) = parseBulletItem(line) {
                blocks.append(EditableBlock(type: .bullet, text: text, depth: depth))
                i += 1; continue
            }

            // Numbered
            if let (depth, text) = parseNumberedItem(line) {
                blocks.append(EditableBlock(type: .numbered, text: text, depth: depth))
                i += 1; continue
            }

            // Blockquote
            if line.hasPrefix(">") {
                let text: String
                if line.count > 1, line[line.index(after: line.startIndex)] == " " {
                    text = String(line.dropFirst(2))
                } else {
                    text = String(line.dropFirst(1))
                }
                blocks.append(EditableBlock(type: .blockquote, text: text))
                i += 1; continue
            }

            // Image
            if let (alt, url) = parseImage(line) {
                blocks.append(EditableBlock(type: .image(alt: alt, url: url)))
                i += 1; continue
            }

            // Paragraph (including empty lines)
            blocks.append(EditableBlock(type: .paragraph, text: line))
            i += 1
        }

        // Ensure at least one block exists
        if blocks.isEmpty {
            blocks.append(EditableBlock(type: .paragraph))
        }
        return blocks
    }

    static func serialize(_ blocks: [EditableBlock]) -> String {
        var lines: [String] = []

        for (index, block) in blocks.enumerated() {
            switch block.type {
            case .heading(let level):
                lines.append(String(repeating: "#", count: level) + " " + block.text)
            case .paragraph:
                lines.append(block.text)
            case .bullet:
                let indent = String(repeating: "  ", count: block.depth)
                lines.append(indent + "- " + block.text)
            case .numbered:
                let indent = String(repeating: "  ", count: block.depth)
                let num = computeNumber(blocks: blocks, at: index)
                lines.append(indent + "\(num). " + block.text)
            case .task:
                let indent = String(repeating: "  ", count: block.depth)
                let check = block.isChecked ? "x" : " "
                lines.append(indent + "- [\(check)] " + block.text)
            case .codeBlock:
                lines.append("```\(block.codeLanguage)")
                lines.append(block.text)
                lines.append("```")
            case .blockquote:
                lines.append("> " + block.text)
            case .horizontalRule:
                lines.append("---")
            case .image(let alt, let url):
                lines.append("![\(alt)](\(url))")
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
        for ch in line { if ch == "#" { level += 1 } else { break } }
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

    private static func computeNumber(blocks: [EditableBlock], at index: Int) -> Int {
        let current = blocks[index]
        var count = 1
        var j = index - 1
        while j >= 0 {
            let prev = blocks[j]
            if case .numbered = prev.type, prev.depth == current.depth {
                count += 1
                j -= 1
            } else if prev.depth > current.depth {
                j -= 1
            } else {
                break
            }
        }
        return count
    }
}

// MARK: - Block Editor View

struct MobileBlockEditorView: View {
    @Binding var blocks: [EditableBlock]
    var onBlocksChanged: (() -> Void)?

    @State private var focusedBlockId: UUID?
    @State private var showBlockMenu = false
    @State private var menuTargetBlockId: UUID?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                BlockRowView(
                    block: binding(for: index),
                    isFocused: focusedBlockId == block.id,
                    onFocus: { focusedBlockId = block.id },
                    onReturn: { insertBlockAfter(index: index) },
                    onDelete: { deleteBlockIfEmpty(index: index) },
                    onToggleCheck: { toggleCheck(index: index) },
                    onIndent: { indent(index: index) },
                    onOutdent: { outdent(index: index) },
                    onBlocksChanged: onBlocksChanged
                )
            }
        }
    }

    private func binding(for index: Int) -> Binding<EditableBlock> {
        Binding(
            get: { index < blocks.count ? blocks[index] : EditableBlock() },
            set: { newValue in
                guard index < blocks.count else { return }
                blocks[index] = newValue
            }
        )
    }

    private func insertBlockAfter(index: Int) {
        let current = blocks[index]
        var newType: EditableBlockType = .paragraph
        var newDepth = 0

        // Continue list type
        switch current.type {
        case .bullet:
            newType = .bullet
            newDepth = current.depth
        case .numbered:
            newType = .numbered
            newDepth = current.depth
        case .task:
            newType = .task
            newDepth = current.depth
        case .blockquote:
            newType = .blockquote
        default:
            break
        }

        // If current block is empty list item, convert to paragraph instead
        if current.text.isEmpty && (current.type == .bullet || current.type == .numbered || current.type == .task) {
            blocks[index].type = .paragraph
            blocks[index].depth = 0
            onBlocksChanged?()
            return
        }

        let newBlock = EditableBlock(type: newType, depth: newDepth)
        let insertIndex = index + 1
        blocks.insert(newBlock, at: insertIndex)
        focusedBlockId = newBlock.id
        onBlocksChanged?()
    }

    private func deleteBlockIfEmpty(index: Int) {
        guard index > 0, index < blocks.count, blocks[index].text.isEmpty else { return }
        let prevId = blocks[index - 1].id
        blocks.remove(at: index)
        focusedBlockId = prevId
        onBlocksChanged?()
    }

    private func toggleCheck(index: Int) {
        guard index < blocks.count else { return }
        blocks[index].isChecked.toggle()
        onBlocksChanged?()
    }

    private func indent(index: Int) {
        guard index < blocks.count else { return }
        let block = blocks[index]
        switch block.type {
        case .bullet, .numbered, .task:
            if block.depth < 4 {
                blocks[index].depth += 1
                onBlocksChanged?()
            }
        default: break
        }
    }

    private func outdent(index: Int) {
        guard index < blocks.count else { return }
        let block = blocks[index]
        switch block.type {
        case .bullet, .numbered, .task:
            if block.depth > 0 {
                blocks[index].depth -= 1
                onBlocksChanged?()
            }
        default: break
        }
    }
}

// MARK: - Block Row View

private struct BlockRowView: View {
    @Binding var block: EditableBlock
    let isFocused: Bool
    let onFocus: () -> Void
    let onReturn: () -> Void
    let onDelete: () -> Void
    let onToggleCheck: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    var onBlocksChanged: (() -> Void)?

    @FocusState private var textFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Leading decoration
            leadingDecoration
                .frame(width: leadingWidth, alignment: .trailing)
                .padding(.trailing, 6)

            // Content
            blockContent
        }
        .padding(.leading, CGFloat(block.depth) * 20)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
        .onTapGesture { onFocus(); textFieldFocused = true }
        .onChange(of: isFocused) { _, newValue in
            if newValue { textFieldFocused = true }
        }
    }

    private var verticalPadding: CGFloat {
        switch block.type {
        case .heading(1): return 12
        case .heading(2): return 8
        case .heading: return 6
        case .horizontalRule: return 8
        case .codeBlock: return 4
        default: return 1
        }
    }

    private var leadingWidth: CGFloat {
        switch block.type {
        case .bullet, .task, .numbered, .blockquote: return 24
        default: return 0
        }
    }

    @ViewBuilder
    private var leadingDecoration: some View {
        switch block.type {
        case .bullet:
            Text("\u{2022}")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        case .numbered:
            Text("1.")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        case .task:
            Button(action: onToggleCheck) {
                Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(block.isChecked ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        case .blockquote:
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary)
                .frame(width: 3)
                .padding(.vertical, 2)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block.type {
        case .heading(let level):
            TextField("Heading", text: $block.text, axis: .vertical)
                .font(headingFont(level))
                .fontWeight(.bold)
                .focused($textFieldFocused)
                .onSubmit { onReturn() }
                .onChange(of: block.text) { _, _ in onBlocksChanged?() }

        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)

        case .codeBlock:
            VStack(alignment: .leading, spacing: 4) {
                if !block.codeLanguage.isEmpty {
                    Text(block.codeLanguage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Code", text: $block.text, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .focused($textFieldFocused)
                    .onChange(of: block.text) { _, _ in onBlocksChanged?() }
            }
            .padding(12)
            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .image(let alt, let url):
            if let imageURL = URL(string: url), url.hasPrefix("http") {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
                    .foregroundStyle(.secondary)
            }

        default:
            // Paragraph, bullet text, numbered text, task text, blockquote text
            TextField(placeholder, text: $block.text, axis: .vertical)
                .font(.body)
                .foregroundStyle(textStyle)
                .strikethrough(block.type == .task && block.isChecked)
                .italic(block.type == .blockquote)
                .focused($textFieldFocused)
                .onSubmit { onReturn() }
                .onChange(of: block.text) { _, _ in onBlocksChanged?() }
        }
    }

    private var placeholder: String {
        switch block.type {
        case .bullet, .numbered: return "List item"
        case .task: return "Task"
        case .blockquote: return "Quote"
        default: return "Type something..."
        }
    }

    private var textStyle: Color {
        if block.type == .task && block.isChecked { return .secondary }
        if block.type == .blockquote { return .secondary }
        return .primary
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .title3
        default: return .headline
        }
    }
}

// MARK: - Block Type Menu

struct BlockTypeMenuView: View {
    let onSelect: (EditableBlockType) -> Void
    @Environment(\.dismiss) private var dismiss

    private let options: [(String, String, EditableBlockType)] = [
        ("Paragraph", "text.alignleft", .paragraph),
        ("Heading 1", "textformat.size.larger", .heading(1)),
        ("Heading 2", "textformat.size", .heading(2)),
        ("Heading 3", "textformat.size.smaller", .heading(3)),
        ("Bullet List", "list.bullet", .bullet),
        ("Numbered List", "list.number", .numbered),
        ("Task", "checklist", .task),
        ("Quote", "text.quote", .blockquote),
        ("Code", "chevron.left.forwardslash.chevron.right", .codeBlock),
        ("Divider", "minus", .horizontalRule),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(options, id: \.0) { name, icon, type in
                    Button {
                        onSelect(type)
                        dismiss()
                    } label: {
                        Label(name, systemImage: icon)
                    }
                }
            }
            .navigationTitle("Block Type")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Editing Toolbar

struct BlockEditingToolbar: View {
    @Binding var blocks: [EditableBlock]
    var focusedBlockId: UUID?
    var onBlocksChanged: (() -> Void)?

    @State private var showBlockTypeMenu = false

    private var focusedIndex: Int? {
        guard let id = focusedBlockId else { return nil }
        return blocks.firstIndex(where: { $0.id == id })
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button { showBlockTypeMenu = true } label: {
                    Image(systemName: "plus.square")
                }

                Divider().frame(height: 20)

                Button { setBlockType(.heading(1)) } label: {
                    Text("H1").font(.caption.bold())
                }
                Button { setBlockType(.heading(2)) } label: {
                    Text("H2").font(.caption.bold())
                }

                Divider().frame(height: 20)

                Button { setBlockType(.bullet) } label: {
                    Image(systemName: "list.bullet")
                }
                Button { setBlockType(.numbered) } label: {
                    Image(systemName: "list.number")
                }
                Button { setBlockType(.task) } label: {
                    Image(systemName: "checklist")
                }
                Button { setBlockType(.blockquote) } label: {
                    Image(systemName: "text.quote")
                }

                Divider().frame(height: 20)

                Button { indentFocused() } label: {
                    Image(systemName: "increase.indent")
                }
                Button { outdentFocused() } label: {
                    Image(systemName: "decrease.indent")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showBlockTypeMenu) {
            BlockTypeMenuView { type in
                setBlockType(type)
            }
        }
    }

    private func setBlockType(_ type: EditableBlockType) {
        guard let index = focusedIndex else { return }
        blocks[index].type = type
        if case .bullet = type { } else if case .numbered = type { } else if case .task = type { } else {
            blocks[index].depth = 0
        }
        onBlocksChanged?()
    }

    private func indentFocused() {
        guard let index = focusedIndex else { return }
        let block = blocks[index]
        switch block.type {
        case .bullet, .numbered, .task:
            if block.depth < 4 {
                blocks[index].depth += 1
                onBlocksChanged?()
            }
        default: break
        }
    }

    private func outdentFocused() {
        guard let index = focusedIndex else { return }
        let block = blocks[index]
        switch block.type {
        case .bullet, .numbered, .task:
            if block.depth > 0 {
                blocks[index].depth -= 1
                onBlocksChanged?()
            }
        default: break
        }
    }
}
