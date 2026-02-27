import SwiftUI
import AppKit

struct TabBarView: View {
    @ObservedObject var appState: AppState
    @State private var dragOverIndex: Int?
    @State private var draggingTabId: UUID?

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(appState.openTabs.enumerated()), id: \.element.id) { index, tab in
                        HStack(spacing: 0) {
                            // Drop indicator before this tab
                            if dragOverIndex == index {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: 2, height: 24)
                                    .padding(.vertical, 4)
                            }

                            TabItemView(
                                tab: tab,
                                isActive: index == appState.activeTabIndex,
                                onSelect: { appState.activeTabIndex = index },
                                onClose: { appState.closeTab(at: index) }
                            )
                            .opacity(draggingTabId == tab.id ? 0.4 : 1.0)
                            .onDrag {
                                draggingTabId = tab.id
                                return NSItemProvider(object: tab.path as NSString)
                            }
                            .onDrop(of: [.text], delegate: TabDropDelegate(
                                targetIndex: index,
                                appState: appState,
                                dragOverIndex: $dragOverIndex,
                                draggingTabId: $draggingTabId
                            ))
                        }
                    }

                    // Drop indicator after last tab
                    if dragOverIndex == appState.openTabs.count {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: 24)
                            .padding(.vertical, 4)
                    }

                    Button(action: { appState.newEmptyTab() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 2)
                    .onDrop(of: [.text], delegate: TabDropDelegate(
                        targetIndex: appState.openTabs.count,
                        appState: appState,
                        dragOverIndex: $dragOverIndex,
                        draggingTabId: $draggingTabId
                    ))
                }
                .padding(.leading, appState.sidebarOpen ? 2 : 88)
            }
            Spacer()
        }
        .frame(height: 36)
        .background(Color.fallbackSidebarBg)
    }
}

// MARK: - Tab Drop Delegate

struct TabDropDelegate: DropDelegate {
    let targetIndex: Int
    let appState: AppState
    @Binding var dragOverIndex: Int?
    @Binding var draggingTabId: UUID?

    func dropEntered(info: DropInfo) {
        dragOverIndex = targetIndex
    }

    func dropExited(info: DropInfo) {
        if dragOverIndex == targetIndex {
            dragOverIndex = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragOverIndex = nil
        guard let draggingId = draggingTabId,
              let sourceIndex = appState.openTabs.firstIndex(where: { $0.id == draggingId }) else {
            draggingTabId = nil
            return false
        }
        appState.reorderTab(from: sourceIndex, to: targetIndex)
        draggingTabId = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        true
    }
}

struct TabItemView: View {
    let tab: OpenFile
    let isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            tabIcon

            Text(tabName)
                .font(.system(size: 13))
                .lineLimit(1)

            if isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: isActive ? 36 : 28)
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

    @ViewBuilder
    private var tabIcon: some View {
        if tab.path == "__settings__" {
            Image(systemName: "gearshape").font(.system(size: 12))
        } else if tab.isDatabase {
            Image(systemName: "tablecells").font(.system(size: 12))
        } else if let icon = tab.icon, !icon.isEmpty {
            if icon.hasPrefix("sf:") {
                Image(systemName: String(icon.dropFirst(3)))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.system(size: 14))
            } else {
                Image(systemName: "doc.text").font(.system(size: 12))
            }
        } else {
            Image(systemName: "doc.text").font(.system(size: 12))
        }
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
