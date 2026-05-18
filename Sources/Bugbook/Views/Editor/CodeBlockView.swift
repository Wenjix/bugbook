import SwiftUI
import AppKit

/// Multi-line code block with language label.
struct CodeBlockView: View {
    var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)?
    @State private var textHeight: CGFloat = 24
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            BlockTextView(
                document: document,
                blockId: block.id,
                selectionVersion: document.selectionVersion,
                isMultiline: true,
                font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                textColor: .labelColor,
                contentMode: .plainCode(language: block.language),
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

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Language", text: languageBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 180, alignment: .leading)

            Spacer()

            Button(action: copyCode) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(copied ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy code")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: {
                document.block(for: block.id)?.language ?? block.language
            },
            set: { newValue in
                let sanitized = newValue
                    .filter { !$0.isWhitespace && !$0.isNewline }
                    .lowercased()
                guard sanitized != document.block(for: block.id)?.language else { return }
                document.updateBlockProperty(id: block.id) { $0.language = sanitized }
                onTyping?()
            }
        )
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(document.block(for: block.id)?.text ?? block.text, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }
}
