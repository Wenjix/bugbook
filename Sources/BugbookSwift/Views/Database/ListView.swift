import SwiftUI
import BugbookCore

struct ListView: View {
    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onSave: (DatabaseRow) -> Void

    @State private var editingTitleId: String?
    @State private var editingTitleText: String = ""

    private var hasActiveFiltersOrSorts: Bool {
        !viewConfig.filters.isEmpty || !viewConfig.sorts.isEmpty
    }

    var body: some View {
        ScrollView {
            if rows.count >= 2000 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Large dataset (\(rows.count) rows) - performance may be affected")
                }
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            LazyVStack(spacing: 1) {
                ForEach($rows) { $row in
                    listRow($row)
                }
                .onMove { source, destination in
                    if !hasActiveFiltersOrSorts {
                        rows.move(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            .padding(12)
        }
    }

    private func listRow(_ row: Binding<DatabaseRow>) -> some View {
        let title = row.wrappedValue.title(schema: schema)
        return HStack(spacing: 8) {
            // Drag handle with context menu
            Menu {
                Button(role: .destructive) {
                    rows.removeAll { $0.id == row.wrappedValue.id }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Text("\u{2AF6}")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Title (double-click to edit inline)
            if editingTitleId == row.wrappedValue.id {
                TextField("New Page", text: $editingTitleText, onCommit: {
                    if let titleProp = schema.titleProperty {
                        row.wrappedValue.properties[titleProp.id] = .text(editingTitleText)
                    }
                    onSave(row.wrappedValue)
                    editingTitleId = nil
                })
                .textFieldStyle(.plain)
                .font(.body)
                .fontWeight(.medium)
                .frame(minWidth: 100)
            } else {
                Button {
                    onOpenRow(row.wrappedValue)
                } label: {
                    Text(title.isEmpty ? "New Page" : title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .onTapGesture(count: 2) {
                    editingTitleText = title
                    editingTitleId = row.wrappedValue.id
                }
            }

            Spacer()

            // Property previews (up to 3, excluding title)
            HStack(spacing: 8) {
                ForEach(schema.properties.filter({ $0.type != .title }).prefix(3)) { prop in
                    propertyPreview(value: row.wrappedValue.properties[prop.id] ?? .empty, prop: prop)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .draggable(row.wrappedValue.id) {
            Text(title)
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
        }
    }

    @ViewBuilder
    private func propertyPreview(value: PropertyValue, prop: PropertyDefinition) -> some View {
        switch value {
        case .select(let id):
            if let option = prop.options?.first(where: { $0.id == id }) {
                Text(option.name)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorFromString(option.color).opacity(0.15))
                    .foregroundColor(colorFromString(option.color))
                    .cornerRadius(4)
            }
        case .multiSelect(let ids):
            let matched = ids.compactMap { id in prop.options?.first(where: { $0.id == id }) }
            ForEach(matched.prefix(2)) { option in
                Text(option.name)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorFromString(option.color).opacity(0.15))
                    .foregroundColor(colorFromString(option.color))
                    .cornerRadius(4)
            }
        case .date(let s):
            Text(formattedDate(s))
                .font(.caption)
                .foregroundColor(.secondary)
        case .checkbox(let b):
            Image(systemName: b ? "checkmark.square.fill" : "square")
                .font(.caption)
                .foregroundColor(b ? .accentColor : .secondary)
        case .text(let s) where !s.isEmpty:
            Text(s)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        case .number(let n):
            Text(n == n.rounded() ? String(Int(n)) : String(n))
                .font(.caption)
                .foregroundColor(.secondary)
        case .empty:
            EmptyView()
        default:
            EmptyView()
        }
    }

    private func formattedDate(_ dateString: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inFmt.date(from: dateString) else { return dateString }
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
