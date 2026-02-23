import SwiftUI

struct FileTreeView: View {
    let entries: [FileEntry]
    let activeFilePath: String?
    var fileSystem: FileSystemService
    var workspacePath: String?
    var parentPath: String?
    var onSelectFile: (FileEntry) -> Void
    var onRefreshTree: () -> Void

    @State private var dragOverIndex: Int?

    var body: some View {
        LazyVStack(spacing: 1) {
            ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
                VStack(spacing: 0) {
                    // Drop indicator above this item
                    if dragOverIndex == index {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .padding(.horizontal, 8)
                    }

                    FileTreeItemView(
                        entry: entry,
                        activeFilePath: activeFilePath,
                        fileSystem: fileSystem,
                        workspacePath: workspacePath,
                        onSelectFile: onSelectFile,
                        onRefreshTree: onRefreshTree
                    )
                    .onDrag {
                        NSItemProvider(object: entry.path as NSString)
                    }
                    .onDrop(of: [.text], delegate: FileTreeDropDelegate(
                        targetIndex: index,
                        entries: sortedEntries,
                        parentPath: effectiveParentPath,
                        fileSystem: fileSystem,
                        dragOverIndex: $dragOverIndex,
                        onRefreshTree: onRefreshTree
                    ))
                }
            }

            // Drop indicator at the end
            if dragOverIndex == sortedEntries.count {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
        .onDrop(of: [.text], delegate: FileTreeDropDelegate(
            targetIndex: sortedEntries.count,
            entries: sortedEntries,
            parentPath: effectiveParentPath,
            fileSystem: fileSystem,
            dragOverIndex: $dragOverIndex,
            onRefreshTree: onRefreshTree
        ))
    }

    private var effectiveParentPath: String {
        parentPath ?? workspacePath ?? "__root__"
    }

    private var sortedEntries: [FileEntry] {
        fileSystem.sortedEntries(entries, parentPath: effectiveParentPath)
    }
}

// MARK: - Drop Delegate

struct FileTreeDropDelegate: DropDelegate {
    let targetIndex: Int
    let entries: [FileEntry]
    let parentPath: String
    let fileSystem: FileSystemService
    @Binding var dragOverIndex: Int?
    let onRefreshTree: () -> Void

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

        guard let provider = info.itemProviders(for: [.text]).first else { return false }

        provider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, _ in
            guard let data = data as? Data,
                  let draggedPath = String(data: data, encoding: .utf8) else { return }

            let draggedName = (draggedPath as NSString).lastPathComponent

            // Only allow reorder within same parent
            let draggedParent = (draggedPath as NSString).deletingLastPathComponent
            let entryParents = Set(entries.map { ($0.path as NSString).deletingLastPathComponent })
            guard entryParents.contains(draggedParent) || entries.contains(where: { $0.path == draggedPath }) else { return }

            DispatchQueue.main.async {
                fileSystem.reorderEntry(
                    named: draggedName,
                    toIndex: targetIndex,
                    inParent: parentPath,
                    siblings: entries
                )
                onRefreshTree()
            }
        }

        return true
    }
}
