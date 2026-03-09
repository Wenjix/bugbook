import SwiftUI
import BugbookCore

struct DatabaseRowModalView: View {
    let dbPath: String
    let rowId: String
    var autoFocusTitle: Bool = false
    var onClose: () -> Void
    var onOpenFullPage: () -> Void

    @StateObject private var vm: DatabaseRowViewModel

    init(dbPath: String, rowId: String, autoFocusTitle: Bool = false, onClose: @escaping () -> Void, onOpenFullPage: @escaping () -> Void) {
        self.dbPath = dbPath
        self.rowId = rowId
        self.autoFocusTitle = autoFocusTitle
        self.onClose = onClose
        self.onOpenFullPage = onOpenFullPage
        _vm = StateObject(wrappedValue: DatabaseRowViewModel(dbPath: dbPath, origin: "rowModal"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { onOpenFullPage() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if let error = vm.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("Failed to load row")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Close") { onClose() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else if vm.schema != nil, vm.row != nil {
                vm.rowPageView(onBack: { onClose() }, autoFocusTitle: autoFocusTitle)
            } else {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: 880, maxHeight: 700)
        .background(Color.fallbackEditorBg)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.fallbackChromeBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 26, y: 12)
        .onTapGesture { }
        .onExitCommand { onClose() }
        .task { vm.loadData(rowId: rowId) }
        .onChange(of: rowId) { _, _ in vm.loadData(rowId: rowId) }
        .onDisappear {
            vm.flushAndCancel()
            vm.postChangeNotification()
        }
    }
}
