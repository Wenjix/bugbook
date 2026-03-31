import Foundation
import BugbookCore

/// Scans workspace databases and aggregates summary stats for the Gateway dashboard.
@MainActor
@Observable
class GatewayViewModel {
    struct DatabaseSummary: Identifiable {
        let id: String
        let name: String
        let path: String
        let rowCount: Int
        let statusCounts: [String: Int]  // option name -> count
    }

    struct TicketSummary {
        var total: Int = 0
        var statusCounts: [String: Int] = [:]  // option name -> count
    }

    private(set) var databases: [DatabaseSummary] = []
    private(set) var ticketSummary = TicketSummary()
    private(set) var isLoading = false
    private(set) var recentFiles: [String] = []  // file names

    private let dbStore = DatabaseStore()
    private let dbService = DatabaseService()

    func scan(workspacePath: String) {
        isLoading = true
        let infos = dbStore.listDatabases(in: workspacePath)

        var summaries: [DatabaseSummary] = []
        var aggregateTickets = TicketSummary()

        for info in infos {
            guard let (schema, rows) = try? dbService.loadDatabase(at: info.path) else { continue }

            // Find the first select property (typically "Status")
            var statusCounts: [String: Int] = [:]
            if let statusProp = schema.properties.first(where: { $0.type == .select }),
               let options = statusProp.options {
                let optionMap = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0.name) })
                for row in rows {
                    if case .select(let optId) = row.properties[statusProp.id] {
                        let name = optionMap[optId] ?? optId
                        statusCounts[name, default: 0] += 1
                    } else {
                        statusCounts["No Status", default: 0] += 1
                    }
                }
            }

            summaries.append(DatabaseSummary(
                id: info.id,
                name: info.name,
                path: info.path,
                rowCount: rows.count,
                statusCounts: statusCounts
            ))

            // Aggregate ticket-like databases (ones with status properties)
            if !statusCounts.isEmpty {
                aggregateTickets.total += rows.count
                for (status, count) in statusCounts {
                    aggregateTickets.statusCounts[status, default: 0] += count
                }
            }
        }

        databases = summaries
        ticketSummary = aggregateTickets
        isLoading = false
    }
}
