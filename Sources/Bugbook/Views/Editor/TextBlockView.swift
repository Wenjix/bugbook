import SwiftUI
import AppKit

/// Renders paragraph, heading, bullet, numbered, task, and blockquote blocks.
struct TextBlockView: View {
    var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)? = nil
    @State private var textHeight: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if block.listDepth > 0 {
                Color.clear.frame(width: CGFloat(block.listDepth) * 24)
            }

            prefixView

            ZStack(alignment: .topLeading) {
                BlockTextView(
                    document: document,
                    blockId: block.id,
                    selectionVersion: document.selectionVersion,
                    isMultiline: false,
                    font: nsFont,
                    textColor: nsTextColor,
                    strikethrough: block.type == .taskItem && block.isChecked,
                    placeholder: nil,
                    onTextChange: onTyping,
                    textHeight: $textHeight
                )
                .frame(height: textHeight)

                // SwiftUI placeholder overlay — more reliable than NSTextView draw override
                if let placeholder = titlePlaceholder, block.text.isEmpty {
                    Text(placeholder)
                        .font(swiftUIFont)
                        .foregroundStyle(Color(nsColor: .placeholderTextColor))
                        .padding(.top, 2) // match textContainerInset
                        .allowsHitTesting(false)
                }
            }
        }
        .editorTextCursor()
    }

    @ViewBuilder
    private var prefixView: some View {
        switch block.type {
        case .bulletListItem:
            Text("\u{2022}")
                .font(.system(size: EditorTypography.bodyFontSize))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

        case .numberedListItem:
            Text("\(computeNumber()).")
                .font(.system(size: EditorTypography.bodyFontSize))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 2)

        case .taskItem:
            Button {
                document.toggleCheck(id: block.id)
            } label: {
                Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(block.isChecked ? Color.dragIndicator : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20)
            .padding(.top, 3)

        case .blockquote:
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.fallbackBadgeBg)
                .frame(width: 3)
                .padding(.vertical, 2)

        default:
            EmptyView()
        }
    }

    private var titlePlaceholder: String? {
        guard block.type == .heading, block.headingLevel == 1 else { return nil }
        let blocks = document.blocks
        guard !blocks.isEmpty, blocks[0].id == block.id else { return nil }
        return "New page"
    }

    private var swiftUIFont: Font {
        switch block.type {
        case .heading:
            switch block.headingLevel {
            case 1: return .system(size: EditorTypography.scaled(30), weight: .bold)
            case 2: return .system(size: EditorTypography.scaled(24), weight: .semibold)
            case 3: return .system(size: EditorTypography.scaled(21), weight: .semibold)
            default: return .system(size: EditorTypography.bodyFontSize)
            }
        default:
            return .system(size: EditorTypography.bodyFontSize)
        }
    }

    private var nsFont: NSFont {
        switch block.type {
        case .heading:
            switch block.headingLevel {
            case 1: return .systemFont(ofSize: EditorTypography.scaled(30), weight: .bold)
            case 2: return .systemFont(ofSize: EditorTypography.scaled(24), weight: .semibold)
            case 3: return .systemFont(ofSize: EditorTypography.scaled(20), weight: .semibold)
            case 4: return .systemFont(ofSize: EditorTypography.scaled(17), weight: .semibold)
            case 5: return .systemFont(ofSize: EditorTypography.bodyFontSize, weight: .semibold)
            case 6: return .systemFont(ofSize: EditorTypography.scaled(13), weight: .semibold)
            default: return .systemFont(ofSize: EditorTypography.bodyFontSize)
            }
        default:
            return .systemFont(ofSize: EditorTypography.bodyFontSize)
        }
    }

    private var nsTextColor: NSColor {
        // Block-level text color takes priority
        if block.textColor != .default {
            return block.textColor.nsTextColor
        }
        switch block.type {
        case .blockquote:
            return .secondaryLabelColor
        case .taskItem where block.isChecked:
            return .tertiaryLabelColor
        default:
            return .labelColor
        }
    }

    private func computeNumber() -> Int {
        guard let idx = document.index(for: block.id) else { return 1 }
        var num = 1
        var i = idx - 1
        while i >= 0 {
            let prev = document.blocks[i]
            if prev.type == .numberedListItem, prev.listDepth == block.listDepth {
                num += 1
                i -= 1
            } else if prev.type == .numberedListItem, prev.listDepth > block.listDepth {
                i -= 1
            } else {
                break
            }
        }
        return num
    }
}
