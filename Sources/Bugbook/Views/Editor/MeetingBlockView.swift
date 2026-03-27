import SwiftUI

/// Compact meeting card block — shows title and recording controls.
/// Notes live as regular editor blocks below this card.
struct MeetingBlockView: View {
    var document: BlockDocument
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: icon + title
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: Typography.body, weight: .medium))
                    .foregroundStyle(.tint)

                Text(block.text.isEmpty ? "Meeting" : block.text)
                    .font(.system(size: Typography.body, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                // Placeholder for future recording controls
                Text("Type notes below")
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(Opacity.subtle))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .contentShape(Rectangle())
        .onTapGesture {
            document.focusOrInsertParagraphAfter(blockId: block.id)
        }
    }
}
