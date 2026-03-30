import SwiftUI
import Combine

/// Describes how the current drag is targeting a sidebar row.
enum DropMode: Equatable {
    case above(Int)   // insert line above this index
    case onto(Int)    // highlight this row (move into)
}

/// Reference-type wrapper so all drop delegates share a single stable instance,
/// preventing stale-binding issues when SwiftUI re-creates delegate structs.
final class DropIndicatorState: ObservableObject {
    @Published var mode: DropMode?

    private var cancellable: AnyCancellable?

    init() {
        // During an active drag, dropUpdated sets mode continuously (~20 Hz).
        // Debounce waits for 0.5s of silence — when the drag ends and no
        // delegate callback fires (dropExited is unreliable in SwiftUI),
        // the debounced nil-clear fires automatically.
        cancellable = $mode
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] newMode in
                guard let self, newMode != nil else { return }
                self.mode = nil
            }
    }
}

struct FileTreeView: View {
    let entries: [FileEntry]
    let activeFilePath: String?
    var fileSystem: FileSystemService
    var workspacePath: String?
    var parentPath: String?
    var onSelectFile: (FileEntry) -> Void
    var onRefreshTree: () -> Void
    @Binding var expandedFolders: Set<String>

    @StateObject private var dropState = DropIndicatorState()
    @State private var cachedEntries: [FileEntry] = []

    var body: some View {
        VStack(spacing: ShellZoomMetrics.size(1)) {
            ForEach(Array(cachedEntries.enumerated()), id: \.element.id) { index, entry in
                FileTreeItemView(
                    entry: entry,
                    activeFilePath: activeFilePath,
                    fileSystem: fileSystem,
                    workspacePath: workspacePath,
                    onSelectFile: onSelectFile,
                    onRefreshTree: onRefreshTree,
                    expandedFolders: $expandedFolders
                )
                // Use overlays instead of conditional views to avoid layout shifts
                .overlay(alignment: .top) {
                    if case .above(index) = dropState.mode {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .padding(.horizontal, ShellZoomMetrics.size(8))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: ShellZoomMetrics.size(Radius.xs))
                        .fill(dropState.mode == .onto(index) ? Color.accentColor.opacity(0.15) : Color.clear)
                        .allowsHitTesting(false)
                )
                .onDrag {
                    dropState.mode = nil
                    return NSItemProvider(object: entry.path as NSString)
                }
                .onDrop(of: [.text], delegate: FileTreeDropDelegate(
                    targetIndex: index,
                    targetEntry: entry,
                    entries: cachedEntries,
                    parentPath: effectiveParentPath,
                    fileSystem: fileSystem,
                    dropState: dropState,
                    onDidReorder: { recomputeEntries() },
                    onRefreshTree: onRefreshTree
                ))
            }

            // Drop zone below the last item
            Color.clear
                .frame(height: ShellZoomMetrics.size(20))
                .overlay(alignment: .top) {
                    if dropState.mode == .above(cachedEntries.count) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .padding(.horizontal, ShellZoomMetrics.size(8))
                    }
                }
                .onDrop(of: [.text], delegate: FileTreeDropDelegate(
                    targetIndex: cachedEntries.count,
                    targetEntry: nil,
                    entries: cachedEntries,
                    parentPath: effectiveParentPath,
                    fileSystem: fileSystem,
                    dropState: dropState,
                    onDidReorder: { recomputeEntries() },
                    onRefreshTree: onRefreshTree
                ))
        }
        .onAppear { recomputeEntries() }
        .onChange(of: entries) { _, _ in recomputeEntries() }
    }

    private var effectiveParentPath: String {
        parentPath ?? workspacePath ?? "__root__"
    }

    private func recomputeEntries() {
        let sorted = fileSystem.sortedEntries(entries, parentPath: effectiveParentPath)
        // Update if entries changed (ids, order, or properties like icon)
        if sorted != cachedEntries {
            cachedEntries = sorted
            fileSystem.reconcileCustomOrder(for: sorted, parentPath: effectiveParentPath)
        }
    }
}

// MARK: - Drop Delegate

struct FileTreeDropDelegate: DropDelegate {
    let targetIndex: Int
    let targetEntry: FileEntry?
    let entries: [FileEntry]
    let parentPath: String
    let fileSystem: FileSystemService
    let dropState: DropIndicatorState
    var onDidReorder: () -> Void
    let onRefreshTree: () -> Void

    /// Whether the target entry can accept children (pages can, databases cannot).
    private var targetAcceptsChildren: Bool {
        guard let entry = targetEntry else { return false }
        if entry.isDatabase { return false }
        return entry.name.hasSuffix(".md") || entry.isDirectory
    }

    func dropEntered(info: DropInfo) {
        updateDropMode(info: info)
    }

    func dropExited(info: DropInfo) {
        dropState.mode = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropMode(info: info)
        return DropProposal(operation: .move)
    }

    private func updateDropMode(info: DropInfo) {
        guard targetAcceptsChildren else {
            // Split into top/bottom halves so items can be placed below database
            let y = info.location.y
            let rowHeight = ShellZoomMetrics.size(28)
            let fraction = y / rowHeight
            dropState.mode = fraction < 0.5 ? .above(targetIndex) : .above(targetIndex + 1)
            return
        }
        // Vertical position within the row: top 25% = above, middle 50% = into, bottom 25% = above next
        let y = info.location.y
        let rowHeight = ShellZoomMetrics.size(28)
        let fraction = y / rowHeight
        if fraction < 0.25 {
            dropState.mode = .above(targetIndex)
        } else if fraction > 0.75 {
            dropState.mode = .above(targetIndex + 1)
        } else {
            dropState.mode = .onto(targetIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let currentMode = dropState.mode
        dropState.mode = nil

        // No drop mode means the drag ended without a valid target — reject the drop
        guard currentMode != nil else { return false }
        guard let provider = info.itemProviders(for: [.text]).first else { return false }

        // Capture reference for use in async callback
        let state = dropState

        provider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, _ in
            guard let data = data as? Data,
                  let draggedPath = String(data: data, encoding: .utf8),
                  !draggedPath.isEmpty else {
                DispatchQueue.main.async { state.mode = nil }
                return
            }

            DispatchQueue.main.async {
                // Belt-and-suspenders: clear indicator on every exit path
                defer { state.mode = nil }

                switch currentMode {
                case .onto(let idx):
                    guard idx < entries.count else { return }
                    let target = entries[idx]
                    // Guard: only move into pages that accept children, never into databases/canvases
                    guard !target.isDatabase else { return }
                    guard target.path != draggedPath else { return }
                    // Don't nest databases inside pages — databases should stay at their current level
                    if fileSystem.isDatabaseFolder(at: draggedPath) { return }
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

                case .above(let insertIndex):
                    let draggedName = (draggedPath as NSString).lastPathComponent
                    guard !draggedName.isEmpty else { return }
                    let draggedParent = (draggedPath as NSString).deletingLastPathComponent
                    let entryParents = Set(entries.map { ($0.path as NSString).deletingLastPathComponent })
                    guard entryParents.contains(draggedParent) || entries.contains(where: { $0.path == draggedPath }) else { return }

                    fileSystem.reorderEntry(
                        named: draggedName,
                        toIndex: insertIndex,
                        inParent: parentPath,
                        siblings: entries
                    )
                    onDidReorder()

                case .none:
                    break
                }
            }
        }

        return true
    }
}
