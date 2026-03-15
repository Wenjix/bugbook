import SwiftUI

/// Flip-style flashcard block with editable front text and nested back content.
struct FlashcardBlockView: View {
    var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Button("Flip", systemImage: "rectangle.on.rectangle") {
                    withAnimation(flipAnimation) {
                        if let idx = document.index(for: block.id) {
                            document.blocks[idx].isExpanded.toggle()
                            // Clear focus so the back side doesn't auto-grab it
                            if document.blocks[idx].isExpanded {
                                document.focusedBlockId = nil
                            }
                        }
                    }
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .rotation3DEffect(
                    .degrees(block.isExpanded ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0)
                )
                .frame(width: 20, height: 24)
                .contentShape(Rectangle())
                .buttonStyle(.plain)

                if !block.isExpanded {
                    BlockTextView(
                        document: document,
                        blockId: block.id,
                        selectionVersion: document.selectionVersion,
                        font: .systemFont(ofSize: EditorTypography.bodyFontSize),
                        textColor: .labelColor,
                        placeholder: "Flashcard front",
                        onTextChange: onTyping,
                        textHeight: $textHeight
                    )
                    .frame(height: textHeight)
                }
            }

            if block.isExpanded {
                backContent
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .animation(flipAnimation, value: block.isExpanded)
    }

    @ViewBuilder
    private var backContent: some View {
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
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor),
                        Color(nsColor: .windowBackgroundColor).opacity(0.92),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var flipAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.12)
            : .spring(response: 0.28, dampingFraction: 0.84)
    }

    private func addChild() {
        guard let idx = document.index(for: block.id) else { return }
        let newChild = Block(type: .paragraph)
        document.blocks[idx].children.append(newChild)
        document.focusedBlockId = newChild.id
        document.cursorPosition = 0
    }
}
