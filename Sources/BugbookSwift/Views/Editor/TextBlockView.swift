import SwiftUI
import AppKit

/// Renders paragraph, heading, bullet, numbered, task, and blockquote blocks.
struct TextBlockView: View {
    @ObservedObject var document: BlockDocument
    let block: Block
    @State private var textHeight: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if block.listDepth > 0 {
                Color.clear.frame(width: CGFloat(block.listDepth) * 24)
            }

            prefixView

            BlockTextView(
                document: document,
                blockId: block.id,
                isMultiline: false,
                font: nsFont,
                textColor: nsTextColor,
                placeholder: titlePlaceholder,
                textHeight: $textHeight
            )
            .frame(height: textHeight)
        }
    }

    @ViewBuilder
    private var prefixView: some View {
        switch block.type {
        case .bulletListItem:
            Text("\u{2022}")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

        case .numberedListItem:
            Text("\(computeNumber()).")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 2)

        case .taskItem:
            Button {
                document.toggleCheck(id: block.id)
            } label: {
                Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(block.isChecked ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20)
            .padding(.top, 3)

        case .blockquote:
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 3)
                .padding(.vertical, 2)

        default:
            EmptyView()
        }
    }

    private var titlePlaceholder: String? {
        guard block.type == .heading, block.headingLevel == 1 else { return nil }
        guard document.blocks.first?.id == block.id else { return nil }
        return "New page"
    }

    private var nsFont: NSFont {
        switch block.type {
        case .heading:
            switch block.headingLevel {
            case 1: return .systemFont(ofSize: 30, weight: .bold)
            case 2: return .systemFont(ofSize: 24, weight: .semibold)
            case 3: return .systemFont(ofSize: 20, weight: .semibold)
            case 4: return .systemFont(ofSize: 17, weight: .semibold)
            case 5: return .systemFont(ofSize: 15, weight: .semibold)
            case 6: return .systemFont(ofSize: 13, weight: .semibold)
            default: return .systemFont(ofSize: 15)
            }
        default:
            return .systemFont(ofSize: 15)
        }
    }

    private var nsTextColor: NSColor {
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
