import ArgumentParser
import Foundation
import BugbookCore

struct DBView: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "Manage database views",
        subcommands: [List.self, Add.self, Update.self, Delete.self, SetDefault.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List views for a database"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Database name, ID, or path")
        var db: String

        func run() throws {
            let (_, schema) = try resolveDatabase(db, workspace: options.resolvedWorkspace)
            let output = schema.views.map { viewJSON($0, schema: schema) }
            try outputJSON(output)
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add a view to a database"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Database name, ID, or path")
        var db: String

        @Option(name: .long, help: "View type: table, list, calendar, kanban")
        var type: String

        @Option(name: .long, help: "View name")
        var name: String?

        @Option(name: .long, help: "Group-by property ID or name for kanban")
        var groupBy: String?

        @Option(name: .long, help: "Date property ID or name for calendar")
        var dateProperty: String?

        @Flag(name: .long, help: "Set this as the default view")
        var setDefault: Bool = false

        func run() throws {
            let output = try addDatabaseView(
                dbQuery: db,
                typeQuery: type,
                name: name,
                groupByQuery: groupBy,
                datePropertyQuery: dateProperty,
                setDefault: setDefault,
                workspace: options.resolvedWorkspace
            )
            try outputJSON(output)
        }
    }

    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Update an existing database view"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Database name, ID, or path")
        var db: String

        @Argument(help: "View ID or exact view name")
        var view: String

        @Option(name: .long, help: "New view type: table, list, calendar, kanban")
        var type: String?

        @Option(name: .long, help: "New view name")
        var name: String?

        @Option(name: .long, help: "Group-by property ID or name for kanban")
        var groupBy: String?

        @Option(name: .long, help: "Date property ID or name for calendar")
        var dateProperty: String?

        @Flag(name: .long, help: "Clear the kanban group-by property")
        var clearGroupBy: Bool = false

        @Flag(name: .long, help: "Clear the calendar date property")
        var clearDateProperty: Bool = false

        @Flag(name: .long, help: "Set this as the default view")
        var setDefault: Bool = false

        func run() throws {
            let output = try updateDatabaseView(
                dbQuery: db,
                viewQuery: view,
                typeQuery: type,
                name: name,
                groupByQuery: groupBy,
                datePropertyQuery: dateProperty,
                clearGroupBy: clearGroupBy,
                clearDateProperty: clearDateProperty,
                setDefault: setDefault,
                workspace: options.resolvedWorkspace
            )
            try outputJSON(output)
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a database view"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Database name, ID, or path")
        var db: String

        @Argument(help: "View ID or exact view name")
        var view: String

        func run() throws {
            let output = try deleteDatabaseView(
                dbQuery: db,
                viewQuery: view,
                workspace: options.resolvedWorkspace
            )
            try outputJSON(output)
        }
    }

    struct SetDefault: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-default",
            abstract: "Set the default view for a database"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Database name, ID, or path")
        var db: String

        @Argument(help: "View ID or exact view name")
        var view: String

        func run() throws {
            let output = try setDefaultDatabaseView(
                dbQuery: db,
                viewQuery: view,
                workspace: options.resolvedWorkspace
            )
            try outputJSON(output)
        }
    }
}

private func addDatabaseView(
    dbQuery: String,
    typeQuery: String,
    name: String?,
    groupByQuery: String?,
    datePropertyQuery: String?,
    setDefault: Bool,
    workspace: String
) throws -> [String: Any] {
    let (dbPath, schema) = try resolveDatabase(dbQuery, workspace: workspace)
    var nextSchema = schema
    let type = try parseViewType(typeQuery)
    let defaultName = defaultDatabaseViewName(for: type)

    let view = try configuredView(
        id: "view_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))",
        existing: nil,
        type: type,
        name: name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? defaultName,
        schema: nextSchema,
        groupByQuery: groupByQuery,
        datePropertyQuery: datePropertyQuery,
        clearGroupBy: false,
        clearDateProperty: false
    )

    nextSchema.views.append(view)
    if setDefault {
        nextSchema.defaultView = view.id
    }

    try DatabaseStore().saveSchema(nextSchema, at: dbPath)
    return [
        "added": true,
        "database": nextSchema.name,
        "view": viewJSON(view, schema: nextSchema),
    ]
}

