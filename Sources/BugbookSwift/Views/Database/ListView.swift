import SwiftUI

struct ListView: View {
    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onSave: (DatabaseRow) -> Void

    @State private var expandedRowId: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach($rows) { $row in
                    listCard($row)
                }
            }
            .padding(12)
        }
    }

    private func listCard(_ row: Binding<DatabaseRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack {
                Button {
                    onOpenRow(row.wrappedValue)
                } label: {
                    Text(row.wrappedValue.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedRowId = expandedRowId == row.wrappedValue.id ? nil : row.wrappedValue.id
                    }
                } label: {
                    Image(systemName: expandedRowId == row.wrappedValue.id ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Inline property editors
            HStack(spacing: 12) {
                ForEach(schema.properties.prefix(4)) { prop in
                    HStack(spacing: 4) {
                        Text(prop.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        let propValue = Binding<PropertyValue>(
                            get: { row.wrappedValue.properties[prop.name] ?? .empty },
                            set: { newVal in
                                row.wrappedValue.properties[prop.name] = newVal
                                onSave(row.wrappedValue)
                            }
                        )
                        PropertyEditorView(definition: prop, value: propValue)
                            .font(.caption)
                    }
                }
            }

            // Expandable body preview
            if expandedRowId == row.wrappedValue.id, !row.wrappedValue.body.isEmpty {
                Text(bodyPreview(row.wrappedValue.body))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(5)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func bodyPreview(_ body: String) -> String {
        // Strip leading heading and return plain text preview
        let lines = body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return lines.prefix(5).joined(separator: "\n")
    }
}
