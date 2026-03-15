import SwiftUI
import BugbookCore

struct DatabaseRowFullPageView: View {
    let dbPath: String
    let rowId: String
    var onTitleChange: (String) -> Void
    var fullWidth: Bool = false

    @State private var vm: DatabaseRowViewModel
    @Environment(\.workspacePath) private var workspacePath

    init(dbPath: String, rowId: String, onTitleChange: @escaping (String) -> Void, fullWidth: Bool = false) {
        self.dbPath = dbPath
        self.rowId = rowId
        self.onTitleChange = onTitleChange
        self.fullWidth = fullWidth
        _vm = State(initialValue: DatabaseRowViewModel(dbPath: dbPath, origin: "rowFullPage"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = vm.error {
                RowLoadErrorView(message: error) { vm.loadData(rowId: rowId) }
            } else if vm.schema != nil, vm.row != nil {
                vm.rowPageView(fullWidth: fullWidth, workspacePath: workspacePath)
            } else {
                ProgressView("Loading row...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.fallbackEditorBg)
        .task { vm.loadData(rowId: rowId) }
        .onChange(of: rowId) { _, _ in vm.loadData(rowId: rowId) }
        .onChange(of: dbPath) { _, newDbPath in
            vm.flushAndCancel()
            vm = DatabaseRowViewModel(dbPath: newDbPath, origin: "rowFullPage")
            vm.loadData(rowId: rowId)
        }
        .onDisappear { vm.flushAndCancel() }
        .onChange(of: vm.row) { _, newRow in
            if let newRow, let schema = vm.schema {
                onTitleChange(newRow.title(schema: schema))
            }
        }
    }
}
