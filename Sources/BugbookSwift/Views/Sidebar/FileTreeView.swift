import SwiftUI

struct FileTreeView: View {
    let entries: [FileEntry]
    let activeFilePath: String?
    var fileSystem: FileSystemService
    var workspacePath: String?
    var onSelectFile: (FileEntry) -> Void
    var onRefreshTree: () -> Void

    var body: some View {
        LazyVStack(spacing: 1) {
            ForEach(sortedEntries) { entry in
                FileTreeItemView(
                    entry: entry,
                    activeFilePath: activeFilePath,
                    fileSystem: fileSystem,
                    workspacePath: workspacePath,
                    onSelectFile: onSelectFile,
                    onRefreshTree: onRefreshTree
                )
            }
        }
    }

    private var sortedEntries: [FileEntry] {
        entries.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
