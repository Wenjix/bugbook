import SwiftUI
import AppKit

struct BreadcrumbView: View {
    let items: [BreadcrumbItem]
    var onNavigate: (BreadcrumbItem) -> Void

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
                            .padding(.leading, index == 0 ? 0 : ShellZoomMetrics.size(6))
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

    @ViewBuilder
    private func breadcrumbIcon(_ icon: String?) -> some View {
        if let icon = icon, !icon.isEmpty {
            if icon.hasPrefix("custom:") {
                let path = String(icon.dropFirst(7))
                if let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: ShellZoomMetrics.size(14), height: ShellZoomMetrics.size(14))
                        .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(3)))
                }
            } else if icon.hasPrefix("sf:") {
                Image(systemName: String(icon.dropFirst(3)))
                    .font(ShellZoomMetrics.font(Typography.caption))
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(ShellZoomMetrics.font(Typography.caption))
            } else if FileManager.default.fileExists(atPath: icon) {
                if let nsImage = NSImage(contentsOfFile: icon) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: ShellZoomMetrics.size(14), height: ShellZoomMetrics.size(14))
                        .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(3)))
                }
            }
        }
    }
}

struct BacklinksMenuButton: View {
    let backlinks: [Backlink]
    let onNavigate: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        Menu {
            Section("Backlinks") {
                ForEach(backlinks) { backlink in
                    Button(backlink.sourceName) {
                        onNavigate(backlink.sourcePath)
                    }
                }
            }
        } label: {
            Image(systemName: "link")
                .font(ShellZoomMetrics.font(Typography.bodySmall, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: ShellZoomMetrics.size(32), height: ShellZoomMetrics.size(32))
        .background(
            RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
