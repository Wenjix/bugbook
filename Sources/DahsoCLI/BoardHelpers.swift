import Foundation
import DahsoCore

func createWorkspaceBoard(
    name: String,
    workspace: String,
    directory: String = "databases",
    groupName: String = "Status",
    columns: [String] = [],
    extraViews: [String] = [],
    includeDefaultTableView: Bool = true,
    datePropertyName: String = "Date",
    embedInPage: String? = nil
) throws -> [String: Any] {
    let normalizedWorkspace = normalizePath(workspace)
    let normalizedDirectory = try normalizeWorkspaceDirectory(directory, workspace: normalizedWorkspace)
    let boardPath = try createDatabaseFolder(
        name: name,
        directory: normalizedDirectory,
        workspace: normalizedWorkspace
    )

    let createdAt = iso8601String(from: Date())
    let groupPropertyName = normalizedBoardGroupName(groupName)
    let groupPropertyId = boardGroupPropertyId(for: groupPropertyName)
    let boardColumns = buildBoardColumns(columns)
    let viewTypes = try resolvedBoardViewTypes(extraViews, includeDefaultTableView: includeDefaultTableView)

    var properties: [PropertyDefinition] = [
        PropertyDefinition(id: "prop_title", name: "Title", type: .title),
        PropertyDefinition(
            id: groupPropertyId,
            name: groupPropertyName,
            type: .select,
            config: PropertyConfig(options: boardColumns)
        ),
    ]

    var calendarDatePropertyId: String?
    if viewTypes.contains(.calendar) {
        let datePropertyId = uniquePropertyId(
            preferredName: normalizedBoardDatePropertyName(datePropertyName),
            used: Set(properties.map(\.id))
        )
        calendarDatePropertyId = datePropertyId
        properties.append(
            PropertyDefinition(
                id: datePropertyId,
                name: normalizedBoardDatePropertyName(datePropertyName),
                type: .date
            )
        )
    }

    let boardViews = buildBoardViews(
        viewTypes: viewTypes,
        groupPropertyId: groupPropertyId,
        datePropertyId: calendarDatePropertyId
    )

    let schema = DatabaseSchema(
        id: "db_\(slugifiedIdentifier(name, fallback: "board"))_\(randomIdentifierSuffix())",
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        version: 1,
        properties: properties,
        views: boardViews,
        defaultView: boardViews.first(where: { $0.type == .kanban })?.id ?? boardViews.first?.id ?? "view_\(randomIdentifierSuffix())",
        createdAt: createdAt
    )

    let store = DatabaseStore()
    try store.saveSchema(schema, at: boardPath)

    let indexManager = IndexManager()
    try indexManager.saveIndex(emptyIndex(updatedAt: createdAt), at: boardPath)

    var output: [String: Any] = [
        "created": true,
        "path": boardPath,
        "name": schema.name,
        "id": schema.id,
        "default_view": schema.defaultView,
        "title_property": [
            "id": "prop_title",
            "name": "Title",
            "type": PropertyType.title.rawValue,
        ],
        "group_property": [
            "id": groupPropertyId,
            "name": groupPropertyName,
            "type": PropertyType.select.rawValue,
        ],
        "columns": boardColumns.map { option in
            [
                "id": option.id,
                "name": option.name,
                "color": option.color,
            ]
        },
        "views": schema.views.map { view in
            var json: [String: Any] = [
                "id": view.id,
                "name": view.name,
                "type": view.type.rawValue,
            ]
            if let groupBy = view.groupBy {
                json["group_by"] = groupBy
            }
            if let dateProperty = view.dateProperty {
                json["date_property"] = dateProperty
            }
            return json
        },
    ]

    if let embedInPage, !embedInPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        output["embed"] = try embedDatabasePathInPage(
            pageQuery: embedInPage,
            databasePath: boardPath,
            workspace: normalizedWorkspace
        )
    }

    return output
}

