import SwiftUI
import AppKit

struct TabBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(appState.openTabs.enumerated()), id: \.element.id) { index, tab in
                        TabItemView(
                            tab: tab,
                            isActive: index == appState.activeTabIndex,
                            onSelect: { appState.activeTabIndex = index },
                            onClose: { appState.closeTab(at: index) }
                        )
                    }

                    Button(action: { appState.newEmptyTab() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 2)
                }
                .padding(.leading, 8)
            }
            Spacer()
        }
        .frame(height: 36)
        .background(Color.fallbackSidebarBg)
    }
}

struct TabItemView: View {
    let tab: OpenFile
    let isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if tab.path == "__settings__" {
                Image(systemName: "gearshape").font(.system(size: 11))
            } else if tab.isDatabase {
                Image(systemName: "tablecells").font(.system(size: 11))
            } else {
                Image(systemName: "doc.text").font(.system(size: 11))
            }

            Text(tabName)
                .font(.system(size: 12))
                .lineLimit(1)

            if isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: isActive ? 30 : 28)
        .background(
            Group {
                if isActive {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 8,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 8
                    )
                    .fill(Color.fallbackEditorBg)
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private var tabName: String {
        if tab.isEmptyTab { return "New tab" }
        if let displayName = tab.displayName { return displayName }
        let name = (tab.path as NSString).lastPathComponent
        return name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }
}

// MARK: - Window Drag Area

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowDragNSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class WindowDragNSView: NSView {
    override public var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
