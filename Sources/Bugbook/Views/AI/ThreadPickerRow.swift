import SwiftUI

/// Reusable thread row for AI thread picker popovers.
/// Provides hover highlight, active-thread checkmark, and delete context menu.
struct ThreadRow: View {
    let thread: AiThread
    let isActive: Bool
    let timestamp: String
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.title)
                        .font(.system(size: Typography.bodySmall, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(Color.fallbackTextPrimary)
                        .lineLimit(1)
                    Text(timestamp)
                        .font(.system(size: Typography.caption2))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isActive || isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Thread", systemImage: "trash")
            }
        }
    }
}

/// "New Thread" button used at the top of thread picker popovers.
struct NewThreadButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                Text("New Thread")
                    .font(.system(size: Typography.bodySmall, weight: .medium))
                    .foregroundStyle(Color.fallbackTextPrimary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
