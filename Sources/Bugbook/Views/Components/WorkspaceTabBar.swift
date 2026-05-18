import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Tab bar at the top of the content area. Each tab owns a pane layout.
struct WorkspaceTabBar: View {
    var workspaceManager: WorkspaceManager
    var browserManager: BrowserManager?
    var sidebarOpen: Bool
    var currentView: ViewMode = .editor
    var recordingPagePath: String?
    var onOpenNewTabLauncher: () -> Void = {}

    @State private var dragOverIndex: Int?
    @State private var draggedWorkspaceID: UUID?
    @State private var draggedWorkspaceOffset: CGSize = .zero
    @State private var workspaceTabFrames: [UUID: CGRect] = [:]
    @State private var showSavedIndicator = false
    @State private var savedIndicatorTask: Task<Void, Never>?
    @State private var isAddWorkspaceHovered = false

    private let detachThreshold: CGFloat = 90

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Sidebar toggle — only in the tab bar when the sidebar is closed.
            // When open, the toggle lives in the sidebar's own top band.
            if !sidebarOpen {
                SidebarToggleButton()
                    .padding(.leading, ShellZoomMetrics.size(78))
                    .padding(.trailing, ShellZoomMetrics.size(4))
                    .padding(.bottom, ShellZoomMetrics.size(2))
            }

            HStack(alignment: .bottom, spacing: -ShellZoomMetrics.size(8)) {
                ForEach(Array(workspaceManager.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    HStack(spacing: 0) {
                        if dragOverIndex == index {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: 2, height: ShellZoomMetrics.size(24))
                                .padding(.vertical, ShellZoomMetrics.size(4))
                        }

                        TabItemView(
                            title: tabTitle(for: workspace),
                            icon: tabIcon(for: workspace),
                            isActive: index == workspaceManager.activeWorkspaceIndex,
                            isRecording: isWorkspaceRecording(workspace),
                            onSelect: { workspaceManager.switchWorkspace(to: index) },
                            onClose: { workspaceManager.closeWorkspace(at: index) },
                            onMoveToNewWindow: {
                                detachWorkspace(id: workspace.id)
                            }
                        )
                        .zIndex(index == workspaceManager.activeWorkspaceIndex ? 1 : 0)
                        .opacity(draggedWorkspaceID == workspace.id ? 0.55 : 1.0)
                        .offset(draggedWorkspaceID == workspace.id ? draggedWorkspaceOffset : .zero)
                        .background(workspaceTabFrameReader(for: workspace.id))
                        .gesture(
                            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                .onChanged { value in
                                    handleWorkspaceDragChanged(
                                        workspaceID: workspace.id,
                                        location: value.location,
                                        translation: value.translation
                                    )
                                }
                                .onEnded { value in
                                    handleWorkspaceDragEnded(
                                        workspaceID: workspace.id,
                                        location: value.location,
                                        translation: value.translation
                                    )
                                }
                        )
                    }
                }

                if dragOverIndex == workspaceManager.workspaces.count {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: ShellZoomMetrics.size(24))
                        .padding(.vertical, ShellZoomMetrics.size(4))
                }

