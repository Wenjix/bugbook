import XCTest
@testable import Bugbook

final class MeetingTranscriptMarkdownTests: XCTestCase {
    func testCollapsedTranscriptToggleSerializesAsPlainMarkdown() {
        let transcriptBlock = Block(type: .codeBlock, text: "Me: hello\n\nOther: hi", language: "text")
        let toggle = Block(
            type: .toggle,
            text: "Transcript",
            children: [transcriptBlock],
            isExpanded: false
        )

        let markdown = MarkdownBlockParser.serialize([toggle])

        XCTAssertTrue(markdown.contains("<!-- toggle collapsed -->"))
        XCTAssertTrue(markdown.contains("Transcript"))
        XCTAssertTrue(markdown.contains("```text\nMe: hello\n\nOther: hi\n```"))
        XCTAssertTrue(markdown.contains("<!-- /toggle -->"))

        let parsed = MarkdownBlockParser.parse(markdown)
        XCTAssertEqual(parsed.first?.type, .toggle)
        XCTAssertEqual(parsed.first?.text, "Transcript")
        XCTAssertEqual(parsed.first?.isExpanded, false)
        XCTAssertEqual(parsed.first?.children.first?.type, .codeBlock)
        XCTAssertEqual(parsed.first?.children.first?.text, "Me: hello\n\nOther: hi")
    }
}
