import SwiftUI

/// Highlighted callout container with icon, editable title, and nested child blocks.
/// Supports four variants: info (blue), warning (orange), success (green), error (red).
struct CalloutBlockView: View {
    var document: BlockDocument
    let block: Block
    var onTyping: (() -> Void)? = nil
    @State private var textHeight: CGFloat = 24

    private var variant: String { block.calloutType }

    private var variantColor: Color {
        switch variant {
        case "warning": return .orange
        case "success": return .green
        case "error": return .red
        default: return .blue
        }
    }

    private var variantIcon: String {
        switch variant {
        case "warning": return "exclamationmark.triangle"
        case "success": return "checkmark.circle"
        case "error": return "xmark.circle"
        default: return "info.circle"
        }
    }

    private static let variantCycle = ["info", "warning", "success", "error"]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left accent border
            RoundedRectangle(cornerRadius: 1.5)
                .fill(variantColor)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                // Header: icon + editable title
                HStack(alignment: .top, spacing: 6) {
                    Button {
                        cycleVariant()
                    } label: {
                        Image(systemName: variantIcon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(variantColor)
                            .frame(width: 20, height: 24)
                    }
                    .buttonStyle(.plain)
                    .appCursor(.pointingHand)

                    BlockTextView(
                        document: document,
                        blockId: block.id,
                        selectionVersion: document.selectionVersion,
                        font: .systemFont(ofSize: EditorTypography.bodyFontSize, weight: .semibold),
                        textColor: .labelColor,
                        placeholder: "Callout",
                        onTextChange: onTyping,
                        textHeight: $textHeight
                    )
                    .frame(height: textHeight)
                }

                // Children
                if !block.children.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(block.children) { child in
                            BlockCellView(document: document, block: child, onTyping: onTyping)
                                .padding(.vertical, 1)
                        }
                    }
                    .padding(.leading, 26)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(variantColor.opacity(0.08))
        )
    }

    private func cycleVariant() {
        guard let idx = document.index(for: block.id) else { return }
        let cycle = Self.variantCycle
        let currentIndex = cycle.firstIndex(of: variant) ?? 0
        let nextIndex = (currentIndex + 1) % cycle.count
        document.blocks[idx].calloutType = cycle[nextIndex]
    }
}
