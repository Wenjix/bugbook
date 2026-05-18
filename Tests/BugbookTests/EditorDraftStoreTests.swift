import XCTest
@testable import Bugbook

final class EditorDraftStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        let fileManager = FileManager.default
        for directory in temporaryDirectories {
            try? fileManager.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testRestorePageDraftReturnsDraftWhenNewerThanDisk() throws {
        let (store, directory) = try makeStore()
        let pageURL = directory.appendingPathComponent("Page.md")
        try writeFile(at: pageURL, contents: "disk", modificationDate: Date(timeIntervalSinceNow: -120))

        store.savePageDraft(content: "draft", path: pageURL.path)

        XCTAssertEqual(store.restorePageDraftIfNewer(path: pageURL.path), "draft")
    }

    func testRestorePageDraftReturnsNilWhenDiskIsNewerThanDraft() throws {
        let (store, directory) = try makeStore()
        let pageURL = directory.appendingPathComponent("Page.md")
        try writeFile(at: pageURL, contents: "disk")

        store.savePageDraft(content: "draft", path: pageURL.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 120)],
            ofItemAtPath: pageURL.path
        )

        XCTAssertNil(store.restorePageDraftIfNewer(path: pageURL.path))
    }

    func testClearRowBodyDraftRemovesStoredDraft() throws {
        let (store, directory) = try makeStore()
        let rowFileURL = directory.appendingPathComponent("Row (123).md")
        try writeFile(at: rowFileURL, contents: "disk")

        store.saveRowBodyDraft(
            content: "draft",
            dbPath: directory.path,
            rowId: "row_123",
            rowFilePath: rowFileURL.path
        )
        store.clearRowBodyDraft(dbPath: directory.path, rowId: "row_123")

        XCTAssertNil(
            store.restoreRowBodyDraftIfNewer(
                dbPath: directory.path,
                rowId: "row_123",
                rowFilePath: rowFileURL.path
            )
        )
    }

    private func makeStore() throws -> (EditorDraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return (EditorDraftStore(directoryURL: directory), directory)
    }

    private func writeFile(at url: URL, contents: String, modificationDate: Date? = nil) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if let modificationDate {
            try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)
        }
    }
}
