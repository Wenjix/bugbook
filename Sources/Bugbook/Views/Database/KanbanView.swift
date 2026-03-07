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

    // Custom drag state
    @State private var draggingRowId: String? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var dragTargetColumn: String? = nil

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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                        kanbanColumn(column, index: index)
                    }

                    // Add new option column
                    if groupProperty != nil {
                        addOptionColumn
                    }
                }
                .padding(12)
                .coordinateSpace(name: "kanban")
                .overlay {
                    if let dragId = draggingRowId,
                       let row = rows.first(where: { $0.id == dragId }) {
                        let title = row.title(schema: schema)
                        dragPreview(title)
                            .position(dragLocation)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Drag Preview

    private func dragPreview(_ title: String) -> some View {
        Text(title.isEmpty ? "Untitled" : title)
            .font(.body)
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 220)
            .background(.ultraThinMaterial)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
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
        .background(Color.fallbackSurfaceSubtle)
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

    private func kanbanColumn(_ column: (id: String, name: String, color: String), index: Int) -> some View {
        let isTargeted = dragTargetColumn == column.id
        let columnWidth: CGFloat = 250
        let columnColor = colorForName(column.color)
        return VStack(alignment: .leading, spacing: 0) {
            // Column header with colored label
            HStack {
                Text(column.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(columnColor.opacity(0.2))
                    .foregroundColor(columnColor)
                    .cornerRadius(4)

                Spacer()

                Text("\(rowsForColumn(column.id).count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.fallbackBadgeBg)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            // Cards — no scroll, just expand
            VStack(spacing: 6) {
                let columnRows = rowsForColumn(column.id)

                ForEach(columnRows) { row in
                    let title = row.title(schema: schema)
                    kanbanCard(row, title: title, columnColor: columnColor)
                        .opacity(draggingRowId == row.id ? 0.2 : 1)
                        .gesture(
                            DragGesture(coordinateSpace: .named("kanban"))
                                .onChanged { value in
                                    if draggingRowId == nil { draggingRowId = row.id }
                                    dragLocation = value.location
                                    let colIndex = Int(value.location.x / (columnWidth + 12))
                                    let clampedIndex = max(0, min(colIndex, columns.count - 1))
                                    dragTargetColumn = columns[clampedIndex].id
                                }
                                .onEnded { value in
                                    if let targetCol = dragTargetColumn {
                                        moveCard(row.id, toColumn: targetCol)
                                    }
                                    draggingRowId = nil
                                    dragTargetColumn = nil
                                }
                        )
                }

                // + New page button at bottom, colored like Notion
                Button {
                    addCardInColumn(column.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New page")
                    }
                    .font(.caption)
                    .foregroundColor(columnColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(columnColor.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
            .padding(.bottom, 8)
        }
        .frame(width: columnWidth)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? columnColor.opacity(0.12) : columnColor.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTargeted ? columnColor.opacity(0.4) : columnColor.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Move Card

    private func moveCard(_ rowId: String, toColumn columnId: String) {
        guard let prop = groupProperty else { return }
        guard let sourceIdx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        let newValue: PropertyValue = columnId == "__none__" ? .empty : .select(columnId)
        var updated = rows
        updated[sourceIdx].properties[prop.id] = newValue
        let savedRow = updated[sourceIdx]
        rows = updated
        onSave(savedRow)
    }

    private func addCardInColumn(_ columnId: String) {
        let now = Date()
        var properties: [String: PropertyValue] = [:]
        if let titleProp = schema.titleProperty {
            properties[titleProp.id] = .text("")
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
    }

    // MARK: - Kanban Card

    private func kanbanCard(_ row: DatabaseRow, title: String, columnColor: Color) -> some View {
        Text(title.isEmpty ? "Untitled" : title)
            .font(.body)
            .fontWeight(.medium)
            .lineLimit(2)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(columnColor.opacity(0.06))
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onTapGesture { onOpenRow(row) }
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .padding(.horizontal, 6)
    }

    // MARK: - Helpers

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
