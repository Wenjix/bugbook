import SwiftUI
import AppKit

struct TabBarView: View {
    var appState: AppState
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    @State private var dragOverIndex: Int?
    @State private var draggingTabId: UUID?

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Back / Forward buttons
            HStack(spacing: ShellZoomMetrics.size(2)) {
                navButton(icon: "chevron.left", help: "Back", isEnabled: canGoBack) { onBack?() }
                navButton(icon: "chevron.right", help: "Forward", isEnabled: canGoForward) { onForward?() }
            }
            .padding(.leading, appState.sidebarOpen ? ShellZoomMetrics.size(8) : ShellZoomMetrics.size(112))
            .padding(.bottom, ShellZoomMetrics.size(3))

            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: -ShellZoomMetrics.size(8)) {
                    ForEach(Array(appState.openTabs.enumerated()), id: \.element.id) { index, tab in
                        HStack(spacing: 0) {
                            if dragOverIndex == index {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: 2, height: ShellZoomMetrics.size(24))
                                    .padding(.vertical, ShellZoomMetrics.size(4))
                            }

                            TabItemView(
                                tab: tab,
                                isActive: index == appState.activeTabIndex,
                                onSelect: { appState.activeTabIndex = index },
                                onClose: { appState.closeTab(at: index) }
                            )
                            .zIndex(index == appState.activeTabIndex ? 1 : 0)
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

                    if dragOverIndex == appState.openTabs.count {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: ShellZoomMetrics.size(24))
                            .padding(.vertical, ShellZoomMetrics.size(4))
                    }

                    Button("New Tab", systemImage: "plus", action: { appState.newEmptyTab() })
                        .labelStyle(.iconOnly)
                        .font(ShellZoomMetrics.font(Typography.bodySmall))
                        .foregroundStyle(.secondary)
                        .frame(width: ShellZoomMetrics.size(28), height: ShellZoomMetrics.size(28))
                        .buttonStyle(.plain)
                    .padding(.leading, ShellZoomMetrics.size(8))
                    .padding(.bottom, ShellZoomMetrics.size(2))
                    .onDrop(of: [.text], delegate: TabDropDelegate(
                        targetIndex: appState.openTabs.count,
                        appState: appState,
                        dragOverIndex: $dragOverIndex,
                        draggingTabId: $draggingTabId
                    ))
                }
                .padding(.leading, ShellZoomMetrics.size(2))
            }
            .scrollIndicators(.hidden)
            Spacer()
        }
        .padding(.top, ShellZoomMetrics.size(6))
        .frame(height: ShellZoomMetrics.size(36))
        .background(
            ZStack(alignment: .bottom) {
                Color.fallbackTabBarBg
                Rectangle()
                    .fill(Color.fallbackChromeBorder)
                    .frame(height: 1)
            }
        )
    }

    private func navButton(icon: String, help: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(ShellZoomMetrics.font(Typography.caption, weight: .medium))
                .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.35))
                .frame(width: ShellZoomMetrics.size(24), height: ShellZoomMetrics.size(24))
        }
        .buttonStyle(.borderless)
        .help(help)
        .disabled(!isEnabled)
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

    @State private var isHovered = false
    @State private var isCloseHovered = false
    private var wingRadius: CGFloat { ShellZoomMetrics.size(5) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ShellZoomMetrics.size(6)) {
                tabIcon

                Text(tabName)
                    .font(ShellZoomMetrics.font(Typography.bodySmall))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(ShellZoomMetrics.font(9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: ShellZoomMetrics.size(20), height: ShellZoomMetrics.size(20))
                        .background(isCloseHovered ? Color.primary.opacity(0.1) : .clear)
                        .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.xs)))
                }
                .buttonStyle(.plain)
                .onHover { isCloseHovered = $0 }
                .opacity(isHovered ? 1 : 0)
            }
            .padding(.leading, ShellZoomMetrics.size(14))
            .padding(.trailing, ShellZoomMetrics.size(8))
            .frame(width: ShellZoomMetrics.size(190), alignment: .leading)
            .frame(height: ShellZoomMetrics.size(30))
            .background(
                Group {
                    if isActive {
                        ZStack(alignment: .bottom) {
                            ConnectedTabShape(
                                cornerRadius: ShellZoomMetrics.size(Radius.sm),
                                wingRadius: wingRadius
                            )
                                .fill(Color.fallbackEditorBg)
                            ConnectedTabShape(
                                cornerRadius: ShellZoomMetrics.size(Radius.sm),
                                wingRadius: wingRadius
                            )
                                .stroke(Color.fallbackChromeBorder, lineWidth: 1)
                        }
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                            .fill(Color.primary.opacity(0.05))
                    } else {
                        Color.clear
                    }
                }
            )
            .padding(.horizontal, ShellZoomMetrics.size(4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var tabIcon: some View {
        if tab.path == "__settings__" {
            Image(systemName: "gearshape").font(ShellZoomMetrics.font(Typography.caption))
        } else if let icon = tab.icon, !icon.isEmpty {
            if icon.hasPrefix("sf:") {
                Image(systemName: String(icon.dropFirst(3)))
                    .font(ShellZoomMetrics.font(Typography.caption))
                    .foregroundStyle(.secondary)
            } else if icon.hasPrefix("custom:") {
                let path = String(icon.dropFirst(7))
                if let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: ShellZoomMetrics.size(14), height: ShellZoomMetrics.size(14))
                        .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(3)))
                }
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(ShellZoomMetrics.font(14))
            }
        }
    }

    private var tabName: String {
        if tab.isEmptyTab { return "New tab" }
        if let displayName = tab.displayName { return displayName }
        let name = (tab.path as NSString).lastPathComponent
        return name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }
}

// MARK: - Connected Tab Shape

/// A tab shape with rounded top corners and inverse-radius "wings" at the bottom
/// that curve into the page, like browser/Notion tabs.
struct ConnectedTabShape: Shape {
    let cornerRadius: CGFloat
    let wingRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cr = min(cornerRadius, h / 2, w / 2)
        let wr = min(wingRadius, h / 2)

        // Start at bottom-left wing
        path.move(to: CGPoint(x: 0, y: h))
        // Wing curve: from (0, h) curving up to (wr, h - wr)
        path.addQuadCurve(
            to: CGPoint(x: wr, y: h - wr),
            control: CGPoint(x: wr, y: h)
        )
        // Left edge up to top-left corner
        path.addLine(to: CGPoint(x: wr, y: cr))
        // Top-left corner
        path.addQuadCurve(
            to: CGPoint(x: wr + cr, y: 0),
            control: CGPoint(x: wr, y: 0)
        )
        // Top edge
        path.addLine(to: CGPoint(x: w - wr - cr, y: 0))
        // Top-right corner
        path.addQuadCurve(
            to: CGPoint(x: w - wr, y: cr),
            control: CGPoint(x: w - wr, y: 0)
        )
        // Right edge down
        path.addLine(to: CGPoint(x: w - wr, y: h - wr))
        // Right wing curve
        path.addQuadCurve(
            to: CGPoint(x: w, y: h),
            control: CGPoint(x: w - wr, y: h)
        )

        return path
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
