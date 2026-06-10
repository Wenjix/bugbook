import SwiftUI
import ImageIO
import os

struct FileTreeItemView: View {
    let entry: FileEntry
    let activeFilePath: String?
    var fileSystem: FileSystemService
    var workspacePath: String?
    var onSelectFile: (FileEntry) -> Void
    var onRefreshTree: () -> Void
    var isSidebarReference: Bool = false
    var showsParentPath: Bool = false
    @Binding var expandedFolders: Set<String>
    var parentPath: String = ""

    private var isExpanded: Bool { expandedFolders.contains(entry.path) }
    @State private var isHovering: Bool = false
    @State private var isRenaming: Bool = false
    @State private var renameName: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var showContextMenu: Bool = false
    @State private var hoveredMenuItem: String?
    @State private var cachedIconImage: NSImage?

    private static let expandedFoldersKey = "expandedFolders"

    var body: some View {
        VStack(spacing: 0) {
            // Row
            if isSidebarReference {
                rowButton
            } else {
                rowButton
                    .onNSRightClick { showContextMenu = true }
                    .floatingPopover(isPresented: $showContextMenu) {
                        sidebarContextMenu
                    }
            }

            // Children (if expanded)
            if !isSidebarReference, isExpanded, let children = entry.children {
                let childParentPath = entry.name.hasSuffix(".md") && !entry.isDirectory
                    ? String(entry.path.dropLast(3))  // companion folder path
                    : entry.path
                FileTreeView(
                    entries: children,
                    activeFilePath: activeFilePath,
                    fileSystem: fileSystem,
                    workspacePath: workspacePath,
                    parentPath: childParentPath,
                    onSelectFile: onSelectFile,
                    onRefreshTree: onRefreshTree,
                    expandedFolders: $expandedFolders
                )
                .padding(.leading, ShellZoomMetrics.size(12))
            }
        }
        .task(id: entry.icon) { await loadIconImage() }
        .alert("Delete \"\(displayName)\"?", isPresented: $showDeleteConfirmation) {
            Button("Move to Trash", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This page will be moved to Recently Deleted.")
        }
    }

    @ViewBuilder
    private var rowButton: some View {
        Button(action: { handleTap() }) {
            HStack(spacing: ShellZoomMetrics.size(6)) {
                // Icon slot: ZStack keeps layout stable during hover transitions
                ZStack {
                    iconView
                        .opacity(isExpandable && isHovering ? 0 : 1)

                    if isExpandable {
                        Button(action: toggleExpanded) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(ShellZoomMetrics.font(Typography.caption2))
                                .foregroundStyle(.secondary)
                                .frame(width: ShellZoomMetrics.size(16), height: ShellZoomMetrics.size(16))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovering ? 1 : 0)
                    }
                }
                .frame(width: ShellZoomMetrics.size(16), height: ShellZoomMetrics.size(16))

                if isRenaming {
                    TextField("", text: $renameName, onCommit: { commitRename() })
                        .textFieldStyle(.plain)
                        .font(ShellZoomMetrics.font(Typography.body))
                        .onExitCommand { isRenaming = false }
                } else {
                    VStack(alignment: .leading, spacing: ShellZoomMetrics.size(1)) {
                        Text(displayName)
                            .font(ShellZoomMetrics.font(Typography.body))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let parentPathLabel {
                            Text(parentPathLabel)
                                .font(ShellZoomMetrics.font(Typography.caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, ShellZoomMetrics.size(4))
            .padding(.horizontal, ShellZoomMetrics.size(12))
            .background(rowBackground)
            .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(Radius.xs)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("file-tree-item-\(displayName)")
        .onHover { hovering in isHovering = hovering }
    }

    private var rowBackground: Color {
        if isActive { return Color.fallbackAccent.opacity(0.15) }
        if isHovering { return Color.primary.opacity(0.07) }
        return .clear
    }

    /// Path to load as a file-based icon, or nil if the icon is not a file path.
    private var iconFilePath: String? {
        guard let icon = entry.icon, !icon.isEmpty else { return nil }
        if icon.hasPrefix("custom:") {
            return String(icon.dropFirst(7))
        } else if icon.hasPrefix("sf:") || icon.unicodeScalars.first?.properties.isEmoji == true {
            return nil
        } else if FileManager.default.fileExists(atPath: icon) {
            return icon
        }
        return nil
    }

    private func loadIconImage() async {
        guard let path = iconFilePath else {
            cachedIconImage = nil
            return
        }
        let loaded = await Task.detached(priority: .utility) {
            Self.downsampledImage(at: path, maxPixelSize: 32)
        }.value
        if !Task.isCancelled {
            cachedIconImage = loaded
        }
    }

    nonisolated private static func downsampledImage(at path: String, maxPixelSize: Int) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = entry.icon, !icon.isEmpty {
            if icon.hasPrefix("custom:") || iconFilePath != nil {
                // File-based icon — uses async-loaded cachedIconImage
                if let cached = cachedIconImage {
                    Image(nsImage: cached)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: ShellZoomMetrics.size(16), height: ShellZoomMetrics.size(16))
                        .clipShape(.rect(cornerRadius: ShellZoomMetrics.size(3)))
                } else {
                    defaultIcon
                }
            } else if icon.hasPrefix("sf:") {
                // SF Symbol (sf:symbolName)
                Image(systemName: String(icon.dropFirst(3)))
                    .font(ShellZoomMetrics.font(Typography.bodySmall))
                    .foregroundStyle(.secondary)
                    .frame(width: ShellZoomMetrics.size(16), height: ShellZoomMetrics.size(16))
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon)
                    .font(ShellZoomMetrics.font(13))
                    .minimumScaleFactor(0.5)
                    .frame(width: ShellZoomMetrics.size(16), height: ShellZoomMetrics.size(16))
            } else {
                defaultIcon
            }
        } else {
            defaultIcon
        }
    }

    @ViewBuilder
    private var defaultIcon: some View {
        Image(systemName: entry.isDatabase ? "tablecells" : "doc.text")
            .font(ShellZoomMetrics.font(Typography.bodySmall))
            .foregroundStyle(.secondary)
            .frame(width: ShellZoomMetrics.size(16), height: ShellZoomMetrics.size(16))
    }

    private var displayName: String {
        if entry.isDatabase { return entry.name }
        return entry.name.removingPageExtension
    }

    private var parentPathLabel: String? {
        guard showsParentPath, let workspacePath else { return nil }

        let parent = ((entry.path as NSString).deletingLastPathComponent as NSString).standardizingPath
        let root = (workspacePath as NSString).standardizingPath
        guard parent != root else { return nil }

        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        guard parent.hasPrefix(rootPrefix) else {
            let fallback = (parent as NSString).lastPathComponent
            return fallback.isEmpty ? nil : fallback
        }

        let relative = String(parent.dropFirst(rootPrefix.count))
        guard !relative.isEmpty else { return nil }
        return relative.replacingOccurrences(of: "/", with: " / ")
    }

    /// Whether this entry can be expanded (directories or pages with sub-pages).
    private var isExpandable: Bool {
        if isSidebarReference { return false }
        if entry.isDatabase { return false }
        return entry.isDirectory || (entry.children != nil && !(entry.children?.isEmpty ?? true))
    }

    private var isActive: Bool {
        activeFilePath == entry.path
    }

    private func handleTap() {
        onSelectFile(entry)
    }

    // MARK: - Expanded State Persistence

    private func toggleExpanded() {
        if expandedFolders.contains(entry.path) {
            expandedFolders.remove(entry.path)
        } else {
            expandedFolders.insert(entry.path)
        }
        UserDefaults.standard.set(Array(expandedFolders), forKey: Self.expandedFoldersKey)
    }

    // MARK: - Context Menu

    private var sidebarContextMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ctxButton(id: "new-note", icon: "doc.badge.plus", label: "New Note") {
                showContextMenu = false; performCreateNote()
            }
            ctxButton(id: "new-db", icon: "tablecells", label: "New Database") {
                showContextMenu = false; performCreateDatabase()
            }
            ctxDivider

            ctxButton(id: "rename", icon: "pencil", label: "Rename") {
                showContextMenu = false; startRename()
            }
            ctxButton(id: "duplicate", icon: "doc.on.doc", label: "Duplicate") {
                showContextMenu = false; performDuplicate()
            }
            if entry.isDirectory || entry.children != nil {
                ctxButton(id: "sub-page", icon: "doc.text.below.ecg", label: "New Sub-page") {
                    showContextMenu = false; performCreateSubPage()
                }
            }
            ctxButton(id: "move-to", icon: "arrow.right", label: "Move to") {
                showContextMenu = false; requestMovePage()
            }

            ctxDivider

            if let workspace = workspacePath {
                ctxButton(
                    id: "favorite",
                    icon: fileSystem.isFavorite(entry.path, for: workspace) ? "star.fill" : "star",
                    label: fileSystem.isFavorite(entry.path, for: workspace) ? "Unfavorite page" : "Favorite page"
                ) {
                    showContextMenu = false
                    if fileSystem.isFavorite(entry.path, for: workspace) {
                        fileSystem.removeFavoritePath(entry.path, for: workspace)
                    } else {
                        fileSystem.addFavoritePath(entry.path, for: workspace)
                    }
                    onRefreshTree()
                }

                ctxDivider
            }

            ctxButton(id: "delete", icon: "trash", label: "Delete", isDestructive: true) {
                showContextMenu = false; showDeleteConfirmation = true
            }
        }
        .frame(width: ShellZoomMetrics.size(200))
        .padding(.vertical, ShellZoomMetrics.size(4))
        .popoverSurface()
    }

    private func ctxButton(
        id: String, icon: String, label: String,
        isDestructive: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: ShellZoomMetrics.size(8)) {
                Image(systemName: icon)
                    .font(ShellZoomMetrics.font(Typography.bodySmall))
                    .foregroundStyle(isDestructive ? .red.opacity(0.8) : .secondary)
                    .frame(width: ShellZoomMetrics.size(16), height: ShellZoomMetrics.size(16))
                Text(label)
                    .font(ShellZoomMetrics.font(Typography.bodySmall))
                    .foregroundStyle(isDestructive ? .red.opacity(0.8) : .primary)
                Spacer()
            }
            .padding(.horizontal, ShellZoomMetrics.size(10))
            .frame(height: ShellZoomMetrics.size(28))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.xs))
                    .fill(hoveredMenuItem == id ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, ShellZoomMetrics.size(4))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in hoveredMenuItem = isHovering ? id : nil }
    }

    private var ctxDivider: some View {
        Divider()
            .padding(.vertical, ShellZoomMetrics.size(4))
            .padding(.horizontal, ShellZoomMetrics.size(10))
    }

    // MARK: - Actions

    private func startRename() {
        renameName = displayName
        isRenaming = true
    }

    private func commitRename() {
        isRenaming = false
        let trimmed = renameName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != displayName else { return }

        let dir = (entry.path as NSString).deletingLastPathComponent
        let ext: String
        if entry.isDatabase || entry.isDirectory {
            ext = ""
        } else {
            let pathExt = (entry.path as NSString).pathExtension
            ext = pathExt.isEmpty ? "" : ".\(pathExt)"
        }
        let newPath = (dir as NSString).appendingPathComponent("\(trimmed)\(ext)")

        try? fileSystem.renameFile(from: entry.path, to: newPath)
        if entry.isDatabase {
            try? fileSystem.updateDatabaseDisplayName(at: newPath, name: trimmed)
        }
        onRefreshTree()
    }

    private func performDelete() {
        let path = entry.path
        if let workspace = workspacePath {
            try? fileSystem.trashFile(at: path, workspace: workspace)
        } else {
            try? fileSystem.deleteFile(at: path)
        }
        NotificationCenter.default.post(name: .fileDeleted, object: path)
        onRefreshTree()
    }

    private func performDuplicate() {
        if let newPath = try? fileSystem.duplicateFile(at: entry.path) {
            onRefreshTree()
            let name = (newPath as NSString).lastPathComponent
            let dup = FileEntry(
                id: newPath, name: name, path: newPath,
                isDirectory: entry.isDirectory,
                kind: entry.kind
            )
            onSelectFile(dup)
        }
    }

    private func performCreateNote() {
        let dir = entry.isDirectory ? entry.path : (entry.path as NSString).deletingLastPathComponent
        do {
            let path = try fileSystem.createNewFile(in: dir)
            onRefreshTree()
            if entry.isDirectory && !isExpanded { toggleExpanded() }
            let name = (path as NSString).lastPathComponent
            let note = FileEntry(
                id: path, name: name, path: path,
                isDirectory: false
            )
            onSelectFile(note)
        } catch {
            Log.fileSystem.error("Failed to create note: \(error.localizedDescription)")
        }
    }

    private func performCreateFolder() {
        guard entry.isDirectory else { return }
        let folderPath = (entry.path as NSString).appendingPathComponent("New Folder")
        try? FileManager.default.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
        onRefreshTree()
        if !isExpanded { toggleExpanded() }
    }

    private func performCreateSubPage() {
        if let path = try? fileSystem.createSubPage(under: entry.path, name: "New Page") {
            onRefreshTree()
            if !isExpanded { toggleExpanded() }
            let sub = FileEntry(
                id: path, name: (path as NSString).lastPathComponent,
                path: path, isDirectory: false
            )
            onSelectFile(sub)
        }
    }

    private func performCreateDatabase() {
        let path: String?
        if entry.kind == .page, !entry.isDirectory, entry.path.hasSuffix(".md") {
            path = try? fileSystem.createDatabase(underPage: entry.path, name: "Untitled Database")
        } else {
            let dir = entry.isDirectory ? entry.path : (entry.path as NSString).deletingLastPathComponent
            path = try? fileSystem.createDatabase(in: dir, name: "Untitled Database")
        }

        if let path {
            onRefreshTree()
            let displayName = (path as NSString).lastPathComponent
            let db = FileEntry(
                id: path, name: displayName,
                path: path, isDirectory: false, kind: .database
            )
            onSelectFile(db)
        }
    }

    private func requestMovePage() {
        NotificationCenter.default.post(name: .movePage, object: entry.path)
    }

}
