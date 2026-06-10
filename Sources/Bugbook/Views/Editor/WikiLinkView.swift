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
            Image(systemName: "arrow.up.right")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.6))
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

    private var iconView: some View {
        PageIconView(icon: icon) {
            defaultPageIcon
        }
        .foregroundStyle(.secondary)
    }

    private var defaultPageIcon: some View {
        Image(systemName: "doc.text")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}
