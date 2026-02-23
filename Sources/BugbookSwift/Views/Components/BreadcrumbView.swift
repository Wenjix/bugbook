import SwiftUI

struct BreadcrumbView: View {
    let items: [BreadcrumbItem]
    var onNavigate: (BreadcrumbItem) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Button(action: { onNavigate(item) }) {
                    HStack(spacing: 3) {
                        if let icon = item.icon {
                            Text(icon).font(.system(size: 11))
                        }
                        Text(item.name)
                            .font(.system(size: 12))
                            .foregroundColor(index == items.count - 1 ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.fallbackBgSecondary)
    }
}
