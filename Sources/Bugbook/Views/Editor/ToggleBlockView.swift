import SwiftUI

/// Collapsible toggle block with a chevron, editable title, and nested child blocks.
struct ToggleBlockView: View {
    @ObservedObject var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)? = nil
    @State private var textHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: chevron + title
            HStack(alignment: .top, spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        if let idx = document.index(for: block.id) {
                            document.blocks[idx].isExpanded.toggle()
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(block.isExpanded ? 90 : 0))
                        .frame(width: 20, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                BlockTextView(
                    document: document,
                    blockId: block.id,
                    font: .systemFont(ofSize: EditorTypography.bodyFontSize),
                    textColor: .labelColor,
                    placeholder: "Toggle heading",
                    onTextChange: onTyping,
                    textHeight: $textHeight
                )
                .frame(height: textHeight)
            }

            // Children (when expanded)
            if block.isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if block.children.isEmpty {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .contentShape(Rectangle())
                            .onTapGesture { addChild() }
                    } else {
                        ForEach(block.children) { child in
                            BlockCellView(document: document, block: child, onTyping: onTyping)
                                .padding(.vertical, 1)
                        }
                    }
                }
                .padding(.leading, 0)
            }
        }
    }

    private func addChild() {
        guard let idx = document.index(for: block.id) else { return }
        let newChild = Block(type: .paragraph)
        document.blocks[idx].children.append(newChild)
        document.focusedBlockId = newChild.id
        document.cursorPosition = 0
    }
}
