import SwiftUI

struct WikiLinkView: View {
    let pageName: String
    let icon: String?
    var onNavigate: () -> Void

    var body: some View {
        Button(action: onNavigate) {
            HStack(spacing: 4) {
                iconView
                Text(pageName)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .underline()
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
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
            .foregroundColor(.secondary)
    }
}
