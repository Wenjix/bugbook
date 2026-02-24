import SwiftUI
import BugbookCore

struct KanbanView: View {
    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onSave: (DatabaseRow) -> Void
    var onUpdateGroupBy: ((String) -> Void)?
    var onAddSelectOption: ((String, SelectOption) -> Void)?

    @State private var newOptionName: String = ""
    @State private var addingOptionForColumn: Bool = false
    @State private var newCardTitle: String = ""
    @State private var addingCardInColumn: String? = nil

    private var selectProperties: [PropertyDefinition] {
        schema.properties.filter { $0.type == .select }
    }

    private var groupProperty: PropertyDefinition? {
        guard let groupId = viewConfig.groupBy else {
            return schema.properties.first(where: { $0.type == .select })
        }
        return schema.properties.first(where: { $0.id == groupId })
    }

    private var columns: [(id: String, name: String, color: String)] {
        guard let prop = groupProperty else { return [] }
        var cols: [(id: String, name: String, color: String)] = [("__none__", "No \(prop.name)", "gray")]
        if let options = prop.options {
            cols += options.map { ($0.id, $0.name, $0.color) }
        }
        return cols
    }

    private func rowsForColumn(_ columnId: String) -> [DatabaseRow] {
        guard let prop = groupProperty else { return rows }
        return rows.filter { row in
            guard let val = row.properties[prop.id] else { return columnId == "__none__" }
            if case .select(let s) = val {
                return s == columnId
            }
            return columnId == "__none__"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // GroupBy selector
            if selectProperties.count > 1 {
                HStack(spacing: 8) {
                    Text("Group by:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Menu {
                        ForEach(selectProperties) { prop in
                            Button {
                                onUpdateGroupBy?(prop.id)
                            } label: {
                                HStack {
                                    Text(prop.name)
                                    if prop.id == groupProperty?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(groupProperty?.name ?? "Select property")
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns, id: \.id) { column in
                        kanbanColumn(column)
                    }

                    // Add new option column
                    if groupProperty != nil {
                        addOptionColumn
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Add Option Column

    private var addOptionColumn: some View {
        VStack(spacing: 8) {
            if addingOptionForColumn {
                VStack(spacing: 6) {
                    TextField("Option name", text: $newOptionName, onCommit: {
                        createNewOption()
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                    HStack(spacing: 6) {
                        Button("Add") { createNewOption() }
                            .font(.caption)
                            .disabled(newOptionName.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("Cancel") {
                            newOptionName = ""
                            addingOptionForColumn = false
                        }
                        .font(.caption)
                    }
                }
                .padding(8)
            } else {
                Button {
                    addingOptionForColumn = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Status")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 200)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private func createNewOption() {
        let name = newOptionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let prop = groupProperty else { return }
        let colors = ["blue", "green", "red", "yellow", "purple", "pink", "orange", "teal"]
        let randomColor = colors.randomElement() ?? "blue"
        let option = SelectOption(id: "opt_\(UUID().uuidString)", name: name, color: randomColor)
        onAddSelectOption?(prop.id, option)
        newOptionName = ""
        addingOptionForColumn = false
    }

    // MARK: - Kanban Column

    private func kanbanColumn(_ column: (id: String, name: String, color: String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(colorForName(column.color))
                    .frame(width: 8, height: 8)

                Text(column.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(rowsForColumn(column.id).count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 6) {
                ForEach(rowsForColumn(column.id)) { row in
                    let title = row.title(schema: schema)
                    kanbanCard(row, title: title)
                        .draggable(row.id) {
                            Text(title)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                        }
                }

                // Inline add card
                if addingCardInColumn == column.id {
                    VStack(spacing: 4) {
                        TextField("Card title", text: $newCardTitle, onCommit: {
                            addCardInColumn(column.id)
                        })
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                        HStack(spacing: 6) {
                            Button("Add") { addCardInColumn(column.id) }
                                .font(.caption)
                                .disabled(newCardTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                            Button("Cancel") {
                                newCardTitle = ""
                                addingCardInColumn = nil
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.horizontal, 6)
                } else {
                    Button {
                        addingCardInColumn = column.id
                        newCardTitle = ""
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("New")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { droppedIds, _ in
                guard let prop = groupProperty else { return false }
                for droppedId in droppedIds {
                    if let idx = rows.firstIndex(where: { $0.id == droppedId }) {
                        let newValue: PropertyValue = column.id == "__none__" ? .empty : .select(column.id)
                        rows[idx].properties[prop.id] = newValue
                        onSave(rows[idx])
                    }
                }
                return true
            }
        }
        .frame(width: 250)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private func addCardInColumn(_ columnId: String) {
        let title = newCardTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let now = Date()
        var properties: [String: PropertyValue] = [:]
        // Set the title property
        if let titleProp = schema.titleProperty {
            properties[titleProp.id] = .text(title)
        }
        if let prop = groupProperty, columnId != "__none__" {
            properties[prop.id] = .select(columnId)
        }
        let suffix = String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        let newRow = DatabaseRow(
            id: "row_\(suffix)",
            properties: properties,
            body: "",
            createdAt: now,
            updatedAt: now
        )
        rows.append(newRow)
        onSave(newRow)
        newCardTitle = ""
        addingCardInColumn = nil
    }

    // MARK: - Kanban Card

    private func kanbanCard(_ row: DatabaseRow, title: String) -> some View {
        Button {
            onOpenRow(row)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                // Show a couple of properties (excluding the group property and title)
                let displayProps = schema.properties.prefix(4).filter {
                    $0.type != .title && ($0.type != .select || $0.id != groupProperty?.id)
                }
                ForEach(displayProps) { prop in
                    if let val = row.properties[prop.id], val != .empty {
                        HStack(spacing: 4) {
                            Text(prop.name)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(displayValue(val, prop: prop))
                                .font(.caption2)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    // MARK: - Helpers

    private func displayValue(_ value: PropertyValue, prop: PropertyDefinition) -> String {
        switch value {
        case .text(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .select(let s):
            return prop.options?.first(where: { $0.id == s })?.name ?? s
        case .multiSelect(let arr):
            return arr.compactMap { id in prop.options?.first(where: { $0.id == id })?.name }.joined(separator: ", ")
        case .date(let s): return s
        case .checkbox(let b): return b ? "Yes" : "No"
        case .url(let s): return s
        case .email(let s): return s
        case .relation(let s): return s
        case .relationMany(let arr): return arr.joined(separator: ", ")
        case .empty: return ""
        }
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "yellow": return .yellow
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "teal": return .teal
        default: return .gray
        }
    }
}
