import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Workspace-level tab bar. Each tab represents a workspace (owns a pane tree).
/// Replaces TabBarView for the pane system.
struct WorkspaceTabBar: View {
    var workspaceManager: WorkspaceManager
    var sidebarOpen: Bool

    @State private var dragOverIndex: Int?
    @State private var draggingWorkspaceId: UUID?

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: -ShellZoomMetrics.size(8)) {
                    ForEach(Array(workspaceManager.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        HStack(spacing: 0) {
                            if dragOverIndex == index {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: 2, height: ShellZoomMetrics.size(24))
                                    .padding(.vertical, ShellZoomMetrics.size(4))
                            }

                            WorkspaceTabItemView(
                                workspace: workspace,
                                isActive: index == workspaceManager.activeWorkspaceIndex,
                                onSelect: { workspaceManager.switchWorkspace(to: index) },
                                onClose: { workspaceManager.closeWorkspace(at: index) }
                            )
                            .zIndex(index == workspaceManager.activeWorkspaceIndex ? 1 : 0)
                            .opacity(draggingWorkspaceId == workspace.id ? 0.4 : 1.0)
                            .onDrag {
                                draggingWorkspaceId = workspace.id
                                return NSItemProvider(object: workspace.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: WorkspaceTabDropDelegate(
                                targetIndex: index,
                                workspaceManager: workspaceManager,
                                dragOverIndex: $dragOverIndex,
                                draggingId: $draggingWorkspaceId
                            ))
                        }
                    }

                    if dragOverIndex == workspaceManager.workspaces.count {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: ShellZoomMetrics.size(24))
                            .padding(.vertical, ShellZoomMetrics.size(4))
                    }

                    Button("New Workspace", systemImage: "plus", action: { workspaceManager.addWorkspace() })
                        .labelStyle(.iconOnly)
                        .font(ShellZoomMetrics.font(Typography.bodySmall))
                        .foregroundStyle(.secondary)
                        .frame(width: ShellZoomMetrics.size(28), height: ShellZoomMetrics.size(28))
                        .buttonStyle(.plain)
                        .padding(.leading, ShellZoomMetrics.size(8))
                        .padding(.bottom, ShellZoomMetrics.size(2))
                        .onDrop(of: [.text], delegate: WorkspaceTabDropDelegate(
                            targetIndex: workspaceManager.workspaces.count,
                            workspaceManager: workspaceManager,
                            dragOverIndex: $dragOverIndex,
                            draggingId: $draggingWorkspaceId
                        ))
                }
                .padding(.leading, ShellZoomMetrics.size(2))
            }
            .scrollIndicators(.hidden)
            .padding(.leading, sidebarOpen ? ShellZoomMetrics.size(8) : ShellZoomMetrics.size(112))
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
}

// MARK: - Workspace Tab Item

struct WorkspaceTabItemView: View {
    let workspace: Workspace
    let isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false
    private var wingRadius: CGFloat { ShellZoomMetrics.size(5) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ShellZoomMetrics.size(6)) {
                if let icon = workspace.icon, !icon.isEmpty {
                    Text(icon).font(ShellZoomMetrics.font(14))
                }

                Text(workspace.name)
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
}

// MARK: - Workspace Tab Drop Delegate

struct WorkspaceTabDropDelegate: DropDelegate {
    let targetIndex: Int
    let workspaceManager: WorkspaceManager
    @Binding var dragOverIndex: Int?
    @Binding var draggingId: UUID?

    func dropEntered(info: DropInfo) { dragOverIndex = targetIndex }

    func dropExited(info: DropInfo) {
        if dragOverIndex == targetIndex { dragOverIndex = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragOverIndex = nil
        guard let draggingId,
              let sourceIndex = workspaceManager.workspaces.firstIndex(where: { $0.id == draggingId }) else {
            self.draggingId = nil
            return false
        }
        guard sourceIndex != targetIndex else {
            self.draggingId = nil
            return true
        }

        workspaceManager.reorderWorkspace(from: sourceIndex, to: targetIndex)

        self.draggingId = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool { true }
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
