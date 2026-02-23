import SwiftUI

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
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                        .onTapGesture { toggleExpanded() }
                } else {
                    Spacer().frame(width: 12)
                }

                iconView

                if isRenaming {
                    TextField("", text: $renameName, onCommit: { commitRename() })
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                } else {
                    Text(displayName)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isActive ? Color.fallbackAccent.opacity(0.15) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
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
            if icon.unicodeScalars.first?.properties.isEmoji == true && icon.count <= 2 {
                Text(icon).font(.system(size: 14))
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        } else if entry.isDatabase {
            Image(systemName: "tablecells")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else if entry.isDirectory {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
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
        Button("Rename") { startRename() }
        Button("Duplicate") { performDuplicate() }
        Divider()
        if entry.isDirectory || entry.children != nil {
            Button("New Sub-page") { performCreateSubPage() }
            Button("New Database Inside") { performCreateDatabase() }
            Divider()
        }
        Button("Delete", role: .destructive) { showDeleteConfirmation = true }
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
        let ext = entry.isDatabase ? "" : ".md"
        let newPath = (dir as NSString).appendingPathComponent("\(trimmed)\(ext)")

        try? fileSystem.renameFile(from: entry.path, to: newPath)
        onRefreshTree()
    }

    private func performDelete() {
        try? fileSystem.deleteFile(at: entry.path)
        onRefreshTree()
    }

    private func performDuplicate() {
        if let newPath = try? fileSystem.duplicateFile(at: entry.path) {
            onRefreshTree()
            let name = (newPath as NSString).lastPathComponent
            let dup = FileEntry(
                id: newPath, name: name, path: newPath,
                isDirectory: false, isDatabase: entry.isDatabase,
                icon: nil, children: nil
            )
            onSelectFile(dup)
        }
    }

    private func performCreateSubPage() {
        if let path = try? fileSystem.createSubPage(under: entry.path, name: "Untitled") {
            onRefreshTree()
            if !isExpanded { toggleExpanded() }
            let sub = FileEntry(
                id: path, name: (path as NSString).lastPathComponent,
                path: path, isDirectory: false, isDatabase: false,
                icon: nil, children: nil
            )
            onSelectFile(sub)
        }
    }

    private func performCreateDatabase() {
        let dir = entry.isDirectory ? entry.path : (entry.path as NSString).deletingLastPathComponent
        if let path = try? fileSystem.createDatabase(in: dir, name: "Untitled Database") {
            onRefreshTree()
            let db = FileEntry(
                id: path, name: "Untitled Database",
                path: path, isDirectory: false, isDatabase: true,
                icon: nil, children: nil
            )
            onSelectFile(db)
        }
    }
}
