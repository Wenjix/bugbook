import SwiftUI

/// Auto-generated table of contents that scans all heading and headingToggle
/// blocks in the document and renders a clickable, indented outline.
/// Updates live as headings change.
struct OutlineBlockView: View {
    var document: BlockDocument

    private var headings: [(id: UUID, text: String, depth: Int)] {
        // Skip H1 (page title) — TOC should only show sub-headings
        // depth = nesting depth in the block tree, not heading level number
        collectHeadings(from: document.blocks, depth: 0).filter { $0.depth > 0 || true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if headings.isEmpty {
                emptyState
            } else {
                ForEach(headings, id: \.id) { entry in
                    headingRow(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.primary.opacity(Opacity.subtle))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.primary.opacity(Opacity.light), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    // MARK: - Rows

    private func headingRow(_ entry: (id: UUID, text: String, depth: Int)) -> some View {
        let indent = CGFloat(entry.depth) * 16

        return TOCLink(text: entry.text, indent: indent) {
            document.focusedBlockId = entry.id
            document.scrollToBlockId = entry.id
        }
    }

    private var emptyState: some View {
        Text("No headings found")
            .font(.system(size: EditorTypography.bodyFontSize - 1))
            .foregroundStyle(Color.fallbackTextSecondary)
            .padding(.vertical, 4)
    }

    // MARK: - Heading Collection

    /// Collect headings with their nesting depth in the block tree (not heading level number).
    /// depth 0 = top-level heading, depth 1 = heading inside a toggle/callout/etc.
    private func collectHeadings(from blocks: [Block], depth: Int) -> [(id: UUID, text: String, depth: Int)] {
        var result: [(id: UUID, text: String, depth: Int)] = []
        for block in blocks {
            if (block.type == .heading || block.type == .headingToggle), block.headingLevel > 1 {
                let plainText = AttributedStringConverter.plainText(from: block.text)
                result.append((id: block.id, text: plainText, depth: depth))
            }
            if !block.children.isEmpty {
                result.append(contentsOf: collectHeadings(from: block.children, depth: depth + 1))
            }
        }
        return result
    }
}

/// A single TOC link with hover highlight.
private struct TOCLink: View {
    let text: String
    let indent: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(text.isEmpty ? "Untitled" : text)
                .font(.system(size: EditorTypography.bodyFontSize - 1))
                .foregroundStyle(isHovered ? Color.primary : Color.fallbackTextSecondary)
                .underline()
                .lineLimit(1)
                .padding(.leading, indent)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appCursor(.pointingHand)
        .onHover { isHovered = $0 }
    }
}
