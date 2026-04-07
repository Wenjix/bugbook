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
        HStack(spacing: 0) {
            // Left: label area
            labelArea

            Spacer(minLength: 0)

            // Right: action buttons
            actionButtons
        }
        .frame(height: 28)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: leaf.id.uuidString as NSString)
        }
        .background(isReplaceWarning ? amberWarning.opacity(0.12) : Color.fallbackEditorBg)
        .overlay(alignment: .top) {
            if isReplaceWarning {
                Rectangle()
                    .fill(amberWarning)
                    .frame(height: 2)
            } else if isFocused {
                Rectangle()
                    .fill(steelBlue)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.04))
                .frame(height: 0.5)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .leading) {
            if isReplaceWarning {
                EmptyView()
            }
        }
        // Warning text overlay
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

    // MARK: - Label Area

    private var labelArea: some View {
        let info = chromeLabel
        let labelColor = isFocused && !isOnlyPane ? steelBlueLight : Color.primary.opacity(0.4)
        let mutedColor = Color.primary.opacity(0.2)

        return HStack(spacing: 0) {
            // Grip indicator (visible on hover)
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 4, height: 1)
                        .cornerRadius(0.5)
                }
            }
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .frame(width: 12)

            // Pane icon
            chromeIconView(info.icon)
                .foregroundStyle(labelColor)
                .frame(width: 14, height: 14)
                .padding(.trailing, 5)

            // Breadcrumb path or simple label
            if breadcrumbs.count > 1, let onNav = onBreadcrumbNavigate {
                // Show parent breadcrumbs (all except last) as clickable, then current page as label
                ForEach(breadcrumbs.dropLast()) { crumb in
                    Button {
                        onNav(crumb)
                    } label: {
                        Text(crumb.name)
                            .font(.system(size: 11))
                            .foregroundStyle(mutedColor)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(mutedColor)
                        .padding(.horizontal, 2)
                }
                // Current page (last breadcrumb)
                Text(breadcrumbs.last?.name ?? info.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
            } else {
                Text(info.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        let showButtons = isFocused || isHovered

        HStack(spacing: 2) {
            // Split — always visible on single pane, otherwise follows hover/focus
            if isOnlyPane || showButtons {
                Button { showSplitPopover.toggle() } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(buttonColor)
                        .frame(width: 26, height: 22)
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

            if !isOnlyPane && showButtons {
                // Pop out
                Button {
                    workspaceManager.popOutPane(id: leaf.id)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(buttonColor)
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PaneActionButtonStyle(isDestructive: false))
                .help("Pop out to tab")

                // Close
                Button {
                    workspaceManager.closePane(id: leaf.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(buttonColor)
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PaneActionButtonStyle(isDestructive: true))
                .help("Close pane")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showButtons)
    }

    private var buttonColor: Color {
        isFocused ? steelBlueLight : Color.primary.opacity(0.3)
    }

    // MARK: - Selection Handler

    private func handleSelection(content: PaneContent, direction: PaneLauncher.Direction) {
        switch direction {
        case .right:
            workspaceManager.setFocusedPane(id: leaf.id)
            _ = workspaceManager.splitFocusedPane(axis: .horizontal, newContent: content)
        case .down:
            workspaceManager.setFocusedPane(id: leaf.id)
            _ = workspaceManager.splitFocusedPane(axis: .vertical, newContent: content)
        case .newTab:
            workspaceManager.addWorkspaceWith(content: content)
        }
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

    // MARK: - Label Derivation

    private var chromeLabel: (icon: String, label: String, context: String?) {
        switch leaf.content {
        case .terminal:
            return ("terminal", "Terminal", nil)
        case .document(let file):
            if file.isEmptyTab { return ("doc", "New Tab", nil) }
            if file.isGateway { return ("house", "Home", nil) }
            if file.isMail { return ("envelope", "Mail", nil) }
            if file.isCalendar { return ("calendar.badge.clock", "Calendar", nil) }
            if file.isBrowser { return ("globe", "Browser", nil) }
            if file.isMeetings { return ("person.2", "Meetings", nil) }
            if file.isChat { return ("bubble.left.and.bubble.right", "Chat", nil) }
            if file.isGraphView { return ("point.3.connected.trianglepath.dotted", "Graph View", nil) }

            // Regular page/database/skill — derive from file metadata
            let name: String
            if let displayName = file.displayName, !displayName.isEmpty {
                name = displayName
            } else {
                let filename = (file.path as NSString).lastPathComponent
                name = filename.hasSuffix(".md") ? String(filename.dropLast(3)) : (filename.isEmpty ? "Untitled" : filename)
            }
            let icon = file.icon ?? (file.isDatabase ? "tablecells" : "doc.text")
            return (icon, name, nil)
        }
    }
}
