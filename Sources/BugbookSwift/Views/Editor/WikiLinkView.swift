import SwiftUI

struct WikiLinkView: View {
    let pageName: String
    let icon: String?
    var onNavigate: () -> Void

    var body: some View {
        Button(action: onNavigate) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Text(icon).font(.system(size: 12))
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
                Text(pageName)
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
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
}