                Button { onOpenNewTabLauncher() } label: {
                    Image(systemName: "plus")
                        .font(ShellZoomMetrics.font(Typography.bodySmall))
                        .foregroundStyle(addWorkspaceForeground)
                        .frame(width: ShellZoomMetrics.size(28), height: ShellZoomMetrics.size(28))
                        .background(
                            RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.sm))
                                .fill(addWorkspaceBackground)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, ShellZoomMetrics.size(8))
                .padding(.bottom, ShellZoomMetrics.size(2))
                .help("Open in new workspace")
                .onHover { isAddWorkspaceHovered = $0 }
            }
            .padding(.leading, 0)
            Spacer(minLength: 0)
            layoutSavedIndicator
        }
        .frame(height: ShellZoomMetrics.size(36))
        .background(Container.groutBg)
        .onChange(of: workspaceManager.lastSavedAt) { _, _ in
            savedIndicatorTask?.cancel()
            withAnimation(.easeIn(duration: 0.15)) { showSavedIndicator = true }
            savedIndicatorTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { showSavedIndicator = false }
            }
        }
        .onPreferenceChange(WorkspaceTabFramePreferenceKey.self) { workspaceTabFrames = $0 }
    }

    private var addWorkspaceForeground: Color {
        if isAddWorkspaceHovered {
            return Color.primary.opacity(0.72)
        }
        return Color.secondary
    }

    private var addWorkspaceBackground: Color {
        if isAddWorkspaceHovered {
            return Color.primary.opacity(0.08)
        }
        return Color.clear
    }

    @ViewBuilder
    private var layoutSavedIndicator: some View {
        if showSavedIndicator {
            Text("Saved")
                .font(.system(size: Typography.caption2))
                .foregroundStyle(.tertiary)
                .padding(.trailing, ShellZoomMetrics.size(12))
                .transition(.opacity)
        }
    }

    private func tabTitle(for ws: Workspace) -> String {
        // Override for full-page views
        if ws.id == workspaceManager.activeWorkspace?.id {
            if currentView == .chat { return "Chat" }
            if currentView == .graphView { return "Graph" }
            if currentView == .calendar { return "Calendar" }
        }
        // In splits, prefer the first document pane over terminal for the tab title
        let leaf = ws.root.firstDocumentLeaf ?? ws.focusedLeaf
        if let leaf {
            return leaf.content.paneItemTitle
        }
        return ws.name
    }

    private func isWorkspaceRecording(_ ws: Workspace) -> Bool {
        guard let path = recordingPagePath else { return false }
        guard let leaf = ws.focusedLeaf else { return false }
        if case .document(let file) = leaf.content {
            return file.path == path
        }
        return false
    }

    private func tabIcon(for ws: Workspace) -> String? {
        if ws.id == workspaceManager.activeWorkspace?.id {
            if currentView == .chat { return "sf:bubble.left.and.bubble.right" }
            if currentView == .graphView { return "sf:point.3.connected.trianglepath.dotted" }
            if currentView == .calendar { return "sf:calendar" }
        }
        guard let leaf = ws.focusedLeaf else { return nil }
        return leaf.content.paneItemIcon
    }

    private func workspaceTabFrameReader(for workspaceID: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: WorkspaceTabFramePreferenceKey.self,
                    value: [workspaceID: proxy.frame(in: .global)]
                )
        }
    }

    private func handleWorkspaceDragChanged(
        workspaceID: UUID,
        location: CGPoint,
        translation: CGSize
    ) {
        draggedWorkspaceID = workspaceID
        draggedWorkspaceOffset = translation

        guard abs(translation.height) < detachThreshold else {
            dragOverIndex = nil
            return
        }

        dragOverIndex = insertionIndex(for: location)
    }

    private func handleWorkspaceDragEnded(
        workspaceID: UUID,
        location: CGPoint,
        translation: CGSize
    ) {
        defer { resetWorkspaceDragState() }

        guard let sourceIndex = workspaceManager.workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return
        }

        if abs(translation.height) >= detachThreshold {
            detachWorkspace(id: workspaceID)
            return
        }

        guard let targetIndex = insertionIndex(for: location) else { return }
        workspaceManager.reorderWorkspace(from: sourceIndex, to: targetIndex)
    }

    private func detachWorkspace(id: UUID) {
        guard let index = workspaceManager.workspaces.firstIndex(where: { $0.id == id }),
              let workspace = workspaceManager.detachWorkspace(at: index) else {
            return
        }

        let title = tabTitle(for: workspace)
        let browserSnapshots = detachedBrowserSnapshots(for: workspace)
        let bootstrap = ContentViewBootstrap(
            workspaces: [workspace],
            activeWorkspaceIndex: 0,
            browserSnapshots: browserSnapshots,
            layoutPersistenceEnabled: false
        )
        DetachedWindowManager.shared.openWindow(title: title, bootstrap: bootstrap)
    }

    private func detachedBrowserSnapshots(for workspace: Workspace) -> [UUID: BrowserPaneSnapshot] {
        guard let browserManager else { return [:] }
        let snapshots: [(UUID, BrowserPaneSnapshot)] = workspace.allLeaves.compactMap { leaf -> (UUID, BrowserPaneSnapshot)? in
            guard leaf.tabs.contains(where: { content in
                guard case .document(let file) = content else { return false }
                return file.isBrowser
            }),
                  let snapshot = browserManager.snapshot(for: leaf.id) else {
                return nil
            }
            return (leaf.id, snapshot)
        }
        return Dictionary(uniqueKeysWithValues: snapshots)
    }

    private func insertionIndex(for location: CGPoint) -> Int? {
        let orderedFrames = workspaceManager.workspaces.compactMap { workspace in
            workspaceTabFrames[workspace.id].map { (workspace.id, $0) }
        }
        .sorted { $0.1.minX < $1.1.minX }

        guard !orderedFrames.isEmpty else { return nil }

        for (index, frame) in orderedFrames.enumerated() where location.x < frame.1.midX {
            return index
        }

        return orderedFrames.count
    }

    private func resetWorkspaceDragState() {
        dragOverIndex = nil
        draggedWorkspaceID = nil
        draggedWorkspaceOffset = .zero
    }
}

