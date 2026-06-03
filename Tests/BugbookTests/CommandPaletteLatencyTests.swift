import Foundation
import XCTest
@testable import Bugbook

final class CommandPaletteLatencyTests: XCTestCase {
    private let cacheBuildBudgetMS = 100.0
    private let repeatedSearchBudgetMS = 50.0

    func testCommandPalettePageCacheMeetsLatencyBudgetForLargeWorkspace() {
        let folderCount = 50
        let pagesPerFolder = 100
        let workspacePath = "/tmp/bugbook-command-palette-latency"
        let fileTree = makeFileTree(
            workspacePath: workspacePath,
            folderCount: folderCount,
            pagesPerFolder: pagesPerFolder
        )

        var index = CommandPalettePageSearchIndex.empty
        let buildMS = milliseconds {
            let cache = CommandPalettePageEntry.build(
                from: fileTree,
                workspacePath: workspacePath,
                includeModificationDates: false
            )
            index = CommandPalettePageSearchIndex(entries: cache)
        }

        XCTAssertEqual(index.count, folderCount * pagesPerFolder)
        XCTAssertLessThan(
            buildMS,
            cacheBuildBudgetMS,
            "Opening the workspace launcher should not block on page-cache preparation."
        )

        let queries = ["page 12", "folder 30", "research", "missing result", "page"]
        let searchMS = milliseconds {
            for query in queries {
                _ = index.rankedMatches(query: query, limit: 10)
                    .map(\.fileEntry)
            }
        }

        XCTAssertLessThan(
            searchMS,
            repeatedSearchBudgetMS,
            "Typing in the workspace launcher should keep result recompute below the interactive budget."
        )
    }

    func testCommandPaletteSearchRanksExactAndPrefixMatchesFirst() {
        let workspacePath = "/tmp/bugbook-command-palette-ranking"
        let entries = [
            makeFile(name: "Meeting Daily.md", path: "\(workspacePath)/Meeting Daily.md"),
            makeFile(name: "Daily Notes.md", path: "\(workspacePath)/Daily Notes.md"),
            makeFile(name: "Work Log.md", path: "\(workspacePath)/Work Log.md")
        ]
        let cache = CommandPalettePageEntry.build(
            from: entries,
            workspacePath: workspacePath,
            includeModificationDates: false
        )
        let index = CommandPalettePageSearchIndex(entries: cache)

        let results = index.rankedMatches(query: "daily", limit: 10)

        XCTAssertEqual(results.map(\.displayName), ["Daily Notes", "Meeting Daily"])
    }

    func testCommandPaletteSearchSupportsSubsequenceMatches() {
        let workspacePath = "/tmp/bugbook-command-palette-fuzzy"
        let entries = [
            makeFile(name: "Parent Interview.md", path: "\(workspacePath)/Research/Parent Interview.md"),
            makeFile(name: "Roadmap.md", path: "\(workspacePath)/Research/Roadmap.md")
        ]
        let cache = CommandPalettePageEntry.build(
            from: entries,
            workspacePath: workspacePath,
            includeModificationDates: false
        )
        let index = CommandPalettePageSearchIndex(entries: cache)

        let results = index.rankedMatches(query: "pin", limit: 10)

        XCTAssertEqual(results.map(\.displayName), ["Parent Interview"])
    }

    private func milliseconds(_ work: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        work()
        return (CFAbsoluteTimeGetCurrent() - start) * 1_000
    }

    private func makeFileTree(workspacePath: String, folderCount: Int, pagesPerFolder: Int) -> [FileEntry] {
        (0..<folderCount).map { folderIndex in
            let folderPath = "\(workspacePath)/Folder \(folderIndex)"
            let children = (0..<pagesPerFolder).map { pageIndex in
                let name = "Research Page \(folderIndex)-\(pageIndex).md"
                return FileEntry(
                    id: "\(folderPath)/\(name)",
                    name: name,
                    path: "\(folderPath)/\(name)",
                    isDirectory: false,
                    kind: .page
                )
            }

            return FileEntry(
                id: folderPath,
                name: "Folder \(folderIndex)",
                path: folderPath,
                isDirectory: true,
                kind: .page,
                children: children
            )
        }
    }

    private func makeFile(name: String, path: String) -> FileEntry {
        FileEntry(
            id: path,
            name: name,
            path: path,
            isDirectory: false,
            kind: .page
        )
    }
}
