import SwiftUI

/// Compact database embed for rendering inside a markdown page.
/// Shows a simplified table or list view of the database rows.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
            } else if let schema = schema {
                // Header
                HStack {
                    Button {
                        onOpenDatabase?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tablecells")
                                .font(.caption)
                            Text(schema.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("\(rows.count) rows")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                Divider()

                // Compact table
                compactTable(schema: schema)
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .task {
            await loadData()
        }
    }

    private func compactTable(schema: DatabaseSchema) -> some View {
        let displayProps = Array(schema.properties.prefix(4))

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("Title")
                    .frame(width: 140, alignment: .leading)
                ForEach(displayProps) { prop in
                    Text(prop.name)
                        .frame(width: 100, alignment: .leading)
                }
            }
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Rows
            ForEach(rows.prefix(maxRows)) { row in
                Button {
                    onOpenRow?(row)
                } label: {
                    HStack(spacing: 0) {
                        Text(row.title)
                            .lineLimit(1)
                            .frame(width: 140, alignment: .leading)
                        ForEach(displayProps) { prop in
                            cellContent(row.properties[prop.name] ?? .empty, prop: prop)
                                .frame(width: 100, alignment: .leading)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(hoveredRowId == row.id ? Color.gray.opacity(0.08) : Color.clear)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredRowId = isHovered ? row.id : nil
                }

                if row.id != rows.prefix(maxRows).last?.id {
                    Divider().padding(.leading, 8)
                }
            }

            if rows.count > maxRows {
                Button {
                    onOpenDatabase?()
                } label: {
                    Text("+\(rows.count - maxRows) more rows")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func cellContent(_ value: PropertyValue, prop: PropertyDefinition) -> some View {
        switch value {
        case .select(let id):
            if let option = prop.options?.first(where: { $0.id == id }) {
                Text(option.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(colorFromString(option.color).opacity(0.15))
                    .foregroundColor(colorFromString(option.color))
                    .cornerRadius(3)
            } else {
                Text(id).lineLimit(1)
            }
        case .date(let s):
            Text(formattedDate(s))
                .lineLimit(1)
        case .checkbox(let b):
            Image(systemName: b ? "checkmark.square.fill" : "square")
                .foregroundColor(b ? .accentColor : .secondary)
        default:
            Text(displayValue(value, prop: prop))
                .lineLimit(1)
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
