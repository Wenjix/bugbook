import XCTest
@testable import Bugbook

final class DatabaseEmbedPathResolverTests: XCTestCase {
    private func makeTemporaryWorkspace() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookResolverTests-\(UUID().uuidString)", isDirectory: true)
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

    private func missingAbsoluteDatabasePath(named name: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookResolverMissing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .path
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

    func testResolveDatabaseEmbedPathForRenderingMarksMissingPathUnresolved() throws {
        let workspace = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let pagePath = (workspace as NSString).appendingPathComponent("Alignment Zone.md")
        let stalePath = missingAbsoluteDatabasePath(named: "Untitled Database")

        let resolution = resolveDatabaseEmbedPathForRendering(
            stalePath,
            pagePath: pagePath,
            workspacePath: workspace
        )

        XCTAssertEqual(resolution?.renderPath, stalePath)
        XCTAssertEqual(resolution?.unresolvedStoredPath, stalePath)
        XCTAssertEqual(resolution?.isResolved, false)
    }

    func testResolveDatabaseEmbedPathForRenderingKeepsResolvedPathResolved() throws {
        let workspace = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let pagePath = (workspace as NSString).appendingPathComponent("Alignment Zone.md")
        let pageContainer = String(pagePath.dropLast(3))
        let databasePath = (pageContainer as NSString).appendingPathComponent("Untitled Database")
        try writeDatabase(at: databasePath, name: "Untitled Database")

        let stalePath = missingAbsoluteDatabasePath(named: "Untitled Database")
        let resolution = resolveDatabaseEmbedPathForRendering(
            stalePath,
            pagePath: pagePath,
            workspacePath: workspace
        )

        XCTAssertEqual(resolution?.renderPath, databasePath)
        XCTAssertNil(resolution?.unresolvedStoredPath)
        XCTAssertEqual(resolution?.isResolved, true)
    }
}
