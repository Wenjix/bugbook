import SwiftUI
import DahsoCore

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
                vm.rowPageView(
                    fullWidth: fullWidth,
                    workspacePath: workspacePath,
                    templates: vm.schema?.templates ?? [],
                    onApplyTemplate: { template in
                        applyTemplate(template)
                    },
                    onNewTemplate: {
                        vm.createTemplate(name: "Untitled")
                    },
                    onSaveAsTemplate: {
                        saveCurrentRowAsTemplate()
                    }
                )
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

    private func applyTemplate(_ template: DatabaseTemplate) {
        guard var currentRow = vm.row, let schema = vm.schema else { return }
        for (key, value) in template.defaultProperties {
            currentRow.properties[key] = value
        }
        currentRow.body = template.body
        vm.debouncedSave(currentRow, schema: schema)
    }

    private func saveCurrentRowAsTemplate() {
        guard let row = vm.row, let schema = vm.schema else { return }
        var defaults: [String: PropertyValue] = [:]
        for prop in schema.properties where prop.type != .title {
            if let val = row.properties[prop.id], val != .empty {
                defaults[prop.id] = val
            }
        }
        let titleText: String
        if let titleProp = schema.titleProperty, let val = row.properties[titleProp.id], case .text(let t) = val {
            titleText = t
        } else {
            titleText = "Untitled"
        }
        vm.createTemplate(
            name: "\(titleText) template",
            defaultProperties: defaults,
            body: row.body
        )
    }
}