func addBoardCard(
    boardQuery: String,
    title: String,
    columnQuery: String?,
    propertyPairs: [String],
    date: String?,
    body: String?,
    workspace: String
) throws -> [String: Any] {
    let context = try resolveBoardContext(boardQuery, workspace: workspace)
    let resolvedColumn = try resolveBoardColumn(columnQuery, context: context)

    var properties = try parseSetValues(propertyPairs, schema: context.schema)
    properties[context.titleProperty.id] = .text(title)

    if let resolvedColumn {
        properties[context.groupProperty.id] = boardColumnValue(
            columnId: resolvedColumn.id,
            groupProperty: context.groupProperty
        )
    }

    if let date, !date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        guard let dateProperty = context.dateProperty else {
            throw CLIError.invalidInput("Board does not have a date property")
        }
        properties[dateProperty.id] = .date(date)
    }

    let errors = SchemaValidator.validate(properties: properties, schema: context.schema, requireTitle: true)
    if !errors.isEmpty {
        let msgs = errors.map(\.description)
        throw CLIError.invalidInput("Validation errors: \(msgs.joined(separator: "; "))")
    }

    let row = DatabaseRow(
        id: RowStore.generateRowId(),
        properties: properties,
        body: body ?? "",
        createdAt: Date(),
        updatedAt: Date()
    )

    try persistRow(row, schema: context.schema, dbPath: context.path)

    var output: [String: Any] = [
        "id": row.id,
        "created": true,
        "board": context.schema.name,
        "board_path": context.path,
        "title": title,
    ]

    if let resolvedColumn {
        output["column"] = [
            "id": resolvedColumn.id,
            "name": resolvedColumn.name,
            "property_id": context.groupProperty.id,
            "property_name": context.groupProperty.name,
        ]
    }

    if let date, let dateProperty = context.dateProperty {
        output["date"] = [
            "property_id": dateProperty.id,
            "property_name": dateProperty.name,
            "value": date,
        ]
    }

    return output
}

func moveBoardCard(
    boardQuery: String,
    rowId: String,
    columnQuery: String,
    workspace: String
) throws -> [String: Any] {
    let context = try resolveBoardContext(boardQuery, workspace: workspace)
    let column = try resolveBoardColumn(columnQuery, context: context)
    guard let row = try loadRow(rowId: rowId, dbPath: context.path, schema: context.schema) else {
        throw CLIError.invalidInput("Row not found: \(rowId)")
    }

    guard let column else {
        throw CLIError.invalidInput("Board has no selectable columns")
    }

    var nextRow = row
    nextRow.properties[context.groupProperty.id] = boardColumnValue(
        columnId: column.id,
        groupProperty: context.groupProperty
    )
    nextRow.updatedAt = Date()

    try persistRow(nextRow, schema: context.schema, dbPath: context.path)

    return [
        "id": rowId,
        "moved": true,
        "board": context.schema.name,
        "board_path": context.path,
        "column": [
            "id": column.id,
            "name": column.name,
            "property_id": context.groupProperty.id,
            "property_name": context.groupProperty.name,
        ],
    ]
}

private struct BoardContext {
    let path: String
    let schema: DatabaseSchema
    let titleProperty: PropertyDefinition
    let groupProperty: PropertyDefinition
    let dateProperty: PropertyDefinition?
}

private func boardColumnValue(columnId: String, groupProperty: PropertyDefinition) -> PropertyValue {
    switch groupProperty.type {
    case .multiSelect:
        return .multiSelect([columnId])
    default:
        return .select(columnId)
    }
}

func normalizeWorkspaceDirectory(_ rawDirectory: String, workspace: String) throws -> String {
    let expanded = (rawDirectory as NSString).expandingTildeInPath
    let path = expanded.hasPrefix("/")
        ? normalizePath(expanded)
        : normalizePath((workspace as NSString).appendingPathComponent(rawDirectory))

    guard isPathInsideWorkspace(path, workspace: workspace) else {
        throw CLIError.invalidInput("Directory must be inside workspace: \(rawDirectory)")
    }

    guard !WorkspacePathRules.shouldIgnoreAbsolutePath(path) else {
        throw CLIError.invalidInput("Directory is not a visible workspace path: \(rawDirectory)")
    }

    return path
}

