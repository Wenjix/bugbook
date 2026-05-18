import SwiftUI

// MARK: - Option Button Row (Notion-style: pill + grip dots + kebab on hover)

struct OptionButtonRow: View {
    let label: String
    let color: Color?
    let isActive: Bool
    let isAction: Bool
    let showKebab: Bool
    let onSelect: () -> Void
    let onKebab: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            if showKebab {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                    .opacity(isHovered ? 1 : 0)
            }

            if let color, !isAction {
                Text(label)
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(isAction ? Color.secondary : Color.primary)
            }

            Spacer()

            if showKebab {
                Button(action: onKebab) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }

            if isActive {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(isHovered ? Color.primary.opacity(0.04) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Option Color Row (Notion-style: swatch + name + checkmark)

struct OptionColorRow: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.2))
                .frame(width: 18, height: 18)
            Text(name)
                .font(.callout)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }
}
