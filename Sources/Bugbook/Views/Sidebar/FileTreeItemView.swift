import SwiftUI
import os

struct FileTreeItemView: View {
    let entry: FileEntry
    let activeFilePath: String?
    var fileSystem: FileSystemService
    var workspacePath: String?
    var onSelectFile: (FileEntry) -> Void
    var onRefreshTree: () -> Void

    @State private var isExpanded: Bool = false
    @State private var isRenaming: Bool = false
    @State private var renameName: String = ""
    @State private var showDeleteConfirmation: Bool = false

    private static let expandedFoldersKey = "expandedFolders"

    var body: some View {
        VStack(spacing: 0) {
            // Row
            HStack(spacing: 6) {
                if entry.isDirectory && !entry.isDatabase {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                        .onTapGesture { toggleExpanded() }
                }

                iconView

                if isRenaming {
                    TextField("", text: $renameName, onCommit: { commitRename() })
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onExitCommand { isRenaming = false }
                } else {
                    Text(displayName)
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(isActive ? Color.fallbackAccent.opacity(0.15) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
            .accessibilityIdentifier("file-tree-item-\(displayName)")
            .onTapGesture { handleTap() }
            .contextMenu { contextMenuItems }

            // Children (if expanded)
            if isExpanded, let children = entry.children {
                FileTreeView(
                    entries: children,
                    activeFilePath: activeFilePath,
                    fileSystem: fileSystem,
                    workspacePath: workspacePath,
                    parentPath: entry.path,
                    onSelectFile: onSelectFile,
                    onRefreshTree: onRefreshTree
                )
                .padding(.leading, 12)
            }
        }
        .onAppear { loadExpandedState() }
        .alert("Delete \"\(displayName)\"?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = entry.icon, !icon.isEmpty {
            if icon.hasPrefix("custom:") {
                // Custom uploaded icon image (custom:/path/to/image)
                let path = String(icon.dropFirst(7))
                if let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                } else {
                    defaultIcon
                }
            } else if icon.hasPrefix("sf:") {
                // SF Symbol (sf:symbolName)
                Image(systemName: String(icon.dropFirst(3)))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.system(size: 15))
            } else if FileManager.default.fileExists(atPath: icon) {
                // Raw file path (legacy)
                if let nsImage = NSImage(contentsOfFile: icon) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                } else {
                    defaultIcon
                }
            } else {
                defaultIcon
            }
        } else {
            defaultIcon
        }
    }

    @ViewBuilder
    private var defaultIcon: some View {
        if entry.isCanvas {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        } else if entry.isDatabase {
            Image(systemName: "tablecells")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        } else if entry.isDirectory {
            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        } else {
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    private var displayName: String {
        if entry.name.hasSuffix(".md") && !entry.isDatabase {
            return String(entry.name.dropLast(3))
        }
        return entry.name
    }

    private var isActive: Bool {
        activeFilePath == entry.path
    }

    private func handleTap() {
        if entry.isDirectory && !entry.isDatabase {
            toggleExpanded()
        } else {
            onSelectFile(entry)
        }
    }

    // MARK: - Expanded State Persistence

    private func toggleExpanded() {
        isExpanded.toggle()
        saveExpandedState()
    }

    private func loadExpandedState() {
        guard entry.isDirectory && !entry.isDatabase else { return }
        let expanded = expandedFolders()
        isExpanded = expanded.contains(entry.path)
    }

    private func saveExpandedState() {
        var expanded = expandedFolders()
        if isExpanded {
            expanded.insert(entry.path)
        } else {
            expanded.remove(entry.path)
        }
        UserDefaults.standard.set(Array(expanded), forKey: Self.expandedFoldersKey)
    }

    private func expandedFolders() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: Self.expandedFoldersKey) ?? []
        return Set(arr)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button { performCreateNote() } label: {
            Label("New Note", systemImage: "doc.badge.plus")
        }
        Button { performCreateDatabase() } label: {
            Label("New Database", systemImage: "tablecells")
        }
        Button { performCreateCanvas() } label: {
            Label("New Canvas", systemImage: "rectangle.on.rectangle.angled")
        }
        if entry.isDirectory && !entry.isDatabase {
            Button { performCreateFolder() } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        }
        Divider()
        Button { startRename() } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button { performDuplicate() } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }
        if entry.isDirectory || entry.children != nil {
            Button { performCreateSubPage() } label: {
                Label("New Sub-page", systemImage: "doc.text.below.ecg")
            }
        }
        Divider()
        Button(role: .destructive) { showDeleteConfirmation = true } label: {
            Label("Delete", systemImage: "trash")
        }
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
        let ext = (entry.isDatabase || entry.isCanvas || entry.isDirectory) ? "" : ".md"
        let newPath = (dir as NSString).appendingPathComponent("\(trimmed)\(ext)")

        try? fileSystem.renameFile(from: entry.path, to: newPath)
        if entry.isDatabase {
            try? fileSystem.updateDatabaseDisplayName(at: newPath, name: trimmed)
        } else if entry.isCanvas {
            try? fileSystem.updateCanvasDisplayName(at: newPath, name: trimmed)
        }
        onRefreshTree()
    }

    private func performDelete() {
        let path = entry.path
        try? fileSystem.deleteFile(at: path)
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
        let dir = entry.isDirectory ? entry.path : (entry.path as NSString).deletingLastPathComponent
        if let path = try? fileSystem.createDatabase(in: dir, name: "Untitled Database") {
            onRefreshTree()
            let displayName = (path as NSString).lastPathComponent
            let db = FileEntry(
                id: path, name: displayName,
                path: path, isDirectory: false, kind: .database
            )
            onSelectFile(db)
        }
    }

    private func performCreateCanvas() {
        let dir = entry.isDirectory ? entry.path : (entry.path as NSString).deletingLastPathComponent
        if let path = try? fileSystem.createCanvas(in: dir, name: "Untitled Canvas") {
            onRefreshTree()
            let displayName = "Untitled Canvas"
            let canvas = FileEntry(
                id: path, name: displayName,
                path: path, isDirectory: false, kind: .canvas
            )
            onSelectFile(canvas)
        }
    }
}
