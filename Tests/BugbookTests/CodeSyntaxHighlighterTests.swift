import AppKit
import XCTest
@testable import Bugbook

final class CodeSyntaxHighlighterTests: XCTestCase {
    func testSwiftKeywordStringAndCommentAreHighlighted() {
        let code = #"let title = "Bugbook" // comment"#
        let attributed = CodeSyntaxHighlighter.attributedString(
            from: code,
            language: "swift",
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            textColor: .labelColor
        )

        XCTAssertColor(attributed.foregroundColor(at: "let", in: code), equals: CodeSyntaxHighlighter.keywordColor)
        XCTAssertColor(attributed.foregroundColor(at: #""Bugbook""#, in: code), equals: CodeSyntaxHighlighter.stringColor)
        XCTAssertColor(attributed.foregroundColor(at: "// comment", in: code), equals: CodeSyntaxHighlighter.commentColor)
    }

    func testJSONLiteralsAndNumbersAreHighlighted() {
        let code = #"{"enabled": true, "count": 42}"#
        let attributed = CodeSyntaxHighlighter.attributedString(
            from: code,
            language: "json",
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            textColor: .labelColor
        )

        XCTAssertColor(attributed.foregroundColor(at: "true", in: code), equals: CodeSyntaxHighlighter.keywordColor)
        XCTAssertColor(attributed.foregroundColor(at: "42", in: code), equals: CodeSyntaxHighlighter.numberColor)
    }
}

private extension CodeSyntaxHighlighterTests {
    func XCTAssertColor(
        _ actual: NSColor?,
        equals expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected color \(expected), got nil", file: file, line: line)
            return
        }
        XCTAssertTrue(
            actual.isEqual(expected),
            "Expected \(expected), got \(actual)",
            file: file,
            line: line
        )
    }
}

private extension NSAttributedString {
    func foregroundColor(at needle: String, in haystack: String) -> NSColor? {
        let range = (haystack as NSString).range(of: needle)
        guard range.location != NSNotFound else { return nil }
        return attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }
}