private func createDatabaseFolder(name: String, directory: String, workspace: String) throws -> String {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
        throw CLIError.invalidInput("Board name cannot be empty")
    }

    let folderName = sanitizeDatabaseFolderName(trimmedName)
    let path = normalizePath((directory as NSString).appendingPathComponent(folderName))

    guard isPathInsideWorkspace(path, workspace: workspace) else {
        throw CLIError.invalidInput("Board path must be inside workspace")
    }
    guard !WorkspacePathRules.shouldIgnoreAbsolutePath(path) else {
        throw CLIError.invalidInput("Board path is not a visible workspace path")
    }
    guard !FileManager.default.fileExists(atPath: path) else {
        throw CLIError.invalidInput("Database already exists at \(path)")
    }

    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

private func buildBoardColumns(_ rawColumns: [String]) -> [SelectOption] {
    let columns = rawColumns
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    let names = columns.isEmpty ? ["Backlog", "In Progress", "Done"] : columns
    let palette = ["gray", "blue", "green", "orange", "purple", "pink", "yellow", "red"]
    var usedIds = Set<String>()

    return names.enumerated().map { index, name in
        let id = uniqueOptionId(for: name, usedIds: &usedIds)
        return SelectOption(id: id, name: name, color: palette[index % palette.count])
    }
}

private func resolvedBoardViewTypes(_ rawViews: [String], includeDefaultTableView: Bool) throws -> [ViewType] {
    var ordered: [ViewType] = [.kanban]
    if includeDefaultTableView {
        ordered.append(.table)
    }

    for raw in rawViews {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { continue }

        let parsed: ViewType
        if normalized == "board" {
            parsed = .kanban
        } else if let value = ViewType(rawValue: normalized) {
            parsed = value
        } else {
            throw CLIError.invalidInput("Unsupported board view: \(raw)")
        }

        if !ordered.contains(parsed) {
            ordered.append(parsed)
        }
    }

    return ordered
}

private func buildBoardViews(
    viewTypes: [ViewType],
    groupPropertyId: String,
    datePropertyId: String?
) -> [ViewConfig] {
    var usedIds = Set<String>()
    return viewTypes.map { type in
        switch type {
        case .kanban:
            return ViewConfig(
                id: uniqueBoardViewId(for: "board", usedIds: &usedIds),
                name: "Board",
                type: .kanban,
                groupBy: groupPropertyId
            )
        case .table:
            return ViewConfig(
                id: uniqueBoardViewId(for: "table", usedIds: &usedIds),
                name: "Table",
                type: .table
            )
        case .list:
            return ViewConfig(
                id: uniqueBoardViewId(for: "list", usedIds: &usedIds),
                name: "List",
                type: .list
            )
        case .calendar:
            return ViewConfig(
                id: uniqueBoardViewId(for: "calendar", usedIds: &usedIds),
                name: "Calendar",
                type: .calendar,
                dateProperty: datePropertyId
            )
        }
    }
}

private func uniqueOptionId(for name: String, usedIds: inout Set<String>) -> String {
    let base = "opt_\(slugifiedIdentifier(name, fallback: "column"))"
    var candidate = base
    var counter = 2

    while !usedIds.insert(candidate).inserted {
        candidate = "\(base)_\(counter)"
        counter += 1
    }

    return candidate
}

private func normalizedBoardGroupName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Status" : trimmed
}

private func normalizedBoardDatePropertyName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Date" : trimmed
}

private func boardGroupPropertyId(for groupName: String) -> String {
    let slug = slugifiedIdentifier(groupName, fallback: "status")
    let candidate = "prop_\(slug)"
    return candidate == "prop_title" ? "prop_status" : candidate
}

