import XCTest
@testable import Bugbook

@MainActor
final class FileSystemServiceTests: XCTestCase {
    private func makeTemporaryDirectory() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }

    func testMovePageMovesDatabaseFolderAsSingleItem() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let sourceDir = (workspace as NSString).appendingPathComponent("Source")
        let destDir = (workspace as NSString).appendingPathComponent("Parent Page")
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)

        let databasePath = try service.createDatabase(in: sourceDir, name: "Project Board")
        let movedPath = try service.movePage(at: databasePath, toDirectory: destDir)

        XCTAssertEqual(movedPath, (destDir as NSString).appendingPathComponent("Project Board"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databasePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: (movedPath as NSString).appendingPathComponent("_schema.json")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: (movedPath as NSString).appendingPathComponent("_index.json")))
    }

    func testMovePageRejectsMovingDatabaseIntoOwnChildren() throws {
        let service = FileSystemService()
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let databasePath = try service.createDatabase(in: workspace, name: "Project Board")
        let nestedDestination = (databasePath as NSString).appendingPathComponent("Nested")

        XCTAssertThrowsError(try service.movePage(at: databasePath, toDirectory: nestedDestination))
    }
}
