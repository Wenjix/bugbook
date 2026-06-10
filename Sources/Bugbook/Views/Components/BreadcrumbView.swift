import SwiftUI

struct BreadcrumbView: View {
    let items: [BreadcrumbItem]
    var onNavigate: (BreadcrumbItem) -> Void
    var sidebarOpen: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: ShellZoomMetrics.size(6)) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Text("/")
                                .font(ShellZoomMetrics.font(Typography.caption, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.horizontal, ShellZoomMetrics.size(1))
                        }
                        Button(action: { onNavigate(item) }) {
                            HStack(spacing: ShellZoomMetrics.size(4)) {
                                breadcrumbIcon(item.icon)
                                Text(item.name)
                                    .font(
                                        ShellZoomMetrics.font(
                                            Typography.bodySmall,
                                            weight: index == items.count - 1 ? .medium : .regular
                                        )
                                    )
                                    .foregroundStyle(index == items.count - 1 ? .primary : .secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.leading, index == 0 && !sidebarOpen ? ShellZoomMetrics.size(2) : ShellZoomMetrics.size(6))
                            .padding(.trailing, ShellZoomMetrics.size(6))
                            .padding(.vertical, ShellZoomMetrics.size(4))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(index == items.count - 1)
                    }
                }
                .padding(.trailing, ShellZoomMetrics.size(8))
            }
            .scrollIndicators(.hidden)
            Spacer(minLength: 0)
        }
        .padding(.vertical, ShellZoomMetrics.size(6))
        .background(Color.fallbackEditorBg)
    }

    private func breadcrumbIcon(_ icon: String?) -> some View {
        PageIconView(
            icon: icon,
            imageSize: ShellZoomMetrics.size(14),
            symbolFont: ShellZoomMetrics.font(Typography.caption),
            emojiFont: ShellZoomMetrics.font(Typography.caption),
            cornerRadius: ShellZoomMetrics.size(3)
        ) {
            EmptyView()
        }
    }
}

