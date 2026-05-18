import SwiftUI
import BugbookCore

struct ListView: View {
    let schema: DatabaseSchema
    @Binding var rows: [DatabaseRow]
    let viewConfig: ViewConfig
    var onOpenRow: (DatabaseRow) -> Void
    var onSave: (DatabaseRow) -> Void
    var onNewRow: (() -> Void)?

    @State private var hoveredRowId: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                listRow(row)
            }

            // + New button
            Button {
                onNewRow?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(DatabaseZoomMetrics.font(12))
                    Text("New")
                        .font(DatabaseZoomMetrics.font(15))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DatabaseZoomMetrics.size(6))
            }
            .buttonStyle(.plain)
        }
        .padding(DatabaseZoomMetrics.size(12))
    }

    private func listRow(_ row: DatabaseRow) -> some View {
        let title = row.title(schema: schema)
        return Button {
            onOpenRow(row)
        } label: {
            Text(title.isEmpty ? "Untitled" : title)
                .font(DatabaseZoomMetrics.font(16))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DatabaseZoomMetrics.size(6))
                .padding(.vertical, DatabaseZoomMetrics.size(8))
                .background(
                    RoundedRectangle(cornerRadius: DatabaseZoomMetrics.size(4))
                        .fill(hoveredRowId == row.id ? Color.primary.opacity(0.04) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in hoveredRowId = hovering ? row.id : nil }
    }
}
