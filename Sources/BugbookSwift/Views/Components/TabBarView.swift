import SwiftUI

struct TabBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(appState.openTabs.enumerated()), id: \.element.id) { index, tab in
                    TabItemView(
                        tab: tab,
                        isActive: index == appState.activeTabIndex,
                        onSelect: { appState.activeTabIndex = index },
                        onClose: { appState.closeTab(at: index) }
                    )
                }

                // New tab button
                Button(action: { appState.newEmptyTab() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 34)
        .background(Color.fallbackBgSecondary)
    }
}

struct TabItemView: View {
    let tab: OpenFile
    let isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if tab.isDatabase {
                Image(systemName: "tablecells").font(.system(size: 10))
            } else {
                Image(systemName: "doc.text").font(.system(size: 10))
            }

            Text(tabName)
                .font(.system(size: 12))
                .lineLimit(1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.fallbackBgPrimary : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private var tabName: String {
        if tab.isEmptyTab { return "Local-first notes for agents and humans" }
        if let displayName = tab.displayName { return displayName }
        let name = (tab.path as NSString).lastPathComponent
        return name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }
}
