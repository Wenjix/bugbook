import XCTest
@testable import Bugbook

final class FileTreeFilterTests: XCTestCase {
    func testEmptyQueryReturnsOriginalTree() {
        let entries = [
            makeFile("Daily Notes.md"),
            makeFolder("Research", children: [makeFile("Parent Interview.md")])
        ]

        XCTAssertEqual(FileTreeFilter.filteredEntries(entries, query: ""), entries)
    }

    func testFuzzyQueryMatchesNestedFilenamesAsFlatResults() {
        let entries = [
            makeFolder("Research", children: [
                makeFile("Parent Interview.md"),
                makeFile("Roadmap.md")
            ]),
            makeFolder("Parent Folder", children: [])
        ]

        let results = FileTreeFilter.filteredEntries(entries, query: "pin")

        XCTAssertEqual(results.map(\.name), ["Parent Interview.md"])
        XCTAssertTrue(results.allSatisfy { $0.children == nil })
    }

    func testRankingPrefersPrefixMatches() {
        let entries = [
            makeFile("Meeting Daily.md"),
            makeFile("Daily Notes.md"),
            makeFile("Work Log.md")
        ]

        let results = FileTreeFilter.filteredEntries(entries, query: "daily")

        XCTAssertEqual(results.map(\.name), ["Daily Notes.md", "Meeting Daily.md"])
    }

    private func makeFile(_ name: String) -> FileEntry {
        FileEntry(
            id: "/tmp/\(name)",
            name: name,
            path: "/tmp/\(name)",
            isDirectory: false
        )
    }

    private func makeFolder(_ name: String, children: [FileEntry]) -> FileEntry {
        FileEntry(
            id: "/tmp/\(name)",
            name: name,
            path: "/tmp/\(name)",
            isDirectory: true,
            children: children
        )
    }
}
