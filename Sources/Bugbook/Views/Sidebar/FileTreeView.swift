import SwiftUI

/// Describes how the current drag is targeting a sidebar row.
enum DropMode: Equatable {
    case above(Int)   // insert line above this index
    case onto(Int)    // highlight this row (move into)
}

struct FileTreeView: View {
    let entries: [FileEntry]
    let activeFilePath: String?
    var fileSystem: FileSystemService
    var workspacePath: String?
    var parentPath: String?
    var onSelectFile: (FileEntry) -> Void
    var onRefreshTree: () -> Void

    @State private var dropMode: DropMode?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(sortedEntries.enumerated(), id: \.element.id) { index, entry in
                FileTreeItemView(
                    entry: entry,
                    activeFilePath: activeFilePath,
                    fileSystem: fileSystem,
                    workspacePath: workspacePath,
                    onSelectFile: onSelectFile,
                    onRefreshTree: onRefreshTree
                )
                // Use overlays instead of conditional views to avoid layout shifts
                .overlay(alignment: .top) {
                    if case .above(index) = dropMode {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .padding(.horizontal, 8)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(dropMode == .onto(index) ? Color.accentColor.opacity(0.15) : Color.clear)
                        .allowsHitTesting(false)
                )
                .onDrag {
                    NSItemProvider(object: entry.path as NSString)
                }
                .onDrop(of: [.text], delegate: FileTreeDropDelegate(
                    targetIndex: index,
                    targetEntry: entry,
                    entries: sortedEntries,
                    parentPath: effectiveParentPath,
                    fileSystem: fileSystem,
                    dropMode: $dropMode,
                    onRefreshTree: onRefreshTree
                ))
            }
        }
        .onDrop(of: [.text], delegate: FileTreeDropDelegate(
            targetIndex: sortedEntries.count,
            targetEntry: nil,
            entries: sortedEntries,
            parentPath: effectiveParentPath,
            fileSystem: fileSystem,
            dropMode: $dropMode,
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
    let targetEntry: FileEntry?
    let entries: [FileEntry]
    let parentPath: String
    let fileSystem: FileSystemService
    @Binding var dropMode: DropMode?
    let onRefreshTree: () -> Void

    /// Whether the target entry can accept children (pages can, databases/canvases cannot).
    private var targetAcceptsChildren: Bool {
        guard let entry = targetEntry else { return false }
        if entry.isDatabase || entry.isCanvas { return false }
        return entry.name.hasSuffix(".md") || entry.isDirectory
    }

    func dropEntered(info: DropInfo) {
        updateDropMode(info: info)
    }

    func dropExited(info: DropInfo) {
        if dropMode == .above(targetIndex) || dropMode == .onto(targetIndex) {
            dropMode = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropMode(info: info)
        return DropProposal(operation: .move)
    }

    private func updateDropMode(info: DropInfo) {
        guard targetAcceptsChildren else {
            dropMode = .above(targetIndex)
            return
        }
        // Vertical position within the row: top 25% = above, middle 50% = into, bottom 25% = above next
        let y = info.location.y
        let rowHeight: CGFloat = 28
        let fraction = y / rowHeight
        if fraction < 0.25 {
            dropMode = .above(targetIndex)
        } else if fraction > 0.75 {
            dropMode = .above(targetIndex + 1)
        } else {
            dropMode = .onto(targetIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let currentMode = dropMode
        dropMode = nil

        guard let provider = info.itemProviders(for: [.text]).first else { return false }

        provider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, _ in
            guard let data = data as? Data,
                  let draggedPath = String(data: data, encoding: .utf8) else { return }

            DispatchQueue.main.async {
                switch currentMode {
                case .onto(let idx):
                    guard idx < entries.count else { return }
                    let target = entries[idx]
                    guard target.path != draggedPath else { return }
                    // Don't drop into own descendant
                    let draggedCompanion = draggedPath.hasSuffix(".md") ? String(draggedPath.dropLast(3)) : draggedPath
                    guard !target.path.hasPrefix(draggedCompanion + "/") else { return }
                    let destDir: String
                    if target.name.hasSuffix(".md") {
                        destDir = String(target.path.dropLast(3))
                    } else {
                        destDir = target.path
                    }
                    NotificationCenter.default.post(
                        name: .movePageToDir,
                        object: nil,
                        userInfo: ["sourcePath": draggedPath, "destDir": destDir]
                    )

                case .above(_):
                    let draggedName = (draggedPath as NSString).lastPathComponent
                    let draggedParent = (draggedPath as NSString).deletingLastPathComponent
                    let entryParents = Set(entries.map { ($0.path as NSString).deletingLastPathComponent })
                    guard entryParents.contains(draggedParent) || entries.contains(where: { $0.path == draggedPath }) else { return }

                    fileSystem.reorderEntry(
                        named: draggedName,
                        toIndex: targetIndex,
                        inParent: parentPath,
                        siblings: entries
                    )
                    onRefreshTree()

                case .none:
                    break
                }
            }
        }

        return true
    }
}
