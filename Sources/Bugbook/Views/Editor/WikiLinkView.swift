import SwiftUI
import UniformTypeIdentifiers

struct WikiLinkView: View {
    let pageName: String
    let icon: String?
    var onNavigate: () -> Void
    var sidebarReferencePayload: SidebarReferenceDragPayload?

    var body: some View {
        if let sidebarReferencePayload {
            linkButton
                .onDrag {
                    let encoder = JSONEncoder()
                    let data = (try? encoder.encode(sidebarReferencePayload)) ?? Data()
                    return NSItemProvider(item: data as NSData, typeIdentifier: UTType.json.identifier)
                }
        } else {
            linkButton
        }
    }

    @ViewBuilder
    private var linkButton: some View {
        Button(action: onNavigate) {
            HStack(spacing: 4) {
                iconView
                Text(pageName)
                    .font(.system(size: EditorTypography.bodyFontSize))
                    .foregroundStyle(.primary)
                    .underline()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = icon, !icon.isEmpty {
            if icon.hasPrefix("custom:") {
                let path = String(icon.dropFirst(7))
                if let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                } else {
                    defaultPageIcon
                }
            } else if icon.hasPrefix("sf:") {
                Image(systemName: String(icon.dropFirst(3)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.system(size: 13))
            } else {
                defaultPageIcon
            }
        } else {
            defaultPageIcon
        }
    }

    private var defaultPageIcon: some View {
        Image(systemName: "doc.text")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}
