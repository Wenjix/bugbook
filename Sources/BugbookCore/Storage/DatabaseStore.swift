import Foundation

public class DatabaseStore {
    private let fm = FileManager.default

    public init() {}

    // MARK: - List Databases

    public func listDatabases(in workspacePath: String) -> [DatabaseInfo] {
        var results: [DatabaseInfo] = []
        scanForDatabases(in: workspacePath, results: &results)
        return results
    }

    private func scanForDatabases(in directory: String, results: inout [DatabaseInfo]) {
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else { return }
        for name in contents {
            guard !name.hasPrefix(".") else { continue }
            let fullPath = (directory as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let schemaPath = (fullPath as NSString).appendingPathComponent("_schema.json")
            if fm.fileExists(atPath: schemaPath) {
                if let schema = try? loadSchema(at: fullPath) {
                    let rowCount = countRowFiles(in: fullPath)
                    results.append(DatabaseInfo(id: schema.id, name: schema.name, path: fullPath, rowCount: rowCount))
                }
            }
            // Recurse into subdirectories
            scanForDatabases(in: fullPath, results: &results)
        }
    }

    private func countRowFiles(in dbPath: String) -> Int {
        guard let contents = try? fm.contentsOfDirectory(atPath: dbPath) else { return 0 }
        return contents.filter { $0.hasSuffix(".md") && !$0.hasPrefix("_") }.count
    }

    // MARK: - Load Schema

    public func loadSchema(at dbPath: String) throws -> DatabaseSchema {
        let schemaPath = (dbPath as NSString).appendingPathComponent("_schema.json")
        let data = try Data(contentsOf: URL(fileURLWithPath: schemaPath))
        return try JSONDecoder().decode(DatabaseSchema.self, from: data)
    }

    // MARK: - Save Schema

    public func saveSchema(_ schema: DatabaseSchema, at dbPath: String) throws {
        let schemaPath = (dbPath as NSString).appendingPathComponent("_schema.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(schema)
        try data.write(to: URL(fileURLWithPath: schemaPath), options: .atomic)
    }

    // MARK: - Create Database

    public func createDatabase(in directory: String, name: String, properties: [PropertyDefinition]?) throws -> String {
        let folderPath = (directory as NSString).appendingPathComponent(name)
        try fm.createDirectory(atPath: folderPath, withIntermediateDirectories: true)

        let props: [PropertyDefinition]
        if let provided = properties, !provided.isEmpty {
            props = provided
        } else {
            props = [PropertyDefinition(id: "prop_title", name: "Title", type: .title)]
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let dbId = "db_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))_\(UUID().uuidString.prefix(6).lowercased())"
        let schema = DatabaseSchema(
            id: dbId,
            name: name,
            properties: props,
            views: [
                ViewConfig(id: "view_table", name: "All \(name)", type: .table)
            ],
            defaultView: "view_table",
            createdAt: formatter.string(from: Date())
        )

        try saveSchema(schema, at: folderPath)
        return folderPath
    }
}