private func updateDatabaseView(
    dbQuery: String,
    viewQuery: String,
    typeQuery: String?,
    name: String?,
    groupByQuery: String?,
    datePropertyQuery: String?,
    clearGroupBy: Bool,
    clearDateProperty: Bool,
    setDefault: Bool,
    workspace: String
) throws -> [String: Any] {
    let (dbPath, schema) = try resolveDatabase(dbQuery, workspace: workspace)
    var nextSchema = schema
    let (index, existing) = try resolveView(viewQuery, in: nextSchema)

    let type = try typeQuery.map(parseViewType) ?? existing.type
    let nextName = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? existing.name

    let updated = try configuredView(
        id: existing.id,
        existing: existing,
        type: type,
        name: nextName,
        schema: nextSchema,
        groupByQuery: groupByQuery,
        datePropertyQuery: datePropertyQuery,
        clearGroupBy: clearGroupBy,
        clearDateProperty: clearDateProperty
    )

    nextSchema.views[index] = updated
    if setDefault {
        nextSchema.defaultView = updated.id
    }

    try DatabaseStore().saveSchema(nextSchema, at: dbPath)
    return [
        "updated": true,
        "database": nextSchema.name,
        "view": viewJSON(updated, schema: nextSchema),
    ]
}

private func deleteDatabaseView(
    dbQuery: String,
    viewQuery: String,
    workspace: String
) throws -> [String: Any] {
    let (dbPath, schema) = try resolveDatabase(dbQuery, workspace: workspace)
    var nextSchema = schema
    let (_, view) = try resolveView(viewQuery, in: nextSchema)

    guard nextSchema.views.count > 1 else {
        throw CLIError.invalidInput("Cannot delete the last remaining view")
    }

    nextSchema.views.removeAll { $0.id == view.id }
    if nextSchema.defaultView == view.id, let first = nextSchema.views.first {
        nextSchema.defaultView = first.id
    }

    try DatabaseStore().saveSchema(nextSchema, at: dbPath)
    return [
        "deleted": true,
        "database": nextSchema.name,
        "view_id": view.id,
        "default_view": nextSchema.defaultView,
    ]
}

private func setDefaultDatabaseView(
    dbQuery: String,
    viewQuery: String,
    workspace: String
) throws -> [String: Any] {
    let (dbPath, schema) = try resolveDatabase(dbQuery, workspace: workspace)
    var nextSchema = schema
    let (_, view) = try resolveView(viewQuery, in: nextSchema)
    nextSchema.defaultView = view.id
    try DatabaseStore().saveSchema(nextSchema, at: dbPath)

    return [
        "updated": true,
        "database": nextSchema.name,
        "default_view": viewJSON(view, schema: nextSchema),
    ]
}

