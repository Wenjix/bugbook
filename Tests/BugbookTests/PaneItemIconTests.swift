import XCTest
@testable import Bugbook

/// Pins pane-item icon normalization: anything PageIcon can decode must round-
/// trip unchanged (custom image icons were previously mangled to "sf:custom:…").
@MainActor
final class PaneItemIconTests: XCTestCase {

    private func pageFile(icon: String?) -> OpenFile {
        OpenFile(
            id: UUID(),
            path: "/ws/Note.md",
            content: "",
            isDirty: false,
            isEmptyTab: false,
            kind: .page,
            icon: icon
        )
    }

    func testCustomIconRoundTripsUnmangled() {
        XCTAssertEqual(pageFile(icon: "custom:/ws/icons/a.png").paneItemIcon, "custom:/ws/icons/a.png")
    }

    func testAbsolutePathIconRoundTripsUnmangled() {
        XCTAssertEqual(pageFile(icon: "/ws/icons/a.png").paneItemIcon, "/ws/icons/a.png")
    }

    func testSymbolAndEmojiIconsRoundTrip() {
        XCTAssertEqual(pageFile(icon: "sf:bolt.fill").paneItemIcon, "sf:bolt.fill")
        XCTAssertEqual(pageFile(icon: "🚀").paneItemIcon, "🚀")
    }

    func testBareSymbolNameGetsPrefixed() {
        XCTAssertEqual(pageFile(icon: "doc.text").paneItemIcon, "sf:doc.text")
    }
}