// MARK: - Tab Item

private struct TabItemView: View {
    let title: String
    var icon: String?
    let isActive: Bool
    var isRecording: Bool = false
    var onSelect: () -> Void
    var onClose: () -> Void
    var onMoveToNewWindow: () -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ShellZoomMetrics.size(6)) {
                if isRecording {
                    PulsingRecordDot()
                        .scaleEffect(0.75)
                } else {
                    tabIconView
                }

                Text(title)
                    .font(ShellZoomMetrics.font(Typography.bodySmall, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : Container.pillInactiveText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(ShellZoomMetrics.font(9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: ShellZoomMetrics.size(18), height: ShellZoomMetrics.size(18))
                        .background(isCloseHovered ? Color.primary.opacity(0.1) : .clear)
                        .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.xs)))
                }
                .buttonStyle(.plain)
                .onHover { isCloseHovered = $0 }
                .opacity(isHovered ? 1 : 0)
            }
            .padding(.leading, ShellZoomMetrics.size(12))
            .padding(.trailing, ShellZoomMetrics.size(8))
            .frame(minWidth: ShellZoomMetrics.size(60), maxWidth: ShellZoomMetrics.size(180), alignment: .leading)
            .frame(height: ShellZoomMetrics.size(28))
            .background(
                RoundedRectangle(cornerRadius: Container.pillRadius)
                    .fill(tabBackground)
            )
            .padding(.horizontal, ShellZoomMetrics.size(2))
            .contentShape(RoundedRectangle(cornerRadius: Container.pillRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Move to New Window") {
                onMoveToNewWindow()
            }
        }
    }

    private var tabBackground: Color {
        if isActive {
            return Container.pillActiveBg
        }
        if isHovered {
            return Color.primary.opacity(0.04)
        }
        return Color.clear
    }

    @ViewBuilder
    private var tabIconView: some View {
        if let icon, !icon.isEmpty {
            if icon.hasPrefix("sf:") {
                Image(systemName: String(icon.dropFirst(3)))
                    .font(ShellZoomMetrics.font(Typography.caption))
                    .foregroundStyle(.secondary)
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(ShellZoomMetrics.font(14))
            }
        }
    }
}

private struct WorkspaceTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Connected Tab Shape

struct ConnectedTabShape: Shape {
    let cornerRadius: CGFloat
    let wingRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let tabCornerRadius = min(cornerRadius, height / 2, width / 2)
        let tabWingRadius = min(wingRadius, height / 2)

        path.move(to: CGPoint(x: 0, y: height))
        path.addQuadCurve(
            to: CGPoint(x: tabWingRadius, y: height - tabWingRadius),
            control: CGPoint(x: tabWingRadius, y: height)
        )
        path.addLine(to: CGPoint(x: tabWingRadius, y: tabCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: tabWingRadius + tabCornerRadius, y: 0),
            control: CGPoint(x: tabWingRadius, y: 0)
        )
        path.addLine(to: CGPoint(x: width - tabWingRadius - tabCornerRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: width - tabWingRadius, y: tabCornerRadius),
            control: CGPoint(x: width - tabWingRadius, y: 0)
        )
        path.addLine(to: CGPoint(x: width - tabWingRadius, y: height - tabWingRadius))
        path.addQuadCurve(
            to: CGPoint(x: width, y: height),
            control: CGPoint(x: width - tabWingRadius, y: height)
        )

        return path
    }
}