private func configuredView(
    id: String,
    existing: ViewConfig?,
    type: ViewType,
    name: String,
    schema: DatabaseSchema,
    groupByQuery: String?,
    datePropertyQuery: String?,
    clearGroupBy: Bool,
    clearDateProperty: Bool
) throws -> ViewConfig {
    var groupBy = existing?.groupBy
    var dateProperty = existing?.dateProperty

    switch type {
    case .kanban:
        if clearGroupBy {
            groupBy = nil
        }
        if let groupByQuery {
            groupBy = try resolveProperty(groupByQuery, in: schema, allowedTypes: [.select, .multiSelect]).id
        } else if groupBy == nil {
            groupBy = schema.properties.first(where: { $0.type == .select || $0.type == .multiSelect })?.id
        }
        dateProperty = nil

    case .calendar:
        if clearDateProperty {
            dateProperty = nil
        }
        if let datePropertyQuery {
            dateProperty = try resolveProperty(datePropertyQuery, in: schema, allowedTypes: [.date]).id
        } else if dateProperty == nil {
            dateProperty = schema.properties.first(where: { $0.type == .date })?.id
        }
        groupBy = nil

    case .table, .list:
        groupBy = nil
        dateProperty = nil
    }

    if type == .kanban, groupBy == nil {
        throw CLIError.invalidInput("Kanban views require a select or multi-select property. Use --group-by.")
    }
    if type == .calendar, dateProperty == nil {
        throw CLIError.invalidInput("Calendar views require a date property. Use --date-property.")
    }

    return ViewConfig(
        id: id,
        name: name,
        type: type,
        sorts: existing?.sorts ?? [],
        filters: existing?.filters ?? [],
        columnWidths: existing?.columnWidths,
        hiddenColumns: existing?.hiddenColumns,
        groupBy: groupBy,
        dateProperty: dateProperty
    )
}

private func resolveView(_ query: String, in schema: DatabaseSchema) throws -> (Int, ViewConfig) {
    let matches = schema.views.enumerated().filter { _, view in
        view.id.caseInsensitiveCompare(query) == .orderedSame
            || view.name.caseInsensitiveCompare(query) == .orderedSame
    }

    if matches.count == 1, let match = matches.first {
        return match
    }

    if matches.isEmpty {
        throw CLIError.invalidInput("View not found: \(query)")
    }

    let options = matches.map { $0.element.name }.joined(separator: ", ")
    throw CLIError.invalidInput("View reference is ambiguous: \(query). Matches: \(options)")
}

private func parseViewType(_ raw: String) throws -> ViewType {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == "board" {
        return .kanban
    }
    guard let type = ViewType(rawValue: normalized) else {
        throw CLIError.invalidInput("Unsupported view type: \(raw)")
    }
    return type
}

private func resolveProperty(
    _ query: String,
    in schema: DatabaseSchema,
    allowedTypes: Set<PropertyType>
) throws -> PropertyDefinition {
    let matches = schema.properties.filter { property in
        property.id.caseInsensitiveCompare(query) == .orderedSame
            || property.name.caseInsensitiveCompare(query) == .orderedSame
    }

    guard matches.count == 1, let property = matches.first else {
        if matches.isEmpty {
            throw CLIError.invalidInput("Property not found: \(query)")
        }
        let options = matches.map(\.name).joined(separator: ", ")
        throw CLIError.invalidInput("Property reference is ambiguous: \(query). Matches: \(options)")
    }

    guard allowedTypes.contains(property.type) else {
        let expected = allowedTypes.map(\.rawValue).sorted().joined(separator: ", ")
        throw CLIError.invalidInput("Property \(property.name) must be one of: \(expected)")
    }

    return property
}

private func viewJSON(_ view: ViewConfig, schema: DatabaseSchema) -> [String: Any] {
    var json: [String: Any] = [
        "id": view.id,
        "name": view.name,
        "type": view.type.rawValue,
        "is_default": schema.defaultView == view.id,
    ]

    if let groupBy = view.groupBy {
        json["group_by"] = groupBy
        if let property = schema.properties.first(where: { $0.id == groupBy }) {
            json["group_by_name"] = property.name
        }
    }

    if let dateProperty = view.dateProperty {
        json["date_property"] = dateProperty
        if let property = schema.properties.first(where: { $0.id == dateProperty }) {
            json["date_property_name"] = property.name
        }
    }

    json["filter_count"] = view.filters.count
    json["sort_count"] = view.sorts.count
    return json
}

private func defaultDatabaseViewName(for type: ViewType) -> String {
    switch type {
    case .kanban: return "Board"
    case .table: return "Table"
    case .list: return "List"
    case .calendar: return "Calendar"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
