import XCTest
@testable import Bugbook

final class ArtifactModelTests: XCTestCase {
    private func makeArtifactOpenFile(
        path: String = "/ws/Weekly Review/sleep-trends.html",
        displayName: String? = nil,
        icon: String? = nil
    ) -> OpenFile {
        OpenFile(
            id: UUID(),
            path: path,
            content: "",
            isDirty: false,
            isEmptyTab: false,
            kind: .artifact,
            displayName: displayName,
            openerPagePath: nil,
            icon: icon,
            navigationHistory: [path],
            navigationHistoryIndex: 0
        )
    }

    func testRemovingPageExtension() {
        XCTAssertEqual("sleep-trends.html".removingPageExtension, "sleep-trends")
        XCTAssertEqual("Weekly Review.md".removingPageExtension, "Weekly Review")
        XCTAssertEqual("Notes.db.md".removingPageExtension, "Notes.db")
        XCTAssertEqual("archive.tar".removingPageExtension, "archive.tar")
        XCTAssertEqual("plain".removingPageExtension, "plain")
        XCTAssertEqual("".removingPageExtension, "")
    }

    func testTabKindArtifactShims() {
        XCTAssertTrue(TabKind.artifact.isArtifact)
        XCTAssertFalse(TabKind.page.isArtifact)
        let entry = FileEntry(
            id: "/ws/chart.html", name: "chart.html", path: "/ws/chart.html",
            isDirectory: false, kind: .artifact
        )
        XCTAssertTrue(entry.isArtifact)
        XCTAssertFalse(entry.isDatabase)
    }

    func testFeatureGateAllowsArtifact() {
        // .artifact must be allowed unconditionally (both legacy and non-legacy modes).
        XCTAssertTrue(BugbookFeatureGate.allowsTabKind(.artifact))
    }

    func testOpenFileCodableRoundTripWithArtifactKind() throws {
        let file = makeArtifactOpenFile()
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(OpenFile.self, from: data)
        XCTAssertEqual(decoded.kind, .artifact)
        XCTAssertTrue(decoded.isArtifact)
        XCTAssertEqual(decoded.path, file.path)
    }

    func testArtifactPaneItemTitleStripsHtmlExtension() {
        XCTAssertEqual(makeArtifactOpenFile().paneItemTitle, "sleep-trends")
        XCTAssertEqual(
            makeArtifactOpenFile(displayName: "Sleep Trends — 2026-W23").paneItemTitle,
            "Sleep Trends — 2026-W23"
        )
    }

    func testArtifactPaneItemIcon() {
        XCTAssertEqual(makeArtifactOpenFile().paneItemIcon, "sf:doc.richtext")
        XCTAssertEqual(makeArtifactOpenFile(icon: "sf:bed.double").paneItemIcon, "sf:bed.double")
    }
}
