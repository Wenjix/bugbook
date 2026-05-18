import SwiftUI
import AppKit

struct FootnoteBlockView: View {
    var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)?
    @State private var textHeight: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            HStack(spacing: 0) {
                Text("[^")
                    .foregroundStyle(.secondary)
                TextField("label", text: footnoteLabel)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 16, maxWidth: 96)
                    .onSubmit {
                        document.focusedBlockId = block.id
                        document.cursorPosition = 0
                    }
                Text("]")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.fallbackBadgeBg, in: RoundedRectangle(cornerRadius: 4))
            .padding(.top, 1)

            ZStack(alignment: .topLeading) {
                BlockTextView(
                    document: document,
                    blockId: block.id,
                    selectionVersion: document.selectionVersion,
                    isMultiline: true,
                    font: .systemFont(ofSize: EditorTypography.bodyFontSize),
                    textColor: .labelColor,
                    strikethrough: false,
                    placeholder: nil,
                    onTextChange: onTyping,
                    textHeight: $textHeight
                )
                .frame(height: textHeight)

                if block.text.isEmpty {
                    Text("Footnote")
                        .font(.system(size: EditorTypography.bodyFontSize))
                        .foregroundStyle(Color(nsColor: .placeholderTextColor))
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .editorTextCursor()
    }

    private var footnoteLabel: Binding<String> {
        Binding(
            get: {
                document.block(for: block.id)?.footnoteLabel ?? block.footnoteLabel
            },
            set: { newValue in
                let sanitized = Self.sanitizeLabel(newValue)
                guard sanitized != document.block(for: block.id)?.footnoteLabel else { return }
                document.updateBlockProperty(id: block.id) { $0.footnoteLabel = sanitized }
                onTyping?()
            }
        )
    }

    private static func sanitizeLabel(_ label: String) -> String {
        label
            .filter { $0 != "]" && !$0.isNewline }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
