import Foundation
import BugbookCore

class DatabaseService {
    private let fileManager = FileManager.default
    private let rowStore = RowStore()
    private let indexManager = IndexManager()

    struct DisplayLoadResult {
        let schema: DatabaseSchema
        let rows: [DatabaseRow]
        let needsDiskRefresh: Bool
    }

    private struct FileMetadata: Equatable {
        let fileSize: UInt64
        let modificationDate: Date
    }

    private struct DisplayCacheEntry {
        let schemaMetadata: FileMetadata
        let indexMetadata: FileMetadata
        let indexData: [String: Any]
        let result: DisplayLoadResult
    }

    private static let maxCachedDisplayDatabases = 32
    private static let displayCacheLock = NSLock()
    private static var displayCache: [String: DisplayCacheEntry] = [:]
    private static var displayCacheOrder: [String] = []

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Load Database

    func loadDatabase(at path: String) throws -> (DatabaseSchema, [DatabaseRow]) {
        let schema = try loadSchema(at: path)
        let rows = try loadRows(in: path, schema: schema)
        return (schema, rows)
    }

    func loadDatabaseForDisplay(at path: String) throws -> DisplayLoadResult {
        if let cached = Self.cachedDisplayResult(at: path) {
            return cached
        }

        let schema = try loadSchema(at: path)

        if let indexData = indexManager.loadIndex(at: path),
           let indexedRows = rowsFromIndex(indexData, schema: schema) {
            let result = DisplayLoadResult(
                schema: schema,
                rows: indexedRows,
                needsDiskRefresh: indexManager.isStale(indexData: indexData, dbPath: path)
            )
            Self.cacheDisplayResult(result, at: path, indexData: indexData)
            return result
        }

        let rows = try loadRows(in: path, schema: schema)
        try? updateIndex(rows: rows, schema: schema, at: path)
        let result = DisplayLoadResult(schema: schema, rows: rows, needsDiskRefresh: false)
        Self.cacheDisplayResult(result, at: path)
        return result
    }

    func loadDatabaseFromDiskRefreshingIndex(at path: String) throws -> (DatabaseSchema, [DatabaseRow]) {
        let (schema, rows) = try loadDatabase(at: path)
        try? updateIndex(rows: rows, schema: schema, at: path)
        Self.cacheDisplayResult(
            DisplayLoadResult(schema: schema, rows: rows, needsDiskRefresh: false),
            at: path
        )
        return (schema, rows)
    }

    func preloadDatabaseForDisplay(at path: String) {
        _ = try? loadDatabaseForDisplay(at: path)
    }

    private func loadSchema(at path: String) throws -> DatabaseSchema {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        let data = try Data(contentsOf: URL(fileURLWithPath: schemaPath))
        return try JSONDecoder().decode(DatabaseSchema.self, from: data)
    }

    private static func cachedDisplayResult(at path: String) -> DisplayLoadResult? {
        guard let schemaMetadata = fileMetadata(
            at: (path as NSString).appendingPathComponent("_schema.json")
        ),
              let indexMetadata = fileMetadata(
                at: (path as NSString).appendingPathComponent("_index.json")
              ) else {
            return nil
        }

        displayCacheLock.lock()

        guard let cached = displayCache[path],
              cached.schemaMetadata == schemaMetadata,
              cached.indexMetadata == indexMetadata else {
            displayCache[path] = nil
            displayCacheOrder.removeAll { $0 == path }
            displayCacheLock.unlock()
            return nil
        }

        touchDisplayCacheEntry(path)
        displayCacheLock.unlock()

        let needsDiskRefresh = cached.result.needsDiskRefresh ||
            IndexManager().isStale(indexData: cached.indexData, dbPath: path)
        return DisplayLoadResult(
            schema: cached.result.schema,
            rows: cached.result.rows,
            needsDiskRefresh: needsDiskRefresh
        )
    }

