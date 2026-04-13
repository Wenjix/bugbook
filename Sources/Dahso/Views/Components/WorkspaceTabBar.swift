import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Tab bar at the top of the content area. Each tab owns a pane layout.
struct WorkspaceTabBar: View {
    var workspaceManager: WorkspaceManager
    var browserManager: BrowserManager
    var sidebarOpen: Bool
    var currentView: ViewMode = .editor
    var recordingPagePath: String?

    @State private var dragOverIndex: Int?
    @State private var draggedWorkspaceID: UUID?
    @State private var draggedWorkspaceOffset: CGSize = .zero
    @State private var workspaceTabFrames: [UUID: CGRect] = [:]
    @State private var showNewMenu = false
    @State private var showSavedIndicator = false
    @State private var savedIndicatorTask: Task<Void, Never>?

    private let detachThreshold: CGFloat = 90

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Sidebar toggle — only visible in tab bar when sidebar is closed
            if !sidebarOpen {
                Button {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(ShellZoomMetrics.font(13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: ShellZoomMetrics.size(30), height: ShellZoomMetrics.size(30))
                }
                .buttonStyle(.plain)
                .help("Toggle Sidebar")
                .padding(.leading, ShellZoomMetrics.size(70))
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

                // + button with content picker
                Button { showNewMenu = true } label: {
                    Image(systemName: "plus")
                        .font(ShellZoomMetrics.font(Typography.bodySmall))
                        .foregroundStyle(.secondary)
                        .frame(width: ShellZoomMetrics.size(28), height: ShellZoomMetrics.size(28))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, ShellZoomMetrics.size(8))
                .padding(.bottom, ShellZoomMetrics.size(2))
                .floatingPopover(isPresented: $showNewMenu) {
                    NewPanePopover(workspaceManager: workspaceManager, dismiss: { showNewMenu = false })
                        .popoverSurface()
                }
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
            switch leaf.content {
            case .document(let file):
                if let name = file.displayName, !name.isEmpty { return name }
                if file.isEmptyTab { return "New Tab" }
                if file.isBrowser {
                    if let host = URL(string: file.path)?.host, !host.isEmpty {
                        return host
                    }
                    return "Browser"
                }
                if file.isCalendar { return "Calendar" }
                if file.isMeetings { return "Meetings" }
                if file.isGraphView { return "Graph" }
                if file.isMail { return "Mail" }
                let fileName = (file.path as NSString).lastPathComponent
                return fileName.hasSuffix(".md") ? String(fileName.dropLast(3)) : fileName
            case .terminal:
                return "Terminal"
            }
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
        switch leaf.content {
        case .document(let file):
            if file.isGateway { return "sf:house" }
            if file.isMail { return "sf:envelope" }
            if file.isCalendar { return "sf:calendar" }
            if file.isBrowser { return "sf:globe" }
            if file.isMeetings { return "sf:waveform" }
            if file.isGraphView { return "sf:point.3.connected.trianglepath.dotted" }
            return file.icon
        case .terminal:
            return "sf:terminal"
        }
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
        Dictionary(uniqueKeysWithValues: workspace.allLeaves.compactMap { leaf in
            guard leaf.tabs.contains(where: { content in
                guard case .document(let file) = content else { return false }
                return file.isBrowser
            }),
                  let snapshot = browserManager.snapshot(for: leaf.id) else {
                return nil
            }
            return (leaf.id, snapshot)
        })
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

// MARK: - New Pane Popover

/// Fast content picker shown when clicking the + button.
private struct NewPanePopover: View {
    let workspaceManager: WorkspaceManager
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Tab")
                .font(.system(size: Typography.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            contentRow(icon: "doc.text", label: "Page") {
                workspaceManager.addWorkspace()
                dismiss()
            }
            contentRow(icon: "terminal", label: "Terminal") {
                workspaceManager.addWorkspaceWith(content: .terminal())
                dismiss()
            }
            contentRow(icon: "globe", label: "Browser") {
                workspaceManager.addWorkspaceWith(content: .browserDocument())
                dismiss()
            }
            contentRow(icon: "envelope", label: "Mail") {
                workspaceManager.addWorkspaceWith(content: .mailDocument())
                dismiss()
            }
            contentRow(icon: "calendar", label: "Calendar") {
                workspaceManager.addWorkspaceWith(content: .calendarDocument())
                dismiss()
            }
            contentRow(icon: "person.2", label: "Meetings") {
                workspaceManager.addWorkspaceWith(content: .meetingsDocument())
                dismiss()
            }
            contentRow(icon: "house", label: "Home") {
                workspaceManager.addWorkspaceWith(content: .gatewayDocument())
                dismiss()
            }

            Divider().padding(.vertical, 4)

            Text("Split Pane")
                .font(.system(size: Typography.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            contentRow(icon: "rectangle.split.2x1", label: "Split Right") {
                _ = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: .terminal())
                dismiss()
            }
            contentRow(icon: "rectangle.split.1x2", label: "Split Down") {
                _ = workspaceManager.splitFocusedPane(axis: .vertical, newContent: .terminal())
                dismiss()
            }
        }
        .padding(.bottom, 8)
        .frame(width: 180)
    }

    private func contentRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: Typography.caption))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: Typography.bodySmall))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .fill(isActive ? Container.pillActiveBg : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
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
        let w = rect.width
        let h = rect.height
        let cr = min(cornerRadius, h / 2, w / 2)
        let wr = min(wingRadius, h / 2)

        path.move(to: CGPoint(x: 0, y: h))
        path.addQuadCurve(to: CGPoint(x: wr, y: h - wr), control: CGPoint(x: wr, y: h))
        path.addLine(to: CGPoint(x: wr, y: cr))
        path.addQuadCurve(to: CGPoint(x: wr + cr, y: 0), control: CGPoint(x: wr, y: 0))
        path.addLine(to: CGPoint(x: w - wr - cr, y: 0))
        path.addQuadCurve(to: CGPoint(x: w - wr, y: cr), control: CGPoint(x: w - wr, y: 0))
        path.addLine(to: CGPoint(x: w - wr, y: h - wr))
        path.addQuadCurve(to: CGPoint(x: w, y: h), control: CGPoint(x: w - wr, y: h))

        return path
    }
}
