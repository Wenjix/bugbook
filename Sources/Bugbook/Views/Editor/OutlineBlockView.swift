import SwiftUI

/// Auto-generated table of contents that scans all heading and headingToggle
/// blocks in the document and renders a clickable, indented outline.
/// Updates live as headings change.
struct OutlineBlockView: View {
    var document: BlockDocument

    private var headings: [(id: UUID, text: String, level: Int)] {
        collectHeadings(from: document.blocks)
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

    private func headingRow(_ entry: (id: UUID, text: String, level: Int)) -> some View {
        let indent = CGFloat(max(0, entry.level - 1)) * 16

        return Button {
            document.focusedBlockId = entry.id
            document.scrollToBlockId = entry.id
        } label: {
            Text(entry.text.isEmpty ? "Untitled" : entry.text)
                .font(.system(size: EditorTypography.bodyFontSize - 1))
                .foregroundStyle(Color.fallbackTextSecondary)
                .lineLimit(1)
                .padding(.leading, indent)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appCursor(.pointingHand)
    }

    private var emptyState: some View {
        Text("No headings found")
            .font(.system(size: EditorTypography.bodyFontSize - 1))
            .foregroundStyle(Color.fallbackTextSecondary)
            .padding(.vertical, 4)
    }

    // MARK: - Heading Collection

    private func collectHeadings(from blocks: [Block]) -> [(id: UUID, text: String, level: Int)] {
        var result: [(id: UUID, text: String, level: Int)] = []
        for block in blocks {
            if block.type == .heading || block.type == .headingToggle {
                result.append((id: block.id, text: block.text, level: block.headingLevel))
            }
            if !block.children.isEmpty {
                result.append(contentsOf: collectHeadings(from: block.children))
            }
        }
        return result
    }
}