private func uniquePropertyId(preferredName: String, used: Set<String>) -> String {
    let base = "prop_\(slugifiedIdentifier(preferredName, fallback: "property"))"
    var candidate = base
    var counter = 2

    while used.contains(candidate) || candidate == "prop_title" {
        candidate = "\(base)_\(counter)"
        counter += 1
    }

    return candidate
}

func sanitizeDatabaseFolderName(_ name: String) -> String {
    let sanitized = name.replacingOccurrences(
        of: "[/\\\\?%*:|\"<>]",
        with: "-",
        options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? "Untitled Board" : sanitized
}

private func slugifiedIdentifier(_ value: String, fallback: String) -> String {
    let slug = value
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return slug.isEmpty ? fallback : slug
}

private func randomIdentifierSuffix() -> String {
    String(UUID().uuidString.prefix(6)).lowercased()
}

private func uniqueBoardViewId(for baseName: String, usedIds: inout Set<String>) -> String {
    let base = "view_\(slugifiedIdentifier(baseName, fallback: "view"))_\(randomIdentifierSuffix())"
    var candidate = base
    var counter = 2

    while !usedIds.insert(candidate).inserted {
        candidate = "\(base)_\(counter)"
        counter += 1
    }

    return candidate
}

private func resolveBoardContext(_ boardQuery: String, workspace: String) throws -> BoardContext {
    let (dbPath, schema) = try resolveDatabase(boardQuery, workspace: workspace)

    guard let titleProperty = schema.titleProperty else {
        throw CLIError.invalidInput("Board is missing a title property")
    }

    let kanbanView = schema.views.first(where: { $0.id == schema.defaultView && $0.type == .kanban })
        ?? schema.views.first(where: { $0.type == .kanban })

    let groupPropertyId = kanbanView?.groupBy
        ?? schema.properties.first(where: { $0.type == .select })?.id

    guard let groupPropertyId,
          let groupProperty = schema.properties.first(where: { $0.id == groupPropertyId }) else {
        throw CLIError.invalidInput("Board does not have a selectable group property")
    }

    let calendarView = schema.views.first(where: { $0.id == schema.defaultView && $0.type == .calendar })
        ?? schema.views.first(where: { $0.type == .calendar })
    let datePropertyId = calendarView?.dateProperty
        ?? schema.properties.first(where: { $0.type == .date })?.id
    let dateProperty = datePropertyId.flatMap { propertyId in
        schema.properties.first(where: { $0.id == propertyId })
    }

    return BoardContext(
        path: dbPath,
        schema: schema,
        titleProperty: titleProperty,
        groupProperty: groupProperty,
        dateProperty: dateProperty
    )
}

private func resolveBoardColumn(_ query: String?, context: BoardContext) throws -> SelectOption? {
    let options = context.groupProperty.options ?? []
    guard !options.isEmpty else {
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIError.invalidInput("Board group property has no configured options")
        }
        return nil
    }

    guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return options.first
    }

    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let match = options.first(where: { $0.id.lowercased() == needle || $0.name.lowercased() == needle }) {
        return match
    }

    let available = options.map(\.name).joined(separator: ", ")
    throw CLIError.invalidInput("Column not found: \(query). Available columns: \(available)")
}

private func persistRow(_ row: DatabaseRow, schema: DatabaseSchema, dbPath: String) throws {
    let rowStore = RowStore()
    try rowStore.saveRow(row, schema: schema, dbPath: dbPath)

    let indexManager = IndexManager()
    let allRows = rowStore.loadAllRows(in: dbPath, schema: schema)
    let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: allRows)
    try indexManager.saveIndex(index, at: dbPath)
}

private func emptyIndex(updatedAt: String) -> [String: Any] {
    [
        "version": 1,
        "updated_at": updatedAt,
        "rows": [:] as [String: Any],
        "indexes": [:] as [String: Any],
    ]
}