    private static func cacheDisplayResult(
        _ result: DisplayLoadResult,
        at path: String,
        indexData providedIndexData: [String: Any]? = nil
    ) {
        guard let schemaMetadata = fileMetadata(
            at: (path as NSString).appendingPathComponent("_schema.json")
        ),
              let indexMetadata = fileMetadata(
                at: (path as NSString).appendingPathComponent("_index.json")
              ),
              let indexData = providedIndexData ?? IndexManager().loadIndex(at: path) else {
            return
        }

        displayCacheLock.lock()
        defer { displayCacheLock.unlock() }

        displayCache[path] = DisplayCacheEntry(
            schemaMetadata: schemaMetadata,
            indexMetadata: indexMetadata,
            indexData: indexData,
            result: result
        )
        touchDisplayCacheEntry(path)

        while displayCacheOrder.count > maxCachedDisplayDatabases {
            let evictedPath = displayCacheOrder.removeFirst()
            displayCache[evictedPath] = nil
        }
    }

    private static func touchDisplayCacheEntry(_ path: String) {
        displayCacheOrder.removeAll { $0 == path }
        displayCacheOrder.append(path)
    }

    private static func fileMetadata(at path: String) -> FileMetadata? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? NSNumber,
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        return FileMetadata(fileSize: fileSize.uint64Value, modificationDate: modificationDate)
    }

    // MARK: - Save Schema

    func saveSchema(_ schema: DatabaseSchema, at path: String) throws {
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(schema)
        try data.write(to: URL(fileURLWithPath: schemaPath), options: .atomic)
    }

    // MARK: - Save Row

    func saveRow(_ row: DatabaseRow, schema: DatabaseSchema, at dbPath: String) throws {
        try rowStore.saveRow(row, schema: schema, dbPath: dbPath)
    }

    // MARK: - Load Row Body (on demand)

    func loadRowBody(rowId: String, at dbPath: String) -> String {
        rowStore.loadRowBody(rowId: rowId, dbPath: dbPath)
    }

    // MARK: - Create Row

    func createRow(in dbPath: String, schema: DatabaseSchema) throws -> DatabaseRow {
        let now = Date()
        let rowId = RowStore.generateRowId()

        var properties: [String: PropertyValue] = [:]
        // Set default title
        if let titleProp = schema.titleProperty {
            properties[titleProp.id] = .text("")
        }

        let row = DatabaseRow(
            id: rowId,
            properties: properties,
            body: "",
            createdAt: now,
            updatedAt: now
        )
        try rowStore.saveRow(row, schema: schema, dbPath: dbPath)
        try incrementalIndexInsert(row: row, schema: schema, at: dbPath)
        return row
    }

    // MARK: - Delete Row

    func deleteRow(_ rowId: String, in dbPath: String) throws {
        try rowStore.deleteRow(rowId: rowId, dbPath: dbPath)
    }

    // MARK: - Schema Operations

    func addProperty(_ property: PropertyDefinition, to schema: inout DatabaseSchema, at dbPath: String) throws {
        schema.properties.append(property)
        try saveSchema(schema, at: dbPath)
    }

    func updateProperty(_ property: PropertyDefinition, in schema: inout DatabaseSchema, at dbPath: String) throws {
        guard let idx = schema.properties.firstIndex(where: { $0.id == property.id }) else { return }
        schema.properties[idx] = property
        try saveSchema(schema, at: dbPath)
    }

    func deleteProperty(_ propertyId: String, from schema: inout DatabaseSchema, at dbPath: String) throws {
        schema.properties.removeAll { $0.id == propertyId }
        try saveSchema(schema, at: dbPath)
    }

    func renameProperty(_ propertyId: String, to newName: String, in schema: inout DatabaseSchema, rows: inout [DatabaseRow], at dbPath: String) throws {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        schema.properties[idx].name = newName
        try saveSchema(schema, at: dbPath)
        // Row properties are keyed by ID, not name — no row migration needed.
        // But re-save rows so filenames update if the title property was renamed.
        for i in rows.indices {
            try rowStore.saveRow(rows[i], schema: schema, dbPath: dbPath)
        }
    }

    func changePropertyType(_ propertyId: String, to newType: PropertyType, in schema: inout DatabaseSchema, rows: inout [DatabaseRow], at dbPath: String) throws {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        let oldType = schema.properties[idx].type
        schema.properties[idx].type = newType
        // Add empty options for select/multiSelect types
        if newType == .select || newType == .multiSelect {
            if schema.properties[idx].config == nil {
                schema.properties[idx].config = PropertyConfig(options: [])
            } else if schema.properties[idx].config?.options == nil {
                schema.properties[idx].config?.options = []
            }
        }
        // Set up relation config with empty target
        if newType == .relation {
            if schema.properties[idx].config == nil {
                schema.properties[idx].config = PropertyConfig(target: nil)
            }
        }
        // Set up formula config with empty expression
        if newType == .formula {
            if schema.properties[idx].config == nil {
                schema.properties[idx].config = PropertyConfig(formula: "")
            } else if schema.properties[idx].config?.formula == nil {
                schema.properties[idx].config?.formula = ""
            }
        }
        // Set up lookup config
        if newType == .lookup {
            if schema.properties[idx].config == nil {
                schema.properties[idx].config = PropertyConfig(relationPropertyId: nil, targetPropertyId: nil)
            }
        }
        // Set up rollup config
        if newType == .rollup {
            if schema.properties[idx].config == nil {
                schema.properties[idx].config = PropertyConfig(relationPropertyId: nil, targetPropertyId: nil, aggregationFunction: "count")
            }
        }
        try saveSchema(schema, at: dbPath)
        // Convert existing values where possible
        for i in rows.indices {
            if let val = rows[i].properties[propertyId] {
                rows[i].properties[propertyId] = convertValue(val, from: oldType, to: newType)
                try rowStore.saveRow(rows[i], schema: schema, dbPath: dbPath)
            }
        }
    }

    func addSelectOption(_ option: SelectOption, toProperty propertyId: String, in schema: inout DatabaseSchema, at dbPath: String) throws {
        guard let idx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        if schema.properties[idx].config == nil {
            schema.properties[idx].config = PropertyConfig(options: [])
        }
        if schema.properties[idx].config?.options == nil {
            schema.properties[idx].config?.options = []
        }
        schema.properties[idx].config?.options?.append(option)
        try saveSchema(schema, at: dbPath)
    }

    func updateSelectOption(_ optionId: String, name: String?, color: String?, inProperty propertyId: String, in schema: inout DatabaseSchema, at dbPath: String) throws {
        guard let propIdx = schema.properties.firstIndex(where: { $0.id == propertyId }),
              let optIdx = schema.properties[propIdx].config?.options?.firstIndex(where: { $0.id == optionId }) else { return }
        if let name = name {
            schema.properties[propIdx].config?.options?[optIdx].name = name
        }
        if let color = color {
            schema.properties[propIdx].config?.options?[optIdx].color = color
        }
        try saveSchema(schema, at: dbPath)
    }

    func deleteSelectOption(_ optionId: String, fromProperty propertyId: String, in schema: inout DatabaseSchema, rows: inout [DatabaseRow], at dbPath: String) throws {
        guard let propIdx = schema.properties.firstIndex(where: { $0.id == propertyId }) else { return }
        schema.properties[propIdx].config?.options?.removeAll { $0.id == optionId }
        try saveSchema(schema, at: dbPath)
        // Clear this option from any rows that reference it
        for i in rows.indices {
            guard let val = rows[i].properties[propertyId] else { continue }
            switch val {
            case .select(let id) where id == optionId:
                rows[i].properties[propertyId] = .empty
                try rowStore.saveRow(rows[i], schema: schema, dbPath: dbPath)
            case .multiSelect(var ids):
                let before = ids.count
                ids.removeAll { $0 == optionId }
                if ids.count != before {
                    rows[i].properties[propertyId] = ids.isEmpty ? .empty : .multiSelect(ids)
                    try rowStore.saveRow(rows[i], schema: schema, dbPath: dbPath)
                }
            default:
                break
            }
        }
    }

    // MARK: - Private: Value Conversion

    private func convertValue(_ value: PropertyValue, from oldType: PropertyType, to newType: PropertyType) -> PropertyValue {
        let str: String
        switch value {
        case .text(let s): str = s
        case .number(let n): str = n == n.rounded() ? String(Int(n)) : String(n)
        case .select(let s): str = s
        case .multiSelect(let arr): str = arr.joined(separator: ", ")
        case .date(let s): str = s
        case .checkbox(let b): str = b ? "true" : "false"
        case .url(let s): str = s
        case .email(let s): str = s
        case .relation(let s): str = s
        case .relationMany(let arr): str = arr.joined(separator: ", ")
        case .empty: return .empty
        }

        switch newType {
        case .title, .text: return .text(str)
        case .number: return .number(Double(str) ?? 0)
        case .checkbox: return .checkbox(str == "true" || str == "1")
        case .date: return .date(str)
        case .url: return .url(str)
        case .email: return .email(str)
        case .select: return .text(str)
        case .multiSelect: return .text(str)
        case .relation: return .relation(str)
        case .formula: return .empty
        case .lookup: return .empty
        case .rollup: return .empty
        }
    }

    func reorderProperties(_ orderedIds: [String], in schema: inout DatabaseSchema, at dbPath: String) throws {
        let byId = Dictionary(uniqueKeysWithValues: schema.properties.map { ($0.id, $0) })
        schema.properties = orderedIds.compactMap { byId[$0] }
        try saveSchema(schema, at: dbPath)
    }

    // MARK: - View Operations

    func addView(_ view: ViewConfig, to schema: inout DatabaseSchema, at dbPath: String) throws {
        schema.views.append(view)
        try saveSchema(schema, at: dbPath)
    }

    func updateView(_ view: ViewConfig, in schema: inout DatabaseSchema, at dbPath: String) throws {
        guard let idx = schema.views.firstIndex(where: { $0.id == view.id }) else { return }
        schema.views[idx] = view
        try saveSchema(schema, at: dbPath)
    }

    func deleteView(_ viewId: String, from schema: inout DatabaseSchema, at dbPath: String) throws {
        schema.views.removeAll { $0.id == viewId }
        if schema.defaultView == viewId, let first = schema.views.first {
            schema.defaultView = first.id
        }
        try saveSchema(schema, at: dbPath)
    }

    func setDefaultView(_ viewId: String, in schema: inout DatabaseSchema, at dbPath: String) throws {
        schema.defaultView = viewId
        try saveSchema(schema, at: dbPath)
    }

    // MARK: - Update Index

    func updateIndex(rows: [DatabaseRow], schema: DatabaseSchema, at dbPath: String) throws {
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: rows)
        try indexManager.saveIndex(index, at: dbPath)
    }

    // MARK: - Incremental Index Updates

    /// Insert a single row into the existing index without a full reload.
    private func incrementalIndexInsert(row: DatabaseRow, schema: DatabaseSchema, at dbPath: String) throws {
        try mutateIndex(at: dbPath) { rowsMap, indexes in
            rowsMap[row.id] = indexManager.buildRowEntry(row: row, schema: schema, dbPath: dbPath)
            addToReverseIndexes(row: row, schema: schema, indexes: &indexes)
        }
    }

    /// Update a single row in the existing index without a full reload.
    func incrementalIndexUpdate(row: DatabaseRow, schema: DatabaseSchema, at dbPath: String) throws {
        try mutateIndex(at: dbPath) { rowsMap, indexes in
            removeFromReverseIndexes(rowId: row.id, indexes: &indexes)
            rowsMap[row.id] = indexManager.buildRowEntry(row: row, schema: schema, dbPath: dbPath)
            addToReverseIndexes(row: row, schema: schema, indexes: &indexes)
        }
    }

    /// Remove a single row from the existing index without a full reload.
    func incrementalIndexDelete(rowId: String, schema: DatabaseSchema, at dbPath: String) throws {
        try mutateIndex(at: dbPath) { rowsMap, indexes in
            rowsMap.removeValue(forKey: rowId)
            removeFromReverseIndexes(rowId: rowId, indexes: &indexes)
        }
    }

    /// Load the index, apply a mutation to its rows and indexes, then save.
    private func mutateIndex(
        at dbPath: String,
        body: (inout [String: Any], inout [String: [String: [String]]]) -> Void
    ) throws {
        var index = indexManager.loadIndex(at: dbPath) ?? [:]
        var rowsMap = index["rows"] as? [String: Any] ?? [:]
        var indexes = index["indexes"] as? [String: [String: [String]]] ?? [:]

        body(&rowsMap, &indexes)

        index["rows"] = rowsMap
        index["indexes"] = indexes
        index["updated_at"] = Self.isoFormatter.string(from: Date())
        index["version"] = 1
        try indexManager.saveIndex(index, at: dbPath)
    }

    private func addToReverseIndexes(row: DatabaseRow, schema: DatabaseSchema, indexes: inout [String: [String: [String]]]) {
        let indexedTypes: Set<PropertyType> = [.select, .multiSelect, .relation, .checkbox]
        for prop in schema.properties where indexedTypes.contains(prop.type) {
            guard let val = row.properties[prop.id] else { continue }
            switch val {
            case .select(let optId):
                indexes[prop.id, default: [:]][optId, default: []].append(row.id)
            case .multiSelect(let optIds):
                for optId in optIds {
                    indexes[prop.id, default: [:]][optId, default: []].append(row.id)
                }
            case .relation(let rid):
                indexes[prop.id, default: [:]][rid, default: []].append(row.id)
            case .relationMany(let rids):
                for rid in rids {
                    indexes[prop.id, default: [:]][rid, default: []].append(row.id)
                }
            case .checkbox(let b):
                indexes[prop.id, default: [:]][b ? "true" : "false", default: []].append(row.id)
            default:
                break
            }
        }
    }

    private func removeFromReverseIndexes(rowId: String, indexes: inout [String: [String: [String]]]) {
        for (propId, propIndex) in indexes {
            var updated = propIndex
            for (key, rowIds) in propIndex {
                let filtered = rowIds.filter { $0 != rowId }
                if filtered.isEmpty {
                    updated.removeValue(forKey: key)
                } else if filtered.count != rowIds.count {
                    updated[key] = filtered
                }
            }
            indexes[propId] = updated
        }
    }

    // MARK: - Private: Load Rows From Index

    private func rowsFromIndex(_ indexData: [String: Any], schema: DatabaseSchema) -> [DatabaseRow]? {
        guard let rowsMap = indexData["rows"] as? [String: [String: Any]] else { return nil }

        return rowsMap.compactMap { rowId, rowData -> DatabaseRow? in
            let rawProperties = rowData["properties"] as? [String: Any] ?? [:]
            var properties: [String: PropertyValue] = [:]
            properties.reserveCapacity(rawProperties.count)

            for property in schema.properties {
                guard let rawValue = rawProperties[property.id],
                      let value = indexedPropertyValue(rawValue, type: property.type) else {
                    continue
                }
                properties[property.id] = value
            }

            return DatabaseRow(
                id: rowId,
                properties: properties,
                body: "",
                createdAt: indexedDate(rowData["created_at"]),
                updatedAt: indexedDate(rowData["updated_at"])
            )
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    private func indexedDate(_ raw: Any?) -> Date {
        guard let string = raw as? String,
              let date = Self.isoFormatter.date(from: string) else {
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private func indexedPropertyValue(_ raw: Any, type: PropertyType) -> PropertyValue? {
        if raw is NSNull { return .empty }

        switch type {
        case .title, .text:
            return stringFromIndexedValue(raw).map(PropertyValue.text)
        case .number:
            return numberFromIndexedValue(raw).map(PropertyValue.number)
        case .select:
            return stringFromIndexedValue(raw).map(PropertyValue.select)
        case .multiSelect:
            return stringArrayFromIndexedValue(raw).map(PropertyValue.multiSelect)
        case .date:
            return stringFromIndexedValue(raw).map(PropertyValue.date)
        case .checkbox:
            return boolFromIndexedValue(raw).map(PropertyValue.checkbox)
        case .url:
            return stringFromIndexedValue(raw).map(PropertyValue.url)
        case .email:
            return stringFromIndexedValue(raw).map(PropertyValue.email)
        case .relation:
            if let values = stringArrayFromIndexedValue(raw) {
                return .relationMany(values)
            }
            return stringFromIndexedValue(raw).map(PropertyValue.relation)
        case .formula:
            return .empty
        case .lookup, .rollup:
            return stringFromIndexedValue(raw).map(PropertyValue.text)
        }
    }

    private func stringFromIndexedValue(_ raw: Any) -> String? {
        if let string = raw as? String { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }

    private func numberFromIndexedValue(_ raw: Any) -> Double? {
        if let number = raw as? NSNumber { return number.doubleValue }
        if let string = raw as? String { return Double(string) }
        return nil
    }

    private func boolFromIndexedValue(_ raw: Any) -> Bool? {
        if let bool = raw as? Bool { return bool }
        if let string = raw as? String {
            switch string.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private func stringArrayFromIndexedValue(_ raw: Any) -> [String]? {
        if let strings = raw as? [String] { return strings }
        if let array = raw as? [Any] {
            return array.compactMap { stringFromIndexedValue($0) }
        }
        return nil
    }

    // MARK: - Private: Load Rows (with legacy repair)

    private func loadRows(in dbPath: String, schema: DatabaseSchema) throws -> [DatabaseRow] {
        // Delegate to RowStore for loading and duplicate cleanup, then apply legacy repair.
        let detailed = rowStore.loadAllRowsDetailed(in: dbPath, schema: schema)

        var rows: [DatabaseRow] = []
        var repairedRows: [DatabaseRow] = []

        for entry in detailed {
            let repaired = repairLegacyProperties(
                in: entry.row.properties,
                rawProperties: entry.rawProperties,
                schema: schema
            )
            let row = DatabaseRow(
                id: entry.row.id,
                properties: repaired.properties,
                body: entry.row.body,
                createdAt: entry.row.createdAt,
                updatedAt: entry.row.updatedAt
            )
            rows.append(row)
            if repaired.repaired {
                repairedRows.append(row)
            }
        }

        // If we repaired legacy properties during load, persist the mapped values.
        if !repairedRows.isEmpty {
            for row in repairedRows {
                try? rowStore.saveRow(row, schema: schema, dbPath: dbPath)
            }
            try? updateIndex(rows: rows, schema: schema, at: dbPath)
        }

        return rows
    }

    // MARK: - Legacy Property Repair

    private func repairLegacyProperties(
        in properties: [String: PropertyValue],
        rawProperties: [String: String],
        schema: DatabaseSchema
    ) -> (properties: [String: PropertyValue], repaired: Bool) {
        var repairedProps = properties
        var didRepair = false

        if let titleProp = schema.titleProperty,
           !hasMeaningfulValue(repairedProps[titleProp.id]),
           let inferredTitle = inferLegacyTitle(from: rawProperties) {
            repairedProps[titleProp.id] = .text(inferredTitle)
            didRepair = true
        }

        if let statusProp = schema.properties.first(where: { $0.type == .select }),
           !hasMeaningfulValue(repairedProps[statusProp.id]),
           let optionId = inferLegacySelectOption(for: statusProp, from: rawProperties) {
            repairedProps[statusProp.id] = .select(optionId)
            didRepair = true
        }

        if let tagsProp = schema.properties.first(where: { $0.type == .multiSelect }),
           !hasMeaningfulValue(repairedProps[tagsProp.id]),
           let rawMultiSelect = inferLegacyMultiSelect(from: rawProperties) {
            let parsed = parsePropertyValue(rawMultiSelect, type: .multiSelect)
            if hasMeaningfulValue(parsed) {
                repairedProps[tagsProp.id] = parsed
                didRepair = true
            }
        }

        return (repairedProps, didRepair)
    }

    private func hasMeaningfulValue(_ value: PropertyValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .empty:
            return false
        case .text(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .multiSelect(let values):
            return !values.isEmpty
        case .relationMany(let values):
            return !values.isEmpty
        case .select(let value), .url(let value), .email(let value), .relation(let value):
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .date(let value):
            if let parsed = DatabaseDateValue.decode(from: value) {
                return !parsed.start.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .number:
            return true
        case .checkbox:
            return true
        }
    }

    private func inferLegacyTitle(from rawProperties: [String: String]) -> String? {
        var bestMatch: (score: Int, value: String)?
        for (key, rawValue) in rawProperties {
            guard let candidate = scalarText(from: rawValue), !candidate.isEmpty else { continue }
            if looksLikeIdentifier(candidate) { continue }
            let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedCandidate == "null" || normalizedCandidate == "nil" || normalizedCandidate == "none" {
                continue
            }

            let keyLower = key.lowercased()
            var score = 0
            if keyLower.contains("title") || keyLower.contains("name") { score += 100 }
            if rawValue.trimmingCharacters(in: .whitespaces).hasPrefix("\"") { score += 30 }
            if candidate.contains(" ") { score += 10 }
            if keyLower.contains("status") || keyLower.contains("tag") || keyLower.contains("label") {
                score -= 40
            }

            if let best = bestMatch {
                if score > best.score {
                    bestMatch = (score, candidate)
                }
            } else {
                bestMatch = (score, candidate)
            }
        }
        return bestMatch?.value
    }

    private func inferLegacySelectOption(for property: PropertyDefinition, from rawProperties: [String: String]) -> String? {
        guard let options = property.options, !options.isEmpty else { return nil }

        var candidateValues: [String] = []
        if let exact = rawProperties[property.id] {
            candidateValues.append(exact)
        }
        for (key, value) in rawProperties where key.lowercased().contains("status") {
            candidateValues.append(value)
        }
        for value in rawProperties.values where scalarToken(from: value).hasPrefix("opt_") {
            candidateValues.append(value)
        }

        var seen: Set<String> = []
        let uniqueCandidates = candidateValues.filter { seen.insert($0).inserted }
        for candidate in uniqueCandidates {
            let token = scalarToken(from: candidate)
            guard !token.isEmpty else { continue }

            if let exactMatch = options.first(where: { $0.id == token }) {
                return exactMatch.id
            }
            if let mapped = mapLegacySelectToken(token, options: options) {
                return mapped.id
            }
        }

        return nil
    }

    private func inferLegacyMultiSelect(from rawProperties: [String: String]) -> String? {
        for (key, value) in rawProperties {
            if key.lowercased().contains("status") { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 {
                return trimmed
            }
        }
        return nil
    }

    private func mapLegacySelectToken(_ token: String, options: [SelectOption]) -> SelectOption? {
        let normalizedToken = normalizeStatusToken(token)
        let compactToken = normalizedToken.replacingOccurrences(of: " ", with: "")

        for option in options {
            let normalizedOption = normalizeStatusToken(option.name)
            let compactOption = normalizedOption.replacingOccurrences(of: " ", with: "")
            if normalizedOption == normalizedToken ||
                compactOption == compactToken ||
                compactToken.contains(compactOption) ||
                compactOption.contains(compactToken) {
                return option
            }
        }

        guard let tokenBucket = statusBucket(for: normalizedToken) else { return nil }
        return options.first { option in
            let optionBucket = statusBucket(for: normalizeStatusToken(option.name))
            return optionBucket == tokenBucket
        }
    }

    private func statusBucket(for normalizedValue: String) -> String? {
        let compact = normalizedValue.replacingOccurrences(of: " ", with: "")
        if compact.contains("done") || compact.contains("complete") || compact.contains("closed") {
            return "done"
        }
        if compact.contains("progress") || compact.contains("doing") || compact.contains("active") || compact.contains("review") {
            return "in_progress"
        }
        if compact.contains("todo") || compact.contains("backlog") || compact.contains("notstarted") || compact.contains("queued") {
            return "todo"
        }
        if compact.contains("block") || compact.contains("stuck") {
            return "blocked"
        }
        if compact.contains("cancel") || compact.contains("wontdo") {
            return "cancelled"
        }
        return nil
    }

    private func normalizeStatusToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scalarText(from rawValue: String) -> String? {
        let token = scalarToken(from: rawValue)
        if token.isEmpty { return nil }
        return token
    }

    private func scalarToken(from rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("["), value.hasSuffix("]") {
            return ""
        }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeIdentifier(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("opt_") || lower.hasPrefix("prop_") || lower.hasPrefix("row_") || lower.hasPrefix("db_") {
            return true
        }
        return lower.range(of: "^[a-z0-9_-]{12,}$", options: .regularExpression) != nil
    }

    /// Parse a raw property value string into a PropertyValue (used only for legacy repair).
    private func parsePropertyValue(_ raw: String, type: PropertyType) -> PropertyValue {
        let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if value.isEmpty { return .empty }

        switch type {
        case .title, .text:
            return .text(value)
        case .number:
            return .number(Double(value) ?? 0)
        case .select:
            return .select(value)
        case .multiSelect:
            if value.hasPrefix("[") {
                let items = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                    .filter { !$0.isEmpty }
                return .multiSelect(items)
            }
            return .multiSelect(value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        case .date:
            return .date(value)
        case .checkbox:
            return .checkbox(value == "true")
        case .url:
            return .url(value)
        case .email:
            return .email(value)
        case .relation:
            if value.hasPrefix("[") {
                let items = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                    .filter { !$0.isEmpty }
                return .relationMany(items)
            }
            return .relation(value)
        case .formula:
            return .empty
        case .lookup:
            return .text(value)
        case .rollup:
            return .text(value)
        }
    }
}

enum DatabaseError: Error, LocalizedError {
    case invalidSchema
    case rowNotFound

    var errorDescription: String? {
        switch self {
        case .invalidSchema: return "Invalid database schema"
        case .rowNotFound: return "Database row not found"
        }
    }
}
