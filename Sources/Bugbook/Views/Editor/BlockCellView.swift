import SwiftUI

/// Per-block wrapper with drag handle on hover.
struct BlockCellView: View {
    @ObservedObject var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)? = nil
    @State private var isHovering = false

    var body: some View {
        // Database embed blocks need their own interactive controls to work, so we
        // skip the block-level tap gesture entirely for them.
        Group {
            if block.type == .databaseEmbed {
                blockShell
            } else {
                blockShell
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.shift),
                           let anchor = document.focusedBlockId {
                            document.selectBlockRange(from: anchor, to: block.id)
                        } else {
                            document.clearBlockSelection()
                            document.focusedBlockId = block.id
                        }
                    }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(
                    document.selectedBlockIds.contains(block.id) ? 0.15 : 0
                ))
                .allowsHitTesting(false)
        )
        .trackRenders("BlockCellView")
        .onHover { hovering in isHovering = hovering }
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
            arrowEdge: .leading
        ) {
            BlockMenuView(document: document, blockId: block.id)
        }
        .popover(
            isPresented: Binding(
                get: { document.showPagePicker && document.pagePickerBlockId == block.id },
                set: { if !$0 { document.dismissPagePicker() } }
            ),
            arrowEdge: .bottom
        ) {
            PagePickerView(document: document)
        }
    }

    private var blockShell: some View {
        HStack(alignment: .top, spacing: 4) {
            // Drag handle — click to open block menu
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 24)
                .opacity(isHovering || document.blockMenuBlockId == block.id ? 1 : 0)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture().onEnded {
                        document.blockMenuBlockId = block.id
                    }
                )
                .draggable(block.id.uuidString)

            blockContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            block.backgroundColor != .default
                ? block.backgroundColor.backgroundColor
                : Color.clear
        )
        .cornerRadius(block.backgroundColor != .default ? 4 : 0)
    }

    private func findPageIcon(named name: String) -> String? {
        func search(in entries: [FileEntry]) -> String? {
            for entry in entries {
                let entryName = entry.name.replacingOccurrences(of: ".md", with: "")
                if entryName.localizedCaseInsensitiveCompare(name) == .orderedSame {
                    return entry.icon
                }
                if let children = entry.children, let found = search(in: children) {
                    return found
                }
            }
            return nil
        }
        return search(in: document.availablePages)
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block.type {
        case .paragraph, .heading, .bulletListItem, .numberedListItem, .taskItem, .blockquote:
            TextBlockView(document: document, block: block, onTyping: onTyping)

        case .codeBlock:
            CodeBlockView(document: document, block: block, onTyping: onTyping)

        case .horizontalRule:
            HorizontalRuleView()

        case .image:
            ImageBlockView(block: block)

        case .databaseEmbed:
            DatabaseEmbedBlockView(block: block, onOpenDatabaseTab: document.onOpenDatabaseTab)

        case .pageLink:
            WikiLinkView(
                pageName: block.pageLinkName,
                icon: findPageIcon(named: block.pageLinkName),
                onNavigate: { document.onNavigateToPage?(block.pageLinkName) }
            )

        case .toggle:
            ToggleBlockView(document: document, block: block, onTyping: onTyping)

        case .column:
            ColumnBlockView(document: document, block: block, onTyping: onTyping)
        }
    }
}
