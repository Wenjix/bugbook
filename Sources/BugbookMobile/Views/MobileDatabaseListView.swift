import SwiftUI
import BugbookCore

struct MobileDatabaseListView: View {
    let workspacePath: String

    @State private var databases: [DatabaseInfo] = []

    private let store = DatabaseStore()

    var body: some View {
        NavigationStack {
            Group {
                if databases.isEmpty {
                    ContentUnavailableView("No databases yet", systemImage: "tablecells")
                } else {
                    List(databases, id: \.id) { db in
                        NavigationLink {
                            MobileDatabaseView(dbPath: db.path)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(db.name)
                                        .font(.body).fontWeight(.medium)
                                    Text("\(db.rowCount) row\(db.rowCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Databases")
            .refreshable {
                loadDatabases()
            }
            .onAppear {
                loadDatabases()
            }
        }
    }

    private func loadDatabases() {
        databases = store.listDatabases(in: workspacePath)
    }
}
