import SwiftUI

struct KanbanView: View {
    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onSave: (DatabaseRow) -> Void

    private var groupProperty: PropertyDefinition? {
        guard let groupId = viewConfig.groupByPropertyId else {
            // Default to first select property
            return schema.properties.first(where: { $0.type == .select })
        }
        return schema.properties.first(where: { $0.id == groupId })
    }

    private var columns: [(id: String, name: String)] {
        guard let prop = groupProperty else { return [] }
        var cols: [(id: String, name: String)] = [("__none__", "No \(prop.name)")]
        if let options = prop.options {
            cols += options.map { ($0.id, $0.name) }
        }
        return cols
    }

    private func rowsForColumn(_ columnId: String) -> [DatabaseRow] {
        guard let prop = groupProperty else { return rows }
        return rows.filter { row in
            guard let val = row.properties[prop.name] else { return columnId == "__none__" }
            if case .select(let s) = val {
                return s == columnId
            }
            return columnId == "__none__"
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns, id: \.id) { column in
                    kanbanColumn(column)
                }
            }
            .padding(12)
        }
    }

    private func kanbanColumn(_ column: (id: String, name: String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(rowsForColumn(column.id).count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)

            LazyVStack(spacing: 6) {
                ForEach(rowsForColumn(column.id)) { row in
                    kanbanCard(row)
                        .draggable(row.id) {
                            Text(row.title)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                        }
                }
            }
            .dropDestination(for: String.self) { droppedIds, _ in
                guard let prop = groupProperty else { return false }
                for droppedId in droppedIds {
                    if let idx = rows.firstIndex(where: { $0.id == droppedId }) {
                        let newValue: PropertyValue = column.id == "__none__" ? .empty : .select(column.id)
                        rows[idx].properties[prop.name] = newValue
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

    private func kanbanCard(_ row: DatabaseRow) -> some View {
        Button {
            onOpenRow(row)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                // Show a couple of properties
                let displayProps = schema.properties.prefix(2).filter { $0.type != .select || $0.id != groupProperty?.id }
                ForEach(displayProps) { prop in
                    if let val = row.properties[prop.name], val != .empty {
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
        case .empty: return ""
        }
    }
}
