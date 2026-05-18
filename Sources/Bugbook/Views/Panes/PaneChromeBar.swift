import Foundation
import SwiftUI

/// Compact pane header bar shown for tiled panes and browser single-pane mode.
/// Focus state is driven by WorkspaceManager — only this view and PaneFocusOverlay
/// respond to focus changes rather than re-rendering the entire pane tree.
struct PaneChromeBar: View {
    let leaf: PaneNode.Leaf
    let workspaceManager: WorkspaceManager
    let isOnlyPane: Bool
    let fileTree: [FileEntry]
    var breadcrumbs: [BreadcrumbItem] = []
    var onBreadcrumbNavigate: ((BreadcrumbItem) -> Void)? = nil
    let paneActions: PaneActions

    @State private var isHovered = false
    @State private var showSplitPopover = false
    @Environment(\.paneReplaceWarningId) private var replaceWarningId

    // Steel blue accent for focused state
    private let steelBlue = Color(red: 0.357, green: 0.596, blue: 0.722)
    private let steelBlueLight = Color(red: 0.561, green: 0.741, blue: 0.831)
    private let amberWarning = Color(red: 0.9, green: 0.65, blue: 0.2)

    private var isFocused: Bool {
        workspaceManager.activeWorkspace?.focusedPaneId == leaf.id
    }

    private var isReplaceWarning: Bool {
        replaceWarningId == leaf.id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                dragHandleArea

                Spacer(minLength: 0)

                actionButtons
            }
            .frame(height: 20)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onDrag {
                NSItemProvider(object: leaf.id.uuidString as NSString)
            }

            if leaf.hasMultipleTabs {
                tabStrip
            }
        }
        .background(isReplaceWarning ? amberWarning.opacity(0.12) : Container.cardBg)
        .overlay(alignment: .top) {
            if isReplaceWarning {
                Rectangle()
                    .fill(amberWarning)
                    .frame(height: 2)
            } else if isFocused && !isOnlyPane {
                Rectangle()
                    .fill(steelBlue)
                    .frame(height: 2)
            }
        }
        .overlay {
            if isReplaceWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("Terminal is running. Click again to replace.")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(amberWarning)
                .transition(.opacity)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.2), value: isReplaceWarning)
    }

    // MARK: - Pane Controls

    private var dragHandleArea: some View {
        // Pane identity belongs to the tab strip and the content surface. This row is
        // intentionally just pane chrome: drag affordance plus controls.
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .fill((isFocused ? steelBlue : Color.primary).opacity(0.25))
                    .frame(width: 5, height: 1)
                    .cornerRadius(0.5)
            }
        }
        .opacity(isHovered || isFocused ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .frame(width: 16, height: 18)
        .accessibilityHidden(true)
        .help("Drag pane")
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(leaf.tabs.enumerated()), id: \.element.id) { index, content in
                    paneTabPill(content: content, isSelected: index == leaf.selectedTabIndex)
                }

                if leaf.activeContent.defaultNewPaneTab() != nil {
                    Button {
                        paneActions.createPaneTab(leaf)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(Color.fallbackTabBarBg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.fallbackChromeBorder)
                .frame(height: 1)
        }
    }

    private func paneTabPill(content: PaneContent, isSelected: Bool) -> some View {
        let selectedFill = isFocused ? steelBlue.opacity(0.12) : Color.primary.opacity(0.08)
        let selectedStroke = isFocused ? steelBlue.opacity(0.45) : Color.primary.opacity(0.1)
        let selectedForeground = isFocused ? steelBlue : Color.primary

        return HStack(spacing: 4) {
            Button {
                workspaceManager.selectPaneTab(paneId: leaf.id, tabId: content.id)
            } label: {
                HStack(spacing: 5) {
                    chromeIconView(content.paneItemIcon)
                        .frame(width: 11, height: 11)
                    Text(content.paneItemTitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? selectedForeground : Color.primary.opacity(0.65))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if leaf.tabs.count > 1 {
                Button {
                    paneActions.closePaneTab(leaf, content.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 5)
            }
        }
        .frame(minWidth: 96, maxWidth: 168)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? selectedFill : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? selectedStroke : Color.clear, lineWidth: 0.5)
        )
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 2) {
            splitButton
            moreMenuButton
            closePaneButton
        }
        .opacity(controlOpacity)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var splitButton: some View {
        Button { showSplitPopover.toggle() } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(buttonColor)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(PaneActionButtonStyle(isDestructive: false))
        .help("Split pane")
        .floatingPopover(isPresented: $showSplitPopover, arrowEdge: .top) {
            PaneLauncher(
                variant: .compact,
                fileTree: fileTree,
                onSelect: { content, direction in
                    showSplitPopover = false
                    handleSelection(content: content, direction: direction)
                },
                onDismiss: { showSplitPopover = false }
            )
            .popoverSurface()
        }
    }

    private var moreMenuButton: some View {
        Menu {
            Button("Split Right") {
                splitPane(axis: .horizontal, content: .emptyDocument())
            }
            Button("Split Down") {
                splitPane(axis: .vertical, content: .emptyDocument())
            }
            Divider()
            Button("Unsplit") {
                paneActions.closeOtherPanes(leaf)
            }
            Button("Close Other Panes") {
                paneActions.closeOtherPanes(leaf)
            }
            if !isOnlyPane {
                Button("Pop Out to Workspace") {
                    workspaceManager.popOutPane(id: leaf.id)
                }
            }
            Divider()
            Button("Close Pane", role: .destructive) {
                paneActions.closePane(leaf)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(buttonColor)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Pane actions")
    }

    private var closePaneButton: some View {
        Button {
            paneActions.closePane(leaf)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(buttonColor)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(PaneActionButtonStyle(isDestructive: true))
        .help("Close pane")
    }

    private var buttonColor: Color {
        if isFocused {
            return steelBlueLight
        }
        return Color.primary.opacity(isHovered ? 0.55 : 0.32)
    }

    private var controlOpacity: Double {
        if isFocused { return 1.0 }
        if isHovered { return 0.72 }
        return 0.34
    }

    // MARK: - Selection Handler

    private func handleSelection(content: PaneContent, direction: PaneLauncher.Direction) {
        guard BugbookFeatureGate.allowsPaneContent(content) else { return }
        switch direction {
        case .right:
            splitPane(axis: .horizontal, content: content)
        case .down:
            splitPane(axis: .vertical, content: content)
        case .newTab:
            workspaceManager.addWorkspaceWith(content: content)
        }
    }

    private func splitPane(axis: PaneNode.Split.Axis, content: PaneContent) {
        guard BugbookFeatureGate.allowsPaneContent(content) else { return }
        workspaceManager.setFocusedPane(id: leaf.id)
        _ = workspaceManager.splitFocusedPane(axis: axis, newContent: content)
    }

    // MARK: - Icon Rendering

    @ViewBuilder
    private func chromeIconView(_ icon: String) -> some View {
        if icon.hasPrefix("sf:") {
            Image(systemName: String(icon.dropFirst(3)))
                .font(.system(size: 12))
        } else if icon.unicodeScalars.first?.properties.isEmoji == true {
            Text(icon).font(.system(size: 11))
        } else {
            Image(systemName: icon)
                .font(.system(size: 12))
        }
    }

}
