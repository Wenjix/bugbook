import SwiftUI

/// Collapsible heading toggle block — heading-sized title with a chevron and nested child blocks.
struct HeadingToggleBlockView: View {
    var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)? = nil
    @State private var textHeight: CGFloat = 30

    private var headingFont: NSFont {
        switch block.headingLevel {
        case 1: return .systemFont(ofSize: EditorTypography.scaled(30), weight: .bold)
        case 2: return .systemFont(ofSize: EditorTypography.scaled(24), weight: .semibold)
        case 3: return .systemFont(ofSize: EditorTypography.scaled(20), weight: .semibold)
        default: return .systemFont(ofSize: EditorTypography.scaled(20), weight: .semibold)
        }
    }

    private var chevronSize: CGFloat {
        switch block.headingLevel {
        case 1: return 14
        case 2: return 13
        default: return 12
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: chevron + heading title
            HStack(alignment: .top, spacing: 4) {
                Button("Toggle", systemImage: "chevron.right") {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        if let idx = document.index(for: block.id) {
                            document.blocks[idx].isExpanded.toggle()
                        }
                    }
                }
                .labelStyle(.iconOnly)
                .font(.system(size: chevronSize, weight: .medium))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(block.isExpanded ? 90 : 0))
                .frame(width: 20, height: textHeight > 0 ? min(textHeight, 36) : 30)
                .contentShape(Rectangle())
                .buttonStyle(.plain)

                BlockTextView(
                    document: document,
                    blockId: block.id,
                    selectionVersion: document.selectionVersion,
                    font: headingFont,
                    textColor: .labelColor,
                    placeholder: "Heading",
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
                            .overlay {
                                Button { addChild() } label: { Color.clear }
                                    .buttonStyle(.plain)
                            }
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
