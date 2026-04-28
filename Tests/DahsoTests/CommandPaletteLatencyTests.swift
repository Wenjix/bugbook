import Foundation
import XCTest
@testable import Dahso

final class CommandPaletteLatencyTests: XCTestCase {
    private let cacheBuildBudgetMS = 100.0
    private let repeatedSearchBudgetMS = 50.0

    func testCommandPalettePageCacheMeetsLatencyBudgetForLargeWorkspace() {
        let folderCount = 50
        let pagesPerFolder = 100
        let workspacePath = "/tmp/dahso-command-palette-latency"
        let fileTree = makeFileTree(
            workspacePath: workspacePath,
            folderCount: folderCount,
            pagesPerFolder: pagesPerFolder
        )

        var cache: [CommandPalettePageEntry] = []
        let buildMS = milliseconds {
            cache = CommandPalettePageEntry.build(
                from: fileTree,
                workspacePath: workspacePath,
                includeModificationDates: false
            )
        }

        XCTAssertEqual(cache.count, folderCount * pagesPerFolder)
        XCTAssertLessThan(
            buildMS,
            cacheBuildBudgetMS,
            "Opening the workspace launcher should not block on page-cache preparation."
        )

        let queries = ["page 12", "folder 30", "research", "missing result", "page"]
        let searchMS = milliseconds {
            for query in queries {
                _ = cache
                    .lazy
                    .filter { $0.matches(query) }
                    .prefix(10)
                    .map(\.fileEntry)
            }
        }

        XCTAssertLessThan(
            searchMS,
            repeatedSearchBudgetMS,
            "Typing in the workspace launcher should keep result recompute below the interactive budget."
        )
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
}
