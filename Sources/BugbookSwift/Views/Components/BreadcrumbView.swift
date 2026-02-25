import SwiftUI
import AppKit

struct BreadcrumbView: View {
    let items: [BreadcrumbItem]
    var onNavigate: (BreadcrumbItem) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Button(action: { onNavigate(item) }) {
                    HStack(spacing: 3) {
                        breadcrumbIcon(item.icon)
                        Text(item.name)
                            .font(.system(size: 13))
                            .foregroundColor(index == items.count - 1 ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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
