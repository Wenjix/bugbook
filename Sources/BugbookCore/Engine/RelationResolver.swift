import Foundation

public struct RelationResolver {

    /// Enrich rows by resolving relation properties to include related row titles.
    /// Best-effort: if target DB or row not found, leaves as-is.
    public static func resolve(rows: [DatabaseRow], relationProperties: [String],
                               fields: [String]?, dbStore: DatabaseStore,
                               workspacePath: String) -> [DatabaseRow] {
        if relationProperties.isEmpty { return rows }

        // Build a cache of database indexes: dbPath -> (schema, indexRows)
        let databases = dbStore.listDatabases(in: workspacePath)
        var titleCache: [String: String] = [:] // rowId -> title

        // Pre-load all database indexes for lookups
        let indexManager = IndexManager()
        var dbIndexes: [(schema: DatabaseSchema, indexData: [String: Any])] = []
        for db in databases {
            if let schema = try? dbStore.loadSchema(at: db.path),
               let indexData = indexManager.loadIndex(at: db.path) {
                dbIndexes.append((schema, indexData))
            }
        }

        return rows.map { row in
            var enriched = row
            for propId in relationProperties {
                guard let value = row.properties[propId] else { continue }

                let relatedIds: [String]
                switch value {
                case .relation(let id):
                    relatedIds = [id]
                case .relationMany(let ids):
                    relatedIds = ids
                default:
                    continue
                }

                let titles = relatedIds.compactMap { rowId -> String? in
                    if let cached = titleCache[rowId] { return cached }
                    let title = lookupTitle(rowId: rowId, dbIndexes: dbIndexes)
                    if let title = title { titleCache[rowId] = title }
                    return title
                }

                if !titles.isEmpty {
                    enriched.properties[propId + "_resolved"] = .text(titles.joined(separator: ", "))
                }
            }
            return enriched
        }
    }

    private static func lookupTitle(rowId: String, dbIndexes: [(schema: DatabaseSchema, indexData: [String: Any])]) -> String? {
        for (schema, indexData) in dbIndexes {
            guard let rows = indexData["rows"] as? [String: [String: Any]],
                  let rowData = rows[rowId],
                  let props = rowData["properties"] as? [String: Any],
                  let titleProp = schema.titleProperty,
                  let titleVal = props[titleProp.id] as? String else {
                continue
            }
            return titleVal
        }
        return nil
    }
}
