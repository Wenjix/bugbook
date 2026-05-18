import XCTest
@testable import Bugbook

final class EditorSaveWorkerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorSaveWorkerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testSaveMarkdownFileWritesOffMainWorker() async throws {
        let path = tempDirectory.appendingPathComponent("Note.md").path
        try "# Old\n".write(toFile: path, atomically: true, encoding: .utf8)

        let worker = EditorSaveWorker()
        let result = await worker.saveMarkdownFile(at: path, content: "# New\n\nBody")

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "# New\n\nBody")
    }

    func testSaveMarkdownFileDoesNotCreateMissingFiles() async {
        let path = tempDirectory.appendingPathComponent("Missing.md").path

        let worker = EditorSaveWorker()
        let result = await worker.saveMarkdownFile(at: path, content: "# New")

        XCTAssertEqual(result, .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testAppendMarkdownToFileAddsTrailingNewlineAndReturnsContent() async throws {
        let path = tempDirectory.appendingPathComponent("Target.md").path
        try "# Target".write(toFile: path, atomically: true, encoding: .utf8)

        let worker = EditorSaveWorker()
        let result = await worker.appendMarkdownToFile(at: path, markdown: "- Moved")

        let expected = "# Target\n- Moved"
        XCTAssertEqual(result, .loaded(EditorLoadedPage(content: expected, isRestoredDraft: false)))
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), expected)
    }

    func testAppendMarkdownToFileReturnsMissingForMissingFile() async {
        let path = tempDirectory.appendingPathComponent("Missing.md").path

        let worker = EditorSaveWorker()
        let result = await worker.appendMarkdownToFile(at: path, markdown: "- Moved")

        XCTAssertEqual(result, .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testPageDraftSaveAndClear() async {
        let draftDirectory = tempDirectory.appendingPathComponent("Drafts", isDirectory: true)
        let draftStore = EditorDraftStore(directoryURL: draftDirectory)
        let worker = EditorSaveWorker(draftStore: draftStore)
        let sourcePath = tempDirectory.appendingPathComponent("Source.md").path

        await worker.savePageDraft(content: "draft", path: sourcePath)
        XCTAssertEqual(draftStore.restorePageDraftIfNewer(path: sourcePath), "draft")

        await worker.clearPageDraft(path: sourcePath)
        XCTAssertNil(draftStore.restorePageDraftIfNewer(path: sourcePath))
    }

    func testLoadPageContentReturnsRestoredDraftWhenNewer() async throws {
        let draftDirectory = tempDirectory.appendingPathComponent("Drafts", isDirectory: true)
        let draftStore = EditorDraftStore(directoryURL: draftDirectory)
        let worker = EditorSaveWorker(draftStore: draftStore)
        let sourcePath = tempDirectory.appendingPathComponent("Source.md").path
        try "# Disk\n".write(toFile: sourcePath, atomically: true, encoding: .utf8)
        await worker.savePageDraft(content: "# Draft\n", path: sourcePath)

        let result = await worker.loadPageContent(at: sourcePath)

        XCTAssertEqual(result, .loaded(EditorLoadedPage(content: "# Draft\n", isRestoredDraft: true)))
    }

    func testLoadPageContentReturnsMissingForMissingFile() async {
        let sourcePath = tempDirectory.appendingPathComponent("Missing.md").path
        let worker = EditorSaveWorker()

        let result = await worker.loadPageContent(at: sourcePath)

        XCTAssertEqual(result, .missing)
    }
}
