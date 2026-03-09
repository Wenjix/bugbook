import SwiftUI
import AppKit

struct BreadcrumbView: View {
    let items: [BreadcrumbItem]
    var onNavigate: (BreadcrumbItem) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Text("/")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.8))
                                .padding(.horizontal, 1)
                        }
                        Button(action: { onNavigate(item) }) {
                            HStack(spacing: 4) {
                                breadcrumbIcon(item.icon)
                                Text(item.name)
                                    .font(.system(size: 13, weight: index == items.count - 1 ? .medium : .regular))
                                    .foregroundColor(index == items.count - 1 ? .primary : .secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(index == items.count - 1)
                    }
                }
                .padding(.trailing, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
                        .frame(width: 14, height: 14)
                }
            } else if icon.hasPrefix("sf:") {
                Image(systemName: String(icon.dropFirst(3)))
                    .font(.system(size: 12))
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.system(size: 12))
            } else if FileManager.default.fileExists(atPath: icon) {
                if let nsImage = NSImage(contentsOfFile: icon) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
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
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 32, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
