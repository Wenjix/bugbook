import XCTest
@testable import Bugbook

@MainActor
final class BacklinkServiceTests: XCTestCase {
    func testUpdateFileAppliesBacklinkScanAfterAsyncRead() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookBacklinks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceURL = workspace.appendingPathComponent("Source.md")
        try "[[First]]".write(to: sourceURL, atomically: true, encoding: .utf8)

        let service = BacklinkService()
        await service.awaitIndex(workspace: workspace.path)

        XCTAssertEqual(service.backlinksFor(pageName: "First").map(\.sourceName), ["Source"])

        try "[[Second]]".write(to: sourceURL, atomically: true, encoding: .utf8)
        service.updateFile(at: sourceURL.path, in: workspace.path)

        try await waitUntil {
            service.backlinksFor(pageName: "Second").map(\.sourceName) == ["Source"]
        }
        XCTAssertTrue(service.backlinksFor(pageName: "First").isEmpty)
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<50 {
            if predicate() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for predicate", file: file, line: line)
    }
}
