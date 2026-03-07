import SwiftUI
import BugbookCore

/// Full-height side panel for peeking at a database row from an inline embed.
/// Loads its own schema/row from disk since it lives at the ContentView level.
struct InlineRowPeekPanel: View {
    let dbPath: String
    let rowId: String
    var onClose: () -> Void
    var onOpenFullPage: () -> Void

    @StateObject private var dbService = DatabaseService()
    @State private var schema: DatabaseSchema?
    @State private var row: DatabaseRow?
    @State private var saveTask: Task<Void, Never>?

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

            if let schema = schema, row != nil {
                RowPageView(
                    schema: schema,
                    row: Binding(
                        get: { row! },
                        set: { newRow in
                            row = newRow
                            debouncedSave(newRow, schema: schema)
                        }
                    ),
                    onSave: { newRow in
                        row = newRow
                        debouncedSave(newRow, schema: schema)
                    },
                    onBack: { onClose() },
                    onAddOption: { propId, option in addOption(propId, option: option) },
                    onUpdateOption: { propId, optId, name, color in updateOption(propId, optId: optId, name: name, color: color) },
                    onDeleteOption: { propId, optId in deleteOption(propId, optId: optId) },
                    showBreadcrumb: false
                )
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
        .task { loadData() }
        .onChange(of: rowId) { _, _ in loadData() }
        .onDisappear {
            saveTask?.cancel()
            // Flush pending save synchronously
            if let currentRow = row, let currentSchema = schema {
                try? dbService.saveRow(currentRow, schema: currentSchema, at: dbPath)
            }
        }
    }

    private func loadData() {
        do {
            let (loadedSchema, loadedRows) = try dbService.loadDatabase(at: dbPath)
            schema = loadedSchema
            row = loadedRows.first(where: { $0.id == rowId })
        } catch {
            // Silently fail — panel will show loading state
        }
    }

    private func debouncedSave(_ row: DatabaseRow, schema: DatabaseSchema) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            try? dbService.saveRow(row, schema: schema, at: dbPath)
            NotificationCenter.default.post(
                name: .databaseDidChange,
                object: nil,
                userInfo: ["dbPath": dbPath, "origin": "peekPanel"]
            )
        }
    }

    private func deleteCurrentRow() {
        guard let currentRow = row else { return }
        try? dbService.deleteRow(currentRow.id, in: dbPath)
        onClose()
        NotificationCenter.default.post(
            name: .databaseDidChange,
            object: nil,
            userInfo: ["dbPath": dbPath, "origin": "peekPanel"]
        )
    }

    private func addOption(_ propertyId: String, option: SelectOption) {
        guard var s = schema else { return }
        Task {
            try? dbService.addSelectOption(option, toProperty: propertyId, in: &s, at: dbPath)
            schema = s
        }
    }

    private func updateOption(_ propertyId: String, optId: String, name: String?, color: String?) {
        guard var s = schema else { return }
        Task {
            try? dbService.updateSelectOption(optId, name: name, color: color, inProperty: propertyId, in: &s, at: dbPath)
            schema = s
        }
    }

    private func deleteOption(_ propertyId: String, optId: String) {
        guard var s = schema else { return }
        var rows: [DatabaseRow] = []
        if let r = row { rows = [r] }
        Task {
            try? dbService.deleteSelectOption(optId, fromProperty: propertyId, in: &s, rows: &rows, at: dbPath)
            schema = s
            if let updatedRow = rows.first { row = updatedRow }
        }
    }
}
