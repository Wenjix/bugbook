import XCTest
@testable import Dahso

final class DatabaseEmbedPathResolverTests: XCTestCase {
    private func makeTemporaryWorkspace() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DahsoResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private func writeDatabase(at path: String, name: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let schemaPath = (path as NSString).appendingPathComponent("_schema.json")
        let schema = """
        {"name":"\(name)"}
        """
        try schema.write(toFile: schemaPath, atomically: true, encoding: .utf8)
    }

    func testResolveDatabaseEmbedPathPrefersCurrentPageChildFolder() throws {
        let workspace = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let pagePath = (workspace as NSString).appendingPathComponent("Agent Flow.md")
        let pageContainer = String(pagePath.dropLast(3))
        let movedDatabasePath = (pageContainer as NSString).appendingPathComponent("Agent Tickets")
        try writeDatabase(at: movedDatabasePath, name: "Agent Tickets")

        let stalePath = (workspace as NSString).appendingPathComponent("Agent Tickets/Agent Tickets")
        let resolved = resolveDatabaseEmbedPath(stalePath, pagePath: pagePath, workspacePath: workspace)

        XCTAssertEqual(resolved, movedDatabasePath)
    }

    func testResolveDatabaseEmbedPathFallsBackToUniqueWorkspaceMatchBySchemaName() throws {
        let workspace = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let pagePath = (workspace as NSString).appendingPathComponent("Agent Flow.md")
        let movedDatabasePath = (workspace as NSString)
            .appendingPathComponent("Agent Flow/Untitled Database")
        try writeDatabase(at: movedDatabasePath, name: "Agent Projects")

        let stalePath = (workspace as NSString).appendingPathComponent("Agent Projects")
        let resolved = resolveDatabaseEmbedPath(stalePath, pagePath: pagePath, workspacePath: workspace)

        XCTAssertEqual(resolved, movedDatabasePath)
    }
}
