import SwiftUI
import AppKit

/// Multi-line code block with language label.
struct CodeBlockView: View {
    var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)? = nil
    @State private var textHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !block.language.isEmpty {
                Text(block.language)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            BlockTextView(
                document: document,
                blockId: block.id,
                selectionVersion: document.selectionVersion,
                isMultiline: true,
                font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                textColor: .labelColor,
                onTextChange: onTyping,
                textHeight: $textHeight
            )
            .frame(height: textHeight)
            .padding(.horizontal, 12)
            .padding(.vertical, block.language.isEmpty ? 12 : 4)
            .padding(.bottom, 8)
        }
        .background(Color.fallbackBgSecondary)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.fallbackBorderColor, lineWidth: 1)
        )
        .editorTextCursor()
    }
}
