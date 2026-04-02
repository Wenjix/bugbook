import SwiftUI
import UniformTypeIdentifiers

struct WikiLinkView: View {
    let pageName: String
    let icon: String?
    var onNavigate: () -> Void
    var sidebarReferencePayload: SidebarReferenceDragPayload?

    var body: some View {
        if let sidebarReferencePayload {
            linkContent
                .onDrag {
                    let data = (try? JSONEncoder().encode(sidebarReferencePayload)) ?? Data()
                    return NSItemProvider(item: data as NSData, typeIdentifier: UTType.sidebarReference.identifier)
                }
        } else {
            linkContent
        }
    }

    private var linkContent: some View {
        HStack(spacing: 4) {
            iconView
            Text(pageName)
                .font(.system(size: EditorTypography.bodyFontSize))
                .foregroundStyle(.primary)
                .underline()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onNavigate)
        .appCursor(.pointingHand)
        .contextMenu {
            if let sidebarReferencePayload {
                Button {
                    NotificationCenter.default.post(name: .addToSidebar, object: sidebarReferencePayload)
                } label: {
                    Label("Add to Sidebar", systemImage: "sidebar.left")
                }
            }
        }
    }

    private var dragPreview: some View {
        SidebarDragPreview(systemImage: "doc.text", title: pageName)
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
