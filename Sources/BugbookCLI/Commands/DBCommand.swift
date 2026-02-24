import ArgumentParser
import Foundation
import BugbookCore

struct DB: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "db",
        abstract: "Database management commands",
        subcommands: [List.self, Schema.self, CreateDB.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all databases in the workspace"
        )

        @OptionGroup var options: Bugbook.Options

        func run() throws {
            let store = DatabaseStore()
            let databases = store.listDatabases(in: options.resolvedWorkspace)
            let output: [[String: Any]] = databases.map { db in
                [
                    "id": db.id,
                    "name": db.name,
                    "path": db.path,
                    "row_count": db.rowCount,
                ]
            }
            try outputJSON(output)
        }
    }

    struct Schema: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "schema",
            abstract: "Print database schema"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Database name or ID")
        var db: String

        func run() throws {
            let (_, schema) = try resolveDatabase(db, workspace: options.resolvedWorkspace)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(schema)
            if let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        }
    }

    struct CreateDB: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new database from a schema JSON file"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Database name")
        var name: String

        @Option(help: "Path to schema JSON file")
        var schema: String

        func run() throws {
            let schemaPath = (schema as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: schemaPath) else {
                throw CLIError.fileNotFound(schemaPath)
            }

            let data = try Data(contentsOf: URL(fileURLWithPath: schemaPath))
            let dbSchema = try JSONDecoder().decode(DatabaseSchema.self, from: data)

            let store = DatabaseStore()
            let dbDir = (options.resolvedWorkspace as NSString).appendingPathComponent("databases")
            try FileManager.default.createDirectory(atPath: dbDir, withIntermediateDirectories: true)

            let path = try store.createDatabase(in: dbDir, name: name, properties: dbSchema.properties)

            // Save the full schema (with views, etc.) over the default one
            try store.saveSchema(dbSchema, at: path)

            try outputJSON(["path": path, "id": dbSchema.id, "name": dbSchema.name])
        }
    }
}
