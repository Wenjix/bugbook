import SwiftUI
import BugbookCore

struct MobileDatabaseView: View {
    let dbPath: String

    @State private var schema: DatabaseSchema?
    @State private var rows: [DatabaseRow] = []

    private let dbStore = DatabaseStore()
    private let rowStore = RowStore()

    var body: some View {
        Group {
            if let schema {
                if rows.isEmpty {
                    ContentUnavailableView("No rows yet", systemImage: "doc.text")
                } else {
                    List(rows) { row in
                        NavigationLink {
                            MobileDatabaseRowView(dbPath: dbPath, schema: schema, existingRow: row)
                        } label: {
                            rowLabel(row, schema: schema)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(schema?.name ?? "Database")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            if let schema {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        MobileDatabaseRowView(dbPath: dbPath, schema: schema, existingRow: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .refreshable {
            reload()
        }
        .onAppear {
            reload()
        }
    }

    // MARK: - Row Label

    @ViewBuilder
    private func rowLabel(_ row: DatabaseRow, schema: DatabaseSchema) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title(schema: schema))
                .font(.body).fontWeight(.medium)
                .lineLimit(1)

            let extras = extraProperties(for: row, schema: schema)
            if !extras.isEmpty {
                HStack(spacing: 6) {
                    ForEach(extras, id: \.id) { item in
                        switch item.kind {
                        case .text(let value):
                            Text(value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        case .select(let name, let colorName):
                            Text(name)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colorForName(colorName).opacity(0.15))
                                .foregroundStyle(colorForName(colorName))
                                .clipShape(Capsule())
                        case .checkbox(let checked):
                            Image(systemName: checked ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(checked ? .green : .secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func reload() {
        if let loaded = try? dbStore.loadSchema(at: dbPath) {
            schema = loaded
            rows = rowStore.loadAllRows(in: dbPath, schema: loaded)
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private struct ExtraItem: Identifiable {
        let id: String
        let kind: Kind

        enum Kind {
            case text(String)
            case select(name: String, color: String)
            case checkbox(Bool)
        }
    }

    private func extraProperties(for row: DatabaseRow, schema: DatabaseSchema) -> [ExtraItem] {
        var items: [ExtraItem] = []
        let nonTitleProps = schema.properties.filter { $0.type != .title }

        for prop in nonTitleProps {
            guard let val = row.properties[prop.id], val != .empty else { continue }
            if items.count >= 3 { break }

            switch prop.type {
            case .select:
                if case .select(let optionId) = val,
                   let option = prop.options?.first(where: { $0.id == optionId }) {
                    items.append(ExtraItem(id: prop.id, kind: .select(name: option.name, color: option.color)))
                }
            case .multiSelect:
                if case .multiSelect(let optionIds) = val {
                    for optId in optionIds.prefix(2) {
                        if let option = prop.options?.first(where: { $0.id == optId }) {
                            items.append(ExtraItem(id: "\(prop.id)_\(optId)", kind: .select(name: option.name, color: option.color)))
                        }
                    }
                }
            case .checkbox:
                if case .checkbox(let b) = val {
                    items.append(ExtraItem(id: prop.id, kind: .checkbox(b)))
                }
            default:
                let str = val.stringValue
                if !str.isEmpty {
                    items.append(ExtraItem(id: prop.id, kind: .text("\(prop.name): \(str)")))
                }
            }
        }
        return items
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
