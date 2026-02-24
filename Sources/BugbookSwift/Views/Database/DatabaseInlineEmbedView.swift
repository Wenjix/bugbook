import SwiftUI
import BugbookCore

/// Compact database embed for rendering inside a markdown page.
/// Interactive mini-table with editable titles, property editors, and inline row creation.
struct DatabaseInlineEmbedView: View {
    let dbPath: String
    var maxRows: Int = 10
    var onOpenRow: ((DatabaseRow) -> Void)?
    var onOpenDatabase: (() -> Void)?

    @StateObject private var dbService = DatabaseService()
    @State private var schema: DatabaseSchema?
    @State private var rows: [DatabaseRow] = []
    @State private var error: String?
    @State private var hoveredRowId: String?
    @State private var editingRowId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = error {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.red)
                    .padding(8)
            } else if let schema = schema {
                headerBar(schema: schema)
                Divider()
                interactiveTable(schema: schema)
                Divider()
                newRowButton(schema: schema)
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .task {
            await loadData()
        }
    }

    // MARK: - Header

    private func headerBar(schema: DatabaseSchema) -> some View {
        HStack {
            Button {
                onOpenDatabase?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tablecells")
                        .font(.callout)
                    Text(schema.name)
                        .font(.callout)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(rows.count) rows")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Table

    private func interactiveTable(schema: DatabaseSchema) -> some View {
        let displayProps = Array(schema.properties.filter({ $0.type != .title }).prefix(4))

        return VStack(alignment: .leading, spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text(schema.titleProperty?.name ?? "Name")
                    .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                ForEach(displayProps) { prop in
                    Text(prop.name)
                        .frame(width: 140, alignment: .leading)
                }
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            Divider().opacity(0.5)

            // Rows
            ForEach(Array(rows.prefix(maxRows).enumerated()), id: \.element.id) { idx, row in
                let globalIdx = rows.firstIndex(where: { $0.id == row.id })!
                interactiveRow(globalIndex: globalIdx, schema: schema, displayProps: displayProps)
                if idx < min(rows.count, maxRows) - 1 {
                    Divider().opacity(0.3).padding(.leading, 12)
                }
            }

            if rows.count > maxRows {
                Button {
                    onOpenDatabase?()
                } label: {
                    Text("+\(rows.count - maxRows) more")
                        .font(.callout)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private func interactiveRow(globalIndex idx: Int, schema: DatabaseSchema, displayProps: [PropertyDefinition]) -> some View {
        let row = rows[idx]
        let isEditing = editingRowId == row.id
        let isHovered = hoveredRowId == row.id

        return HStack(spacing: 0) {
            // Title cell
            if isEditing {
                TextField("New Page", text: Binding(
                    get: { rawTitle(at: idx, schema: schema) },
                    set: { newVal in
                        if let titlePropId = schema.titleProperty?.id {
                            rows[idx].properties[titlePropId] = .text(newVal)
                        }
                    }
                ), onCommit: {
                    saveRow(rows[idx], schema: schema)
                    editingRowId = nil
                })
                .textFieldStyle(.plain)
                .font(.body)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                )
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 4) {
                    Text(row.title(schema: schema))
                        .font(.body)
                        .lineLimit(1)
                        .foregroundColor(rawTitle(at: idx, schema: schema).isEmpty ? .secondary : .primary)
                    Spacer()
                    if isHovered {
                        Button {
                            onOpenDatabase?()
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { editingRowId = row.id }
            }

            // Property cells
            ForEach(displayProps) { prop in
                inlineCellEditor(rowIndex: idx, prop: prop, schema: schema)
                    .frame(width: 140, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isHovered ? Color.gray.opacity(0.04) : Color.clear)
        .onHover { hoveredRowId = $0 ? row.id : nil }
    }

    // MARK: - New Row Button

    private func newRowButton(schema: DatabaseSchema) -> some View {
        Button {
            addNewRow(schema: schema)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption)
                Text("New")
                    .font(.callout)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline Cell Editor

    private func rawTitle(at idx: Int, schema: DatabaseSchema) -> String {
        guard let titlePropId = schema.titleProperty?.id,
              let val = rows[idx].properties[titlePropId],
              case .text(let s) = val else { return "" }
        return s
    }

    @ViewBuilder
    private func inlineCellEditor(rowIndex idx: Int, prop: PropertyDefinition, schema: DatabaseSchema) -> some View {
        let value = rows[idx].properties[prop.id] ?? .empty

        switch prop.type {
        case .select:
            inlineSelectCell(rowIndex: idx, prop: prop, value: value)
        case .multiSelect:
            inlineMultiSelectCell(rowIndex: idx, prop: prop, value: value)
        case .checkbox:
            Toggle("", isOn: Binding(
                get: {
                    if case .checkbox(let b) = rows[idx].properties[prop.id] ?? .empty { return b }
                    return false
                },
                set: {
                    rows[idx].properties[prop.id] = .checkbox($0)
                    saveRow(rows[idx], schema: schema)
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
        case .date:
            Text(formattedDate(value))
                .font(.callout)
                .foregroundColor(.secondary)
        default:
            TextField("", text: Binding(
                get: { stringFromValue(value) },
                set: { newVal in
                    rows[idx].properties[prop.id] = prop.type == .number
                        ? .number(Double(newVal) ?? 0)
                        : .text(newVal)
                }
            ), onCommit: {
                saveRow(rows[idx], schema: schema)
            })
            .textFieldStyle(.plain)
            .font(.body)
        }
    }

    // MARK: - Inline Select

    private func inlineSelectCell(rowIndex idx: Int, prop: PropertyDefinition, value: PropertyValue) -> some View {
        let options = prop.options ?? []
        let currentId: String = {
            if case .select(let s) = value { return s }
            return ""
        }()
        let currentOption = options.first(where: { $0.id == currentId })

        return Menu {
            Button("None") {
                rows[idx].properties[prop.id] = .empty
                saveRow(rows[idx], schema: schema!)
            }
            ForEach(options) { option in
                Button {
                    rows[idx].properties[prop.id] = .select(option.id)
                    saveRow(rows[idx], schema: schema!)
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(colorFromString(option.color)).frame(width: 8, height: 8)
                        Text(option.name)
                    }
                }
            }
        } label: {
            if let opt = currentOption {
                Text(opt.name)
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorFromString(opt.color).opacity(0.12))
                    .foregroundColor(colorFromString(opt.color))
                    .cornerRadius(4)
            } else {
                Color.clear.frame(height: 22)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Inline Multi-Select

    private func inlineMultiSelectCell(rowIndex idx: Int, prop: PropertyDefinition, value: PropertyValue) -> some View {
        let options = prop.options ?? []
        let selectedIds: [String] = {
            if case .multiSelect(let arr) = value { return arr }
            return []
        }()

        return HStack(spacing: 3) {
            ForEach(selectedIds.prefix(2), id: \.self) { id in
                if let option = options.first(where: { $0.id == id }) {
                    Text(option.name)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(colorFromString(option.color).opacity(0.12))
                        .foregroundColor(colorFromString(option.color))
                        .cornerRadius(3)
                }
            }
            if selectedIds.count > 2 {
                Text("+\(selectedIds.count - 2)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Menu {
                ForEach(options) { option in
                    let isSelected = selectedIds.contains(option.id)
                    Button {
                        var updated = selectedIds
                        if isSelected {
                            updated.removeAll { $0 == option.id }
                        } else {
                            updated.append(option.id)
                        }
                        rows[idx].properties[prop.id] = updated.isEmpty ? .empty : .multiSelect(updated)
                        saveRow(rows[idx], schema: schema!)
                    } label: {
                        HStack {
                            Circle().fill(colorFromString(option.color)).frame(width: 8, height: 8)
                            Text(option.name)
                            if isSelected { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Data Operations

    private func addNewRow(schema: DatabaseSchema) {
        do {
            let newRow = try dbService.createRow(in: dbPath, schema: schema)
            rows.append(newRow)
            editingRowId = newRow.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveRow(_ row: DatabaseRow, schema: DatabaseSchema) {
        Task {
            try? dbService.saveRow(row, schema: schema, at: dbPath)
        }
    }

    private func loadData() async {
        do {
            let (loadedSchema, loadedRows) = try await dbService.loadDatabase(at: dbPath)
            schema = loadedSchema
            rows = loadedRows
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func stringFromValue(_ value: PropertyValue) -> String {
        switch value {
        case .text(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .url(let s): return s
        case .email(let s): return s
        default: return ""
        }
    }

    private func formattedDate(_ value: PropertyValue) -> String {
        guard case .date(let s) = value else { return "" }
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inFmt.date(from: s) else { return s }
        let outFmt = DateFormatter()
        outFmt.dateStyle = .medium
        return outFmt.string(from: date)
    }

    private func colorFromString(_ name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        case "brown": return .brown
        case "teal", "cyan": return .teal
        default: return .accentColor
        }
    }
}
