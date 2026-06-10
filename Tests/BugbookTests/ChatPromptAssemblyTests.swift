import XCTest
@testable import Bugbook

/// Tests the prompt-assembly module through its interface, using the
/// `readFile` seam so no test touches disk.
final class ChatPromptAssemblyTests: XCTestCase {

    private let workspace = "/ws"

    private func ref(_ path: String, name: String? = nil) -> ChatPromptAssembly.Reference {
        ChatPromptAssembly.Reference(path: path, name: name ?? (path as NSString).lastPathComponent)
    }

    func testDisplayNameStripsMarkdownExtension() {
        XCTAssertEqual(ChatPromptAssembly.displayName(for: "Notes.md"), "Notes")
        XCTAssertEqual(ChatPromptAssembly.displayName(for: "Folder"), "Folder")
    }

    func testDisplayMessageWithoutReferencesIsQuestion() {
        XCTAssertEqual(ChatPromptAssembly.displayMessage(question: "Q?", references: []), "Q?")
    }

    func testDisplayMessageAppendsMentions() {
        let message = ChatPromptAssembly.displayMessage(
            question: "Summarize",
            references: [ref("/ws/A.md"), ref("/ws/B.md")]
        )
        XCTAssertEqual(message, "Summarize\n\n@A @B")
    }

    func testPromptWithoutReferencesIsQuestion() {
        let prompt = ChatPromptAssembly.prompt(
            question: "Q?", references: [], workspacePath: workspace
        ) { _ in XCTFail("must not read files"); return nil }
        XCTAssertEqual(prompt, "Q?")
    }

    func testPromptEmbedsFencedSnippetWithRelativePath() {
        let prompt = ChatPromptAssembly.prompt(
            question: "Q?",
            references: [ref("/ws/sub/Note.md")],
            workspacePath: workspace
        ) { path in
            XCTAssertEqual(path, "/ws/sub/Note.md")
            return "hello body"
        }
        XCTAssertTrue(prompt.contains("File: sub/Note.md"))
        XCTAssertTrue(prompt.contains("```text\nhello body\n```"))
        XCTAssertTrue(prompt.hasPrefix("Q?"))
        XCTAssertTrue(prompt.contains("Referenced files (treat these as primary context):"))
    }

    func testPromptSkipsFilesOutsideWorkspace() {
        let prompt = ChatPromptAssembly.prompt(
            question: "Q?",
            references: [ref("/elsewhere/X.md")],
            workspacePath: workspace
        ) { _ in "should be ignored" }
        XCTAssertEqual(prompt, "Q?")
    }

    func testPromptTruncatesLongFiles() {
        let long = String(repeating: "a", count: ChatPromptAssembly.maxCharactersPerFile + 100)
        let prompt = ChatPromptAssembly.prompt(
            question: "Q?",
            references: [ref("/ws/Long.md")],
            workspacePath: workspace
        ) { _ in long }
        XCTAssertTrue(prompt.contains("...[truncated]"))
        XCTAssertFalse(prompt.contains(long))
    }

    func testPromptNotesUnreadableFiles() {
        let prompt = ChatPromptAssembly.prompt(
            question: "Q?",
            references: [ref("/ws/Gone.md")],
            workspacePath: workspace
        ) { _ in nil }
        XCTAssertTrue(prompt.contains("File: Gone.md\n[Could not read file content]"))
    }

    func testPromptCapsReferenceCount() {
        var readCount = 0
        let references = (0..<10).map { ref("/ws/N\($0).md") }
        _ = ChatPromptAssembly.prompt(
            question: "Q?",
            references: references,
            workspacePath: workspace
        ) { _ in
            readCount += 1
            return "x"
        }
        XCTAssertEqual(readCount, ChatPromptAssembly.maxReferences)
    }
}
