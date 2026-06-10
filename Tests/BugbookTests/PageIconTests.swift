import XCTest
@testable import Bugbook

/// Tests the page-icon module through its interface: `PageIcon.parse`, the
/// single decoder for raw icon strings stored in page metadata and FileEntry.
final class PageIconTests: XCTestCase {

    func testParseCustomPrefixDecodesPath() {
        XCTAssertEqual(
            PageIcon.parse("custom:/Users/x/Library/icons/a.png"),
            PageIcon.custom("/Users/x/Library/icons/a.png")
        )
    }

    func testParseSymbolPrefixDecodesSymbolName() {
        XCTAssertEqual(PageIcon.parse("sf:bolt.fill"), PageIcon.symbol("bolt.fill"))
    }

    func testParseEmojiDecodesAsEmoji() {
        XCTAssertEqual(PageIcon.parse("🚀"), PageIcon.emoji("🚀"))
    }

    func testParseMultiScalarEmojiDecodesAsEmoji() {
        XCTAssertEqual(PageIcon.parse("👨‍👩‍👧"), PageIcon.emoji("👨‍👩‍👧"))
    }

    func testParseBareAbsolutePathIsLegacyCustomIcon() {
        XCTAssertEqual(PageIcon.parse("/tmp/icon.png"), PageIcon.custom("/tmp/icon.png"))
    }

    func testParseNilEmptyAndPlainTextReturnNil() {
        XCTAssertNil(PageIcon.parse(nil))
        XCTAssertNil(PageIcon.parse(""))
        XCTAssertNil(PageIcon.parse("hello"))
        XCTAssertNil(PageIcon.parse("relative/path.png"))
    }

    /// Documents preserved first-scalar semantics: ASCII digits carry the
    /// Unicode Emoji property (keycap bases), so they render as emoji text —
    /// exactly what the previous per-view decoders did.
    func testParseDigitKeepsHistoricEmojiTreatment() {
        XCTAssertEqual(PageIcon.parse("1"), PageIcon.emoji("1"))
    }
}
