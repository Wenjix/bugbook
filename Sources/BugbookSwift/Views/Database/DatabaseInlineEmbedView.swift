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
                            Text(displayValue(row.properties[prop.name] ?? .empty, prop: prop))
                                .lineLimit(1)
                                .frame(width: 100, alignment: .leading)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)

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
}
