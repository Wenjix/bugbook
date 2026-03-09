import SwiftUI
import BugbookCore

/// Full-height side panel for peeking at a database row from an inline embed.
/// Loads its own schema/row from disk since it lives at the ContentView level.
struct InlineRowPeekPanel: View {
    let dbPath: String
    let rowId: String
    var onClose: () -> Void
    var onOpenFullPage: () -> Void

    @StateObject private var vm: DatabaseRowViewModel

    init(dbPath: String, rowId: String, onClose: @escaping () -> Void, onOpenFullPage: @escaping () -> Void) {
        self.dbPath = dbPath
        self.rowId = rowId
        self.onClose = onClose
        self.onOpenFullPage = onOpenFullPage
        _vm = StateObject(wrappedValue: DatabaseRowViewModel(dbPath: dbPath, origin: "peekPanel"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with close / expand buttons
            HStack(spacing: 8) {
                Button { onClose() } label: {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { onOpenFullPage() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    Button { onOpenFullPage() } label: {
                        Label("Open as full page", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    Button(role: .destructive) {
                        deleteCurrentRow()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(.secondary)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if vm.schema != nil, vm.row != nil {
                vm.rowPageView(onBack: { onClose() })
            } else {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                Spacer()
            }
        }
        .background(Color.fallbackEditorBg)
        .overlay {
            Rectangle()
                .stroke(Color.fallbackChromeBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .task { vm.loadData(rowId: rowId) }
        .onChange(of: rowId) { _, _ in vm.loadData(rowId: rowId) }
        .onDisappear { vm.flushAndCancel() }
    }

    private func deleteCurrentRow() {
        guard vm.row != nil else { return }
        vm.deleteRow(vm.row!.id)
        onClose()
    }
}
