import ArgumentParser
import Foundation
import DahsoCore

struct DB: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "db",
        abstract: "Database management commands",
        subcommands: [List.self, Schema.self, CreateDB.self, Move.self, DBView.self, Template.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all databases in the workspace"
        )

        @OptionGroup var options: Dahso.Options

        func run() throws {
            let store = DatabaseStore()
            let databases = store.listDatabases(in: options.resolvedWorkspace)
            let output: [[String: Any]] = databases.map { db in
                var json: [String: Any] = [
                    "id": db.id,
                    "name": db.name,
                    "path": db.path,
                    "relative_path": relativePath(from: db.path, workspace: options.resolvedWorkspace),
                    "row_count": db.rowCount,
                ]
                if let parentPage = databaseParentPageInfo(for: db.path, workspace: options.resolvedWorkspace) {
                    json["parent_page"] = parentPage
                }
                return json
            }
            try outputJSON(output)
        }
    }

    struct Schema: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "schema",
            abstract: "Print database schema"
        )

        @OptionGroup var options: Dahso.Options

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

        @OptionGroup var options: Dahso.Options

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

    struct Template: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "template",
            abstract: "Print the body template for a database"
        )

        @OptionGroup var options: Dahso.Options

        @Argument(help: "Database name or ID")
        var db: String

        func run() throws {
            let (dbPath, _) = try resolveDatabase(db, workspace: options.resolvedWorkspace)
            let templatePath = (dbPath as NSString).appendingPathComponent("_template.md")
            if let content = try? String(contentsOfFile: templatePath, encoding: .utf8) {
                FileHandle.standardOutput.write(Data(content.utf8))
            } else {
                throw CLIError.invalidInput("No template found for database")
            }
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move",
            abstract: "Move a database to a new directory or page companion folder and retarget embeds"
        )

        @OptionGroup var options: Dahso.Options

        @Argument(help: "Database name, ID, or path")
        var db: String

        @Option(help: "Relative or absolute workspace directory to move the database into")
        var directory: String?

        @Option(name: .long, help: "Move the database under this page's companion folder")
        var page: String?

        @Flag(name: .long, help: "Preview the move without writing any files")
        var dryRun = false

        func run() throws {
            let output = try moveWorkspaceDatabase(
                query: db,
                workspace: options.resolvedWorkspace,
                destinationDirectory: directory,
                destinationPageQuery: page,
                dryRun: dryRun
            )
            try outputJSON(output)
        }
    }
}
