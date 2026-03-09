import SwiftUI
import BugbookCore

struct DatabaseRowFullPageView: View {
    let dbPath: String
    let rowId: String
    var onTitleChange: (String) -> Void

    @StateObject private var vm: DatabaseRowViewModel

    init(dbPath: String, rowId: String, onTitleChange: @escaping (String) -> Void) {
        self.dbPath = dbPath
        self.rowId = rowId
        self.onTitleChange = onTitleChange
        _vm = StateObject(wrappedValue: DatabaseRowViewModel(dbPath: dbPath, origin: "rowFullPage"))
    }

    var body: some View {
        Group {
            if let error = vm.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Failed to load row")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { vm.loadData(rowId: rowId) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.schema != nil, vm.row != nil {
                vm.rowPageView()
            } else {
                ProgressView("Loading row...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.fallbackEditorBg)
        .task { vm.loadData(rowId: rowId) }
        .onChange(of: rowId) { _, _ in vm.loadData(rowId: rowId) }
        .onDisappear { vm.flushAndCancel() }
        .onChange(of: vm.row) { _, newRow in
            if let newRow, let schema = vm.schema {
                onTitleChange(newRow.title(schema: schema))
            }
        }
    }
}
