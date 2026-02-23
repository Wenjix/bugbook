import SwiftUI

/// Per-block wrapper with drag handle on hover.
struct BlockCellView: View {
    @ObservedObject var document: BlockDocument
    let block: Block
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // Drag handle — click to open block menu
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 24)
                .opacity(isHovering ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    document.blockMenuBlockId = block.id
                }
                .draggable(block.id.uuidString)

            // Block content
            blockContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .background(
            block.backgroundColor != .default
                ? block.backgroundColor.backgroundColor
                : Color.clear
        )
        .cornerRadius(block.backgroundColor != .default ? 4 : 0)
        .onHover { hovering in
            isHovering = hovering
        }
        .popover(
            isPresented: Binding(
                get: { document.slashMenuBlockId == block.id },
                set: { if !$0 { document.dismissSlashMenu() } }
            ),
            arrowEdge: .bottom
        ) {
            SlashCommandMenu(document: document)
        }
        .popover(
            isPresented: Binding(
                get: { document.blockMenuBlockId == block.id },
                set: { if !$0 { document.dismissBlockMenu() } }
            ),
            arrowEdge: .trailing
        ) {
            BlockMenuView(document: document, blockId: block.id)
        }
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block.type {
        case .paragraph, .heading, .bulletListItem, .numberedListItem, .taskItem, .blockquote:
            TextBlockView(document: document, block: block)

        case .codeBlock:
            CodeBlockView(document: document, block: block)

        case .horizontalRule:
            HorizontalRuleView()

        case .image:
            ImageBlockView(block: block)

        case .databaseEmbed:
            DatabaseEmbedBlockView(block: block)

        case .column:
            ColumnBlockView(document: document, block: block)
        }
    }
}
