import XCTest
@testable import Bugbook

// MARK: - AttributedString Converter Tests

final class AttributedStringConverterTests: XCTestCase {
    func testBareWikiLinkBecomesClickableSpanAndRoundTrips() {
        let markdown = "See [[Values]] for more."
        let attributed = AttributedStringConverter.attributedString(from: markdown)
        let linkRange = (attributed.string as NSString).range(of: "Values")

        XCTAssertEqual(attributed.string, "See Values for more.")
        XCTAssertEqual(
            attributed.attribute(AttributedStringConverter.wikiLinkPageNameKey, at: linkRange.location, effectiveRange: nil) as? String,
            "Values"
        )
        XCTAssertEqual(
            attributed.attribute(AttributedStringConverter.markdownSourceKey, at: linkRange.location, effectiveRange: nil) as? String,
            "[[Values]]"
        )
        XCTAssertEqual(AttributedStringConverter.markdown(from: attributed), markdown)
    }

    func testBareWikiLinkWorksInsideBulletText() {
        let markdown = "[[Values]] test"
        let attributed = AttributedStringConverter.attributedString(from: markdown)
        let linkRange = (attributed.string as NSString).range(of: "Values")

        XCTAssertEqual(attributed.string, "Values test")
        XCTAssertEqual(
            attributed.attribute(AttributedStringConverter.wikiLinkPageNameKey, at: linkRange.location, effectiveRange: nil) as? String,
            "Values"
        )
    }

    func testWikiLinkAliasDisplaysAliasAndKeepsTarget() {
        let markdown = "See [[Values|core values]]."
        let attributed = AttributedStringConverter.attributedString(from: markdown)
        let linkRange = (attributed.string as NSString).range(of: "core values")

        XCTAssertEqual(attributed.string, "See core values.")
        XCTAssertEqual(
            attributed.attribute(AttributedStringConverter.wikiLinkPageNameKey, at: linkRange.location, effectiveRange: nil) as? String,
            "Values"
        )
        XCTAssertEqual(AttributedStringConverter.markdown(from: attributed), markdown)
    }

    func testMentionSyntaxStillUsesMentionSpanAndRoundTrips() {
        let markdown = "Ask @[[Values]] about it."
        let attributed = AttributedStringConverter.attributedString(from: markdown)
        let mentionRange = (attributed.string as NSString).range(of: "Values")

        XCTAssertEqual(attributed.string, "Ask Values about it.")
        XCTAssertEqual(
            attributed.attribute(AttributedStringConverter.mentionPageNameKey, at: mentionRange.location, effectiveRange: nil) as? String,
            "Values"
        )
        XCTAssertNil(attributed.attribute(AttributedStringConverter.wikiLinkPageNameKey, at: mentionRange.location, effectiveRange: nil))
        XCTAssertEqual(AttributedStringConverter.markdown(from: attributed), markdown)
    }

    func testInlineFootnoteReferenceBecomesSuperscriptAndRoundTrips() {
        let markdown = "See this[^1]."
        let attributed = AttributedStringConverter.attributedString(from: markdown)
        let labelRange = (attributed.string as NSString).range(of: "1")

        XCTAssertEqual(attributed.string, "See this1.")
        XCTAssertEqual(
            attributed.attribute(AttributedStringConverter.footnoteReferenceLabelKey, at: labelRange.location, effectiveRange: nil) as? String,
            "1"
        )
        XCTAssertEqual(
            attributed.attribute(AttributedStringConverter.markdownSourceKey, at: labelRange.location, effectiveRange: nil) as? String,
            "[^1]"
        )
        XCTAssertNotNil(attributed.attribute(.baselineOffset, at: labelRange.location, effectiveRange: nil))
        XCTAssertEqual(AttributedStringConverter.markdown(from: attributed), markdown)
    }

    func testFootnoteDefinitionSyntaxIsNotRenderedAsInlineReference() {
        let markdown = "[^1]: definition"
        let attributed = AttributedStringConverter.attributedString(from: markdown)

        XCTAssertEqual(attributed.string, markdown)
    }
}

// MARK: - Live Transcription Audio Source Tests

final class LiveTranscriptionAudioSourceTests: XCTestCase {
    func testTranscriptLabelsOnlyMarkSystemAudio() {
        XCTAssertEqual(
            LiveTranscriptionAudioSource.microphone.labeledTranscript(" hello "),
            "hello"
        )
        XCTAssertEqual(
            LiveTranscriptionAudioSource.system.labeledTranscript("remote voice"),
            "Other: remote voice"
        )
    }

    func testTranscriptLabelsSkipEmptyText() {
        XCTAssertEqual(LiveTranscriptionAudioSource.microphone.labeledTranscript("  "), "")
        XCTAssertEqual(LiveTranscriptionAudioSource.system.labeledTranscript("\n"), "")
    }
}

// MARK: - BlockDocument Tests

@MainActor
final class BlockDocumentTests: XCTestCase {

    func testInitFromMarkdown() {
        let doc = BlockDocument(markdown: "# Title\nSome text\n")
        XCTAssertGreaterThanOrEqual(doc.blocks.count, 2)
        XCTAssertEqual(doc.blocks[0].type, .heading)
        XCTAssertEqual(doc.blocks[0].headingLevel, 1)
        XCTAssertEqual(doc.blocks[0].text, "Title")
    }

    func testTitleBlockAccessor() {
        let doc = BlockDocument(markdown: "# My Title\nBody\n")
        XCTAssertNotNil(doc.titleBlock)
        XCTAssertEqual(doc.titleBlock?.text, "My Title")
    }

    func testTitleBlockNilWhenNotHeading() {
        let doc = BlockDocument(markdown: "Just a paragraph\n")
        XCTAssertNil(doc.titleBlock)
    }

    func testDefaultModeBlocksInlineAiPrompt() throws {
        UserDefaults.standard.removeObject(forKey: BugbookFeatureGate.legacyPanesDefaultsKey)
        let doc = BlockDocument(markdown: "Just a paragraph\n")
        let blockId = try XCTUnwrap(doc.blocks.first?.id)

        doc.showAiPrompt(blockId: blockId)

        XCTAssertNil(doc.aiPromptBlockId)
    }

    func testLegacyModeAllowsInlineAiPrompt() throws {
        UserDefaults.standard.set(true, forKey: BugbookFeatureGate.legacyPanesDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: BugbookFeatureGate.legacyPanesDefaultsKey) }
        let doc = BlockDocument(markdown: "Just a paragraph\n")
        let blockId = try XCTUnwrap(doc.blocks.first?.id)

        doc.showAiPrompt(blockId: blockId)

        XCTAssertEqual(doc.aiPromptBlockId, blockId)
    }

    func testMeetingPageCompletionRequiresRecordedAt() {
        let scheduledMeeting = BlockDocument(markdown: """
        ---
        type: meeting
        duration: 45m
        ---

        # Parent Interview
        """)

        XCTAssertTrue(scheduledMeeting.isMeetingPage)
        XCTAssertFalse(scheduledMeeting.isCompletedMeetingPage)

        let completedMeeting = BlockDocument(markdown: """
        ---
        type: meeting
        recorded_at: 2026-05-18T07:00:00Z
        duration: 45m
        ---

        # Parent Interview
        """)

        XCTAssertTrue(completedMeeting.isMeetingPage)
        XCTAssertTrue(completedMeeting.isCompletedMeetingPage)
    }

    func testMarkdownRoundTrip() {
        let md = "# Title\n\nSome text here\n\n- List item 1\n- List item 2\n"
        let doc = BlockDocument(markdown: md)
        let output = doc.markdown
        // Should contain the same content elements
        XCTAssertTrue(output.contains("Title"))
        XCTAssertTrue(output.contains("Some text here"))
        XCTAssertTrue(output.contains("List item 1"))
    }

    func testDefaultSlashCommandsHideAskAI() {
        UserDefaults.standard.removeObject(forKey: BugbookFeatureGate.legacyPanesDefaultsKey)
        let doc = BlockDocument(markdown: "")
        doc.slashMenuFilter = "ai"

        XCTAssertFalse(doc.filteredSlashCommands.contains { $0.name == "Ask AI" })
    }

    func testLegacySlashCommandsIncludeAskAI() {
        UserDefaults.standard.set(true, forKey: BugbookFeatureGate.legacyPanesDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: BugbookFeatureGate.legacyPanesDefaultsKey) }

        let doc = BlockDocument(markdown: "")
        doc.slashMenuFilter = "ai"

        XCTAssertTrue(doc.filteredSlashCommands.contains { $0.name == "Ask AI" })
    }

    func testMarkdownParsesObsidianCallout() {
        let markdown = """
        > [!WARNING] Watch this
        > Check [[Runbook]] first.
        > - Confirm audio
        """
        let doc = BlockDocument(markdown: markdown)

        XCTAssertEqual(doc.blocks.count, 1)
        let callout = doc.blocks[0]
        XCTAssertEqual(callout.type, .callout)
        XCTAssertEqual(callout.text, "Watch this")
        XCTAssertEqual(callout.calloutIcon, "exclamationmark.triangle")
        XCTAssertEqual(callout.calloutColor, "orange")
        XCTAssertEqual(callout.children.map(\.type), [.paragraph, .bulletListItem])
        XCTAssertEqual(callout.children[0].text, "Check [[Runbook]] first.")
        XCTAssertEqual(callout.children[1].text, "Confirm audio")
    }

    func testDefaultCalloutSerializesAsMarkdownCallout() {
        let callout = Block(
            type: .callout,
            text: "Remember",
            children: [
                Block(type: .paragraph, text: "Plain note"),
                Block(type: .taskItem, text: "Ship it", isChecked: true),
            ]
        )
        let doc = BlockDocument(markdown: "")
        doc.blocks = [callout]

        XCTAssertEqual(
            doc.markdown,
            """
            > [!NOTE] Remember
            > Plain note
            > - [x] Ship it
            """
        )
    }

    func testCustomCalloutKeepsCommentSerialization() {
        let callout = Block(
            type: .callout,
            text: "Custom",
            calloutIcon: "heart",
            calloutColor: "pink"
        )
        let doc = BlockDocument(markdown: "")
        doc.blocks = [callout]

        XCTAssertEqual(
            doc.markdown,
            """
            <!-- callout icon:heart color:pink -->
            Custom
            <!-- /callout -->
            """
        )
    }

    func testReloadFromDiskRestoresMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("Note.md")
        let markdown = """
        <!-- icon:bolt.fill -->
        <!-- cover:/tmp/cover.png@42 -->
        <!-- full-width -->
        # Title
        Body
        """
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        let doc = BlockDocument(markdown: "# Title\nBody\n")
        doc.filePath = fileURL.path
        doc.reloadFromDisk()

        XCTAssertEqual(doc.icon, "bolt.fill")
        XCTAssertEqual(doc.coverUrl, "/tmp/cover.png")
        XCTAssertEqual(doc.coverPosition, 42)
        XCTAssertTrue(doc.fullWidth)
        XCTAssertEqual(doc.titleBlock?.text, "Title")
        XCTAssertTrue(doc.blocks.contains(where: { $0.text == "Body" }))
    }

    func testDeleteBlock() {
        let doc = BlockDocument(markdown: "# Title\nParagraph 1\nParagraph 2\n")
        let initialCount = doc.blocks.count
        guard initialCount >= 3 else {
            XCTFail("Expected at least 3 blocks")
            return
        }
        let blockToDelete = doc.blocks[1].id
        let survivorId = doc.blocks[2].id
        doc.deleteBlock(id: blockToDelete)
        XCTAssertEqual(doc.blocks.count, initialCount)
        XCTAssertNil(doc.blocks.first(where: { $0.id == blockToDelete }))
        XCTAssertEqual(doc.blocks[1].id, survivorId)
        XCTAssertEqual(doc.blocks.last?.type, .paragraph)
        XCTAssertEqual(doc.blocks.last?.text, "")
    }

    func testChangeBlockType() {
        let doc = BlockDocument(markdown: "# Title\nA paragraph\n")
        guard doc.blocks.count >= 2 else {
            XCTFail("Expected at least 2 blocks")
            return
        }
        let paragraphId = doc.blocks[1].id
        doc.changeBlockType(id: paragraphId, to: .bulletListItem)
        XCTAssertEqual(doc.blocks[1].type, .bulletListItem)
    }

    func testToggleCheck() {
        let doc = BlockDocument(markdown: "# Title\n- [ ] Task\n")
        guard doc.blocks.count >= 2 else {
            XCTFail("Expected at least 2 blocks")
            return
        }
        let taskId = doc.blocks[1].id
        XCTAssertFalse(doc.blocks[1].isChecked)
        doc.toggleCheck(id: taskId)
        XCTAssertTrue(doc.blocks[1].isChecked)
        doc.toggleCheck(id: taskId)
        XCTAssertFalse(doc.blocks[1].isChecked)
    }

    func testMoveBlock() {
        let doc = BlockDocument(markdown: "# Title\nBlock A\nBlock B\nBlock C\n")
        guard doc.blocks.count >= 4 else {
            XCTFail("Expected at least 4 blocks")
            return
        }
        let blockAId = doc.blocks[1].id
        doc.moveBlock(from: 1, to: 3) // Move A after C
        XCTAssertEqual(doc.blocks[2].id, blockAId)
    }

    func testDuplicateBlock() {
        let doc = BlockDocument(markdown: "# Title\nOriginal text\n")
        guard doc.blocks.count >= 2 else {
            XCTFail("Expected at least 2 blocks")
            return
        }
        let initialCount = doc.blocks.count
        let originalId = doc.blocks[1].id
        doc.duplicateBlock(id: originalId)
        XCTAssertEqual(doc.blocks.count, initialCount + 1)
        // Find the duplicate (should be right after original)
        let dupIndex = doc.blocks.firstIndex(where: { $0.id != originalId && $0.text == "Original text" })
        XCTAssertNotNil(dupIndex)
    }

    func testCopyImageToAssetsStoresWorkspaceRelativePath() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("source.png")
        try Data([1, 2, 3]).write(to: sourceURL)

        let workspaceURL = tempDir.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let doc = BlockDocument(markdown: "# Title\n")
        doc.workspacePath = workspaceURL.path

        let storedPath = try XCTUnwrap(doc.copyImageToAssets(sourceURL))

        XCTAssertEqual(storedPath, "_assets/source.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent(storedPath).path))

        doc.insertImageBlock(at: doc.blocks.count, imagePath: storedPath)
        XCTAssertTrue(doc.markdown.contains("![](_assets/source.png)"))
    }

    func testSaveImageDataToAssetsStoresWorkspaceRelativePath() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let doc = BlockDocument(markdown: "# Title\n")
        doc.workspacePath = workspaceURL.path

        let storedPath = try XCTUnwrap(doc.saveImageDataToAssets(Data([4, 5, 6]), fileExtension: "png"))

        XCTAssertTrue(storedPath.hasPrefix("_assets/"))
        XCTAssertFalse(storedPath.hasPrefix("/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent(storedPath).path))
    }

    func testSelectAllBlocks() {
        let doc = BlockDocument(markdown: "# Title\nBlock 1\nBlock 2\nBlock 3\n")
        doc.selectAllBlocks()
        XCTAssertEqual(doc.selectedBlockIds.count, doc.blocks.count)
    }

    func testClearBlockSelection() {
        let doc = BlockDocument(markdown: "# Title\nBlock 1\n")
        doc.selectAllBlocks()
        XCTAssertFalse(doc.selectedBlockIds.isEmpty)
        doc.clearBlockSelection()
        XCTAssertTrue(doc.selectedBlockIds.isEmpty)
    }

    func testSelectBlockRange() {
        let doc = BlockDocument(markdown: "# Title\nA\nB\nC\nD\n")
        guard doc.blocks.count >= 5 else {
            XCTFail("Expected at least 5 blocks")
            return
        }
        let from = doc.blocks[1].id
        let to = doc.blocks[3].id
        doc.selectBlockRange(from: from, to: to)
        XCTAssertEqual(doc.selectedBlockIds.count, 3)
        XCTAssertTrue(doc.selectedBlockIds.contains(doc.blocks[1].id))
        XCTAssertTrue(doc.selectedBlockIds.contains(doc.blocks[2].id))
        XCTAssertTrue(doc.selectedBlockIds.contains(doc.blocks[3].id))
    }

    func testCommandShiftDownSelectionExtendsFromFocusedBlockToEnd() {
        let doc = BlockDocument(markdown: "# Title\nA\nB\nC\nD\n")
        guard doc.blocks.count >= 5 else {
            XCTFail("Expected at least 5 blocks")
            return
        }

        doc.focusedBlockId = doc.blocks[2].id

        XCTAssertTrue(doc.selectBlockRangeFromFocusedBlock(toBoundary: .down))
        XCTAssertEqual(doc.selectedBlockIds, Set(doc.blocks[2...].map(\.id)))
    }

    func testCommandShiftUpSelectionExtendsFromStartToFocusedBlock() {
        let doc = BlockDocument(markdown: "# Title\nA\nB\nC\nD\n")
        guard doc.blocks.count >= 5 else {
            XCTFail("Expected at least 5 blocks")
            return
        }

        doc.focusedBlockId = doc.blocks[3].id

        XCTAssertTrue(doc.selectBlockRangeFromFocusedBlock(toBoundary: .up))
        XCTAssertEqual(doc.selectedBlockIds, Set(doc.blocks[...3].map(\.id)))
    }

    func testCommandShiftBlockSelectionRequiresFocusedBlock() {
        let doc = BlockDocument(markdown: "# Title\nA\nB\n")
        doc.focusedBlockId = nil

        XCTAssertFalse(doc.selectBlockRangeFromFocusedBlock(toBoundary: .down))
        XCTAssertTrue(doc.selectedBlockIds.isEmpty)
    }

    func testDeleteSelectedBlocks() {
        let doc = BlockDocument(markdown: "# Title\nA\nB\nC\n")
        let initialCount = doc.blocks.count
        guard initialCount >= 4 else {
            XCTFail("Expected at least 4 blocks")
            return
        }
        let deletedIds = [doc.blocks[1].id, doc.blocks[2].id]
        doc.selectedBlockIds = Set(deletedIds)
        doc.deleteSelectedBlocks()
        XCTAssertEqual(doc.blocks.count, initialCount - 1)
        XCTAssertNil(doc.blocks.first(where: { deletedIds.contains($0.id) }))
        XCTAssertEqual(doc.blocks.last?.type, .paragraph)
        XCTAssertEqual(doc.blocks.last?.text, "")
        XCTAssertTrue(doc.selectedBlockIds.isEmpty)
    }

    func testBlockSelectionDragSetsTapSuppressionUntilConsumed() {
        let doc = BlockDocument(markdown: "# Title\nA\nB\n")
        guard doc.blocks.count >= 3 else {
            XCTFail("Expected at least 3 blocks")
            return
        }
        doc.beginBlockSelectionDrag(from: doc.blocks[1].id)
        doc.selectBlockRange(from: doc.blocks[1].id, to: doc.blocks[2].id)
        doc.endBlockSelectionDrag()

        XCTAssertTrue(doc.consumePendingEditorTapAfterBlockSelection())
        XCTAssertFalse(doc.consumePendingEditorTapAfterBlockSelection())
    }

    func testUndoBlockOperation() {
        let doc = BlockDocument(markdown: "# Title\nOriginal\n")
        let initialCount = doc.blocks.count
        let deletedId = doc.blocks[1].id
        doc.deleteBlock(id: deletedId)
        XCTAssertEqual(doc.blocks.count, initialCount)
        XCTAssertNil(doc.blocks.first(where: { $0.id == deletedId }))
        XCTAssertEqual(doc.blocks.last?.type, .paragraph)
        XCTAssertEqual(doc.blocks.last?.text, "")
        doc.undo()
        XCTAssertEqual(doc.blocks.count, initialCount)
        XCTAssertNotNil(doc.blocks.first(where: { $0.id == deletedId }))
    }

    func testRedoBlockOperation() {
        let doc = BlockDocument(markdown: "# Title\nOriginal\n")
        let initialCount = doc.blocks.count
        let deletedId = doc.blocks[1].id
        doc.deleteBlock(id: deletedId)
        doc.undo()
        doc.redo()
        XCTAssertEqual(doc.blocks.count, initialCount)
        XCTAssertNil(doc.blocks.first(where: { $0.id == deletedId }))
        XCTAssertEqual(doc.blocks.last?.type, .paragraph)
        XCTAssertEqual(doc.blocks.last?.text, "")
    }

    func testSplitBlock() {
        let doc = BlockDocument(markdown: "# Title\nHello World\n")
        guard doc.blocks.count >= 2 else {
            XCTFail("Expected at least 2 blocks")
            return
        }
        let blockId = doc.blocks[1].id
        let initialCount = doc.blocks.count
        _ = doc.splitBlock(id: blockId, atOffset: 5)
        XCTAssertEqual(doc.blocks.count, initialCount + 1)
        XCTAssertEqual(doc.blocks[1].text, "Hello")
        XCTAssertEqual(doc.blocks[2].text, " World")
    }

    func testPasteMarkdownBlocksIntoEmptyParagraph() {
        let doc = BlockDocument(markdown: "")
        let targetId = doc.blocks[0].id

        let didPaste = doc.pasteMarkdownBlocks(
            """
            ## From Obsidian

            - [ ] Draft import
            [[Action Zone]]
            """,
            into: targetId,
            replacingMarkdownRange: NSRange(location: 0, length: 0)
        )

        XCTAssertTrue(didPaste)
        XCTAssertEqual(doc.blocks[0].type, .heading)
        XCTAssertEqual(doc.blocks[0].headingLevel, 2)
        XCTAssertEqual(doc.blocks[0].text, "From Obsidian")
        XCTAssertEqual(doc.blocks[1].type, .taskItem)
        XCTAssertFalse(doc.blocks[1].isChecked)
        XCTAssertEqual(doc.blocks[1].text, "Draft import")
        XCTAssertEqual(doc.blocks[2].type, .pageLink)
        XCTAssertEqual(doc.blocks[2].pageLinkName, "Action Zone")
        XCTAssertEqual(doc.blocks.last?.type, .paragraph)
        XCTAssertEqual(doc.blocks.last?.text, "")
    }

    func testPasteMarkdownBlocksSplitsCurrentParagraph() {
        let doc = BlockDocument(markdown: "Before after")
        let targetId = doc.blocks[0].id
        let insertionOffset = ("Before " as NSString).length

        let didPaste = doc.pasteMarkdownBlocks(
            """
            # Inserted

            Body
            """,
            into: targetId,
            replacingMarkdownRange: NSRange(location: insertionOffset, length: 0)
        )

        XCTAssertTrue(didPaste)
        XCTAssertEqual(doc.blocks[0].text, "Before ")
        XCTAssertEqual(doc.blocks[1].type, .heading)
        XCTAssertEqual(doc.blocks[1].text, "Inserted")
        XCTAssertEqual(doc.blocks[2].type, .paragraph)
        XCTAssertEqual(doc.blocks[2].text, "Body")
        XCTAssertEqual(doc.blocks[3].type, .paragraph)
        XCTAssertEqual(doc.blocks[3].text, "after")
        XCTAssertEqual(doc.focusedBlockId, doc.blocks[3].id)
        XCTAssertEqual(doc.cursorPosition, 0)
    }

    func testSetHeadingLevel() {
        let doc = BlockDocument(markdown: "# Title\nSome text\n")
        guard doc.blocks.count >= 2 else {
            XCTFail("Expected at least 2 blocks")
            return
        }
        let blockId = doc.blocks[1].id
        doc.changeBlockType(id: blockId, to: .heading)
        doc.setHeadingLevel(id: blockId, level: 2)
        XCTAssertEqual(doc.blocks[1].headingLevel, 2)
    }

    func testUpdateBlockText() {
        let doc = BlockDocument(markdown: "# Title\nOld text\n")
        guard doc.blocks.count >= 2 else {
            XCTFail("Expected at least 2 blocks")
            return
        }
        let blockId = doc.blocks[1].id
        doc.updateBlockText(id: blockId, text: "New text")
        XCTAssertEqual(doc.blocks[1].text, "New text")
    }

    func testEmptyDocument() {
        let doc = BlockDocument(markdown: "")
        XCTAssertGreaterThanOrEqual(doc.blocks.count, 1) // Should have at least an empty block
    }

    func testBlockColors() {
        let doc = BlockDocument(markdown: "# Title\nText\n")
        guard doc.blocks.count >= 2 else {
            XCTFail("Expected at least 2 blocks")
            return
        }
        let blockId = doc.blocks[1].id
        doc.setTextColor(id: blockId, color: .red)
        XCTAssertEqual(doc.blocks[1].textColor, .red)
        doc.setBackgroundColor(id: blockId, color: .blue)
        XCTAssertEqual(doc.blocks[1].backgroundColor, .blue)
    }

    func testMarkdownSerializeDoesNotEmitBlockIDCommentsByDefault() {
        let doc = BlockDocument(markdown: "# Title\nBody\n")
        let output = doc.markdown

        let blockIDLines = output
            .components(separatedBy: .newlines)
            .filter { $0.contains("<!-- block-id:") }

        XCTAssertTrue(blockIDLines.isEmpty)
        XCTAssertTrue(output.contains("# Title"))
        XCTAssertTrue(output.contains("Body"))
    }

    func testMarkdownRoundTripsPersistedBlockIDs() {
        let titleID = UUID().uuidString.lowercased()
        let bodyID = UUID().uuidString.lowercased()
        let markdown = """
        <!-- block-id: \(titleID) -->
        # Title
        <!-- block-id: \(bodyID) -->
        Body
        """

        let doc = BlockDocument(markdown: markdown)
        XCTAssertEqual(doc.blocks[0].id.uuidString.lowercased(), titleID)
        XCTAssertEqual(doc.blocks[1].id.uuidString.lowercased(), bodyID)

        let output = doc.markdown
        XCTAssertTrue(output.contains("<!-- block-id: \(titleID) -->"))
        XCTAssertTrue(output.contains("<!-- block-id: \(bodyID) -->"))
    }

    func testMarkdownIgnoresSingleTrailingNewlineAsExtraBlock() {
        let doc = BlockDocument(markdown: "# Title\nBody\n")
        XCTAssertEqual(doc.blocks.count, 2)
        XCTAssertEqual(doc.blocks[0].text, "Title")
        XCTAssertEqual(doc.blocks[1].text, "Body")
    }

    func testMarkdownEscapesParagraphSyntaxToPreserveParagraphBlocks() {
        let doc = BlockDocument(markdown: "Paragraph\n")
        doc.blocks[0].text = "- not a list"

        let output = doc.markdown
        XCTAssertEqual(output, "\\- not a list")

        let reparsed = BlockDocument(markdown: output)
        XCTAssertEqual(reparsed.blocks.count, 1)
        XCTAssertEqual(reparsed.blocks[0].type, .paragraph)
        XCTAssertEqual(reparsed.blocks[0].text, "- not a list")
    }

    func testMarkdownParsesFootnoteDefinition() {
        let doc = BlockDocument(markdown: "[^1]: Footnote text")

        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks[0].type, .footnote)
        XCTAssertEqual(doc.blocks[0].footnoteLabel, "1")
        XCTAssertEqual(doc.blocks[0].text, "Footnote text")
        XCTAssertEqual(doc.markdown, "[^1]: Footnote text")
    }

    func testMarkdownRoundTripsMultilineFootnoteDefinition() {
        let markdown = """
        [^note]: First line
            Continued line
        """

        let doc = BlockDocument(markdown: markdown)

        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks[0].type, .footnote)
        XCTAssertEqual(doc.blocks[0].footnoteLabel, "note")
        XCTAssertEqual(doc.blocks[0].text, "First line\nContinued line")
        XCTAssertEqual(doc.markdown, markdown)
    }

    func testMarkdownEscapesParagraphFootnoteSyntax() {
        let doc = BlockDocument(markdown: "Paragraph\n")
        doc.blocks[0].text = "[^1]: not a footnote"

        let output = doc.markdown
        XCTAssertEqual(output, "\\[^1]: not a footnote")

        let reparsed = BlockDocument(markdown: output)
        XCTAssertEqual(reparsed.blocks.count, 1)
        XCTAssertEqual(reparsed.blocks[0].type, .paragraph)
        XCTAssertEqual(reparsed.blocks[0].text, "[^1]: not a footnote")
    }

    func testMarkdownParsesTableWithoutOuterPipes() {
        let markdown = #"""
        Name | Notes
        --- | ---
        Alpha | one \| two
        Beta | plain
        """#

        let doc = BlockDocument(markdown: markdown)

        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks[0].type, .table)
        XCTAssertTrue(doc.blocks[0].hasHeaderRow)
        XCTAssertEqual(doc.blocks[0].tableData, [
            ["Name", "Notes"],
            ["Alpha", "one | two"],
            ["Beta", "plain"],
        ])
        XCTAssertEqual(doc.markdown, """
        | Name | Notes |
        | --- | --- |
        | Alpha | one \\| two |
        | Beta | plain |
        """)
    }

    func testMarkdownKeepsPlainPipeParagraphWithoutTableSeparator() {
        let doc = BlockDocument(markdown: "Use A | B as text")

        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks[0].type, .paragraph)
        XCTAssertEqual(doc.blocks[0].text, "Use A | B as text")
    }

}

// MARK: - AppState Tests

@MainActor
final class AppStateTests: XCTestCase {
    private func makeUserDefaultsSuite() -> UserDefaults {
        let suiteName = "AppStateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeEntry(
        name: String = "Test.md",
        path: String = "/test/Test.md",
        kind: TabKind = .page
    ) -> FileEntry {
        FileEntry(
            id: path,
            name: name,
            path: path,
            isDirectory: false,
            kind: kind
        )
    }

    private func makeOpenFile(name: String, path: String, id: UUID = UUID()) -> OpenFile {
        OpenFile(
            id: id,
            path: path,
            content: "",
            isDirty: false,
            isEmptyTab: false,
            displayName: name.replacingOccurrences(of: ".md", with: ""),
            navigationHistory: [path],
            navigationHistoryIndex: 0
        )
    }

    func testOpenFileCreatesTab() {
        let state = AppState()
        let entry = makeEntry()
        state.openFile(entry)
        XCTAssertEqual(state.openTabs.count, 1)
        XCTAssertEqual(state.activeTabIndex, 0)
        XCTAssertEqual(state.openTabs[0].path, "/test/Test.md")
    }

    func testOpenFileSwitchesToExistingTab() {
        let state = AppState()
        let entry1 = makeEntry(name: "A.md", path: "/test/A.md")
        let entry2 = makeEntry(name: "B.md", path: "/test/B.md")
        state.openFile(entry1)
        state.openFile(entry2)
        XCTAssertEqual(state.openTabs.count, 2)
        XCTAssertEqual(state.activeTabIndex, 1)
        state.openFile(entry1) // should switch, not create new
        XCTAssertEqual(state.openTabs.count, 2)
        XCTAssertEqual(state.activeTabIndex, 0)
    }

    func testPaneScopedReplaceUpdatesRequestedPaneWhenAnotherPaneIsFocused() throws {
        let state = AppState()
        let manager = WorkspaceManager()
        manager.layoutPersistenceEnabled = false

        manager.addWorkspaceWith(content: .document(openFile: makeOpenFile(name: "Child.md", path: "/test/Child.md")))
        let sourcePaneId = try XCTUnwrap(manager.focusedPane?.id)

        let otherFile = makeOpenFile(name: "Other.md", path: "/test/Other.md")
        let otherPaneId = try XCTUnwrap(
            manager.splitFocusedPane(axis: .horizontal, newContent: .document(openFile: otherFile))
        )
        XCTAssertEqual(manager.activeWorkspace?.focusedPaneId, otherPaneId)

        let target = makeEntry(name: "Parent.md", path: "/test/Parent.md")
        let handledWithoutLoad = state.openFileReplacingCurrentTab(
            target,
            workspaceManager: manager,
            paneId: sourcePaneId,
            pushHistory: true,
            preferExistingTab: false
        )

        XCTAssertFalse(handledWithoutLoad)
        XCTAssertEqual(manager.leaf(id: sourcePaneId)?.activeOpenFile?.path, "/test/Parent.md")
        XCTAssertEqual(manager.leaf(id: otherPaneId)?.activeOpenFile?.path, "/test/Other.md")
        XCTAssertEqual(manager.activeWorkspace?.focusedPaneId, sourcePaneId)
        XCTAssertTrue(state.openTabs.isEmpty)
    }

    func testCloseTab() {
        let state = AppState()
        state.openFile(makeEntry(name: "A.md", path: "/test/A.md"))
        state.openFile(makeEntry(name: "B.md", path: "/test/B.md"))
        XCTAssertEqual(state.openTabs.count, 2)
        state.closeTab(at: 0)
        XCTAssertEqual(state.openTabs.count, 1)
        XCTAssertEqual(state.openTabs[0].path, "/test/B.md")
    }

    func testCloseTabsForPath() {
        let state = AppState()
        state.openFile(makeEntry(name: "A.md", path: "/test/A.md"))
        state.openFile(makeEntry(name: "B.md", path: "/test/B.md"))
        state.openFile(makeEntry(name: "C.md", path: "/test/C.md"))
        XCTAssertEqual(state.openTabs.count, 3)
        state.closeTabsForPath("/test/B.md")
        XCTAssertEqual(state.openTabs.count, 2)
        XCTAssertFalse(state.openTabs.contains(where: { $0.path == "/test/B.md" }))
    }

    func testActiveTab() {
        let state = AppState()
        XCTAssertNil(state.activeTab)
        state.openFile(makeEntry())
        XCTAssertNotNil(state.activeTab)
        XCTAssertEqual(state.activeTab?.path, "/test/Test.md")
    }

    func testOpenFileInNewTab() {
        let state = AppState()
        let entry = makeEntry()
        state.openFileInNewTab(entry)
        XCTAssertEqual(state.openTabs.count, 1)
    }

    func testReorderTab() {
        let state = AppState()
        state.openFile(makeEntry(name: "A.md", path: "/test/A.md"))
        state.openFile(makeEntry(name: "B.md", path: "/test/B.md"))
        state.openFile(makeEntry(name: "C.md", path: "/test/C.md"))
        state.reorderTab(from: 0, to: 2)
        XCTAssertEqual(state.openTabs[0].path, "/test/B.md")
        XCTAssertEqual(state.openTabs[1].path, "/test/A.md")
    }

    func testNewEmptyTab() {
        let state = AppState()
        state.newEmptyTab()
        XCTAssertEqual(state.openTabs.count, 1)
        XCTAssertTrue(state.openTabs[0].isEmptyTab)
    }

    func testDisplayNameStripsMarkdownExtension() {
        let state = AppState()
        state.openFile(makeEntry(name: "My Notes.md", path: "/test/My Notes.md"))
        XCTAssertEqual(state.openTabs[0].displayName, "My Notes")
    }

    func testDisplayNamePreservesNonMarkdown() {
        let state = AppState()
        state.openFile(makeEntry(name: "Database", path: "/test/Database", kind: .database))
        XCTAssertEqual(state.openTabs[0].displayName, "Database")
    }

    func testOpenDatabaseTab() {
        let state = AppState()
        let entry = makeEntry(name: "Tasks", path: "/test/Tasks", kind: .database)
        state.openFile(entry)
        XCTAssertTrue(state.openTabs[0].isDatabase)
    }

    func testDatabaseRowNavigationPathRoundTrips() {
        let path = DatabaseRowNavigationPath.make(dbPath: "/test/Tasks", rowId: "row_123")
        let parsed = DatabaseRowNavigationPath.parse(path)
        XCTAssertEqual(parsed?.dbPath, "/test/Tasks")
        XCTAssertEqual(parsed?.rowId, "row_123")
    }

    func testHistoryRestoresDatabaseRowContext() {
        let state = AppState()
        state.openFile(makeEntry(name: "Home.md", path: "/test/Home.md"))

        let rowPath = DatabaseRowNavigationPath.make(dbPath: "/test/Tasks", rowId: "row_123")
        let rowEntry = FileEntry(
            id: rowPath,
            name: "Row Title",
            path: rowPath,
            isDirectory: false,
            kind: .databaseRow(dbPath: "/test/Tasks", rowId: "row_123")
        )

        _ = state.openFileReplacingCurrentTab(rowEntry)
        XCTAssertTrue(state.openTabs[0].isDatabaseRow)
        XCTAssertEqual(state.openTabs[0].databasePath, "/test/Tasks")
        XCTAssertEqual(state.openTabs[0].databaseRowId, "row_123")

        _ = state.goBackInActiveTab()
        let forwardEntry = state.goForwardInActiveTab()
        XCTAssertEqual(forwardEntry?.path, rowPath)
        XCTAssertEqual(forwardEntry?.databasePath, "/test/Tasks")
        XCTAssertEqual(forwardEntry?.databaseRowId, "row_123")
        XCTAssertTrue(state.openTabs[0].isDatabaseRow)
    }

    func testDefaultModeBlocksLegacyViewModeTransitions() {
        UserDefaults.standard.removeObject(forKey: BugbookFeatureGate.legacyPanesDefaultsKey)

        let state = AppState()
        XCTAssertEqual(state.currentView, .editor)
        XCTAssertFalse(state.aiSidePanelOpen)
        state.openAiPanel()
        XCTAssertFalse(state.aiSidePanelOpen)
        XCTAssertEqual(state.currentView, .editor)
        state.openGraphView()
        XCTAssertFalse(state.aiSidePanelOpen)
        XCTAssertEqual(state.currentView, .editor)
    }

    func testLegacyModeAllowsLegacyViewModeTransitions() {
        UserDefaults.standard.set(true, forKey: BugbookFeatureGate.legacyPanesDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: BugbookFeatureGate.legacyPanesDefaultsKey) }

        let state = AppState()
        XCTAssertEqual(state.currentView, .editor)
        XCTAssertFalse(state.aiSidePanelOpen)
        state.openAiPanel()
        XCTAssertTrue(state.aiSidePanelOpen)
        XCTAssertEqual(state.currentView, .editor)
        state.openGraphView()
        XCTAssertFalse(state.aiSidePanelOpen)
        XCTAssertEqual(state.currentView, .graphView)
    }

    func testDismissLegacyWorkspacePersistsAndFiltersBannerList() {
        let defaults = makeUserDefaultsSuite()
        let state = AppState(userDefaults: defaults)
        let legacyWorkspace = FileSystemService.LegacyWorkspace(
            path: URL(fileURLWithPath: "/tmp/legacy-workspace", isDirectory: true),
            kind: .applicationSupportBugbook
        )

        state.legacyWorkspaces = [legacyWorkspace]
        XCTAssertEqual(state.legacyWorkspacesNeedingAttention, [legacyWorkspace])

        state.dismissLegacyWorkspace(legacyWorkspace)

        XCTAssertTrue(state.legacyWorkspacesNeedingAttention.isEmpty)

        let reloadedState = AppState(userDefaults: defaults)
        XCTAssertTrue(reloadedState.dismissedLegacyKeys.contains(legacyWorkspace.defaultsKey))
    }
}

// MARK: - Block Model Tests

final class BlockModelTests: XCTestCase {

    func testBlockDefaultInit() {
        let block = Block()
        XCTAssertEqual(block.type, .paragraph)
        XCTAssertEqual(block.text, "")
        XCTAssertEqual(block.headingLevel, 1)
        XCTAssertFalse(block.isChecked)
        XCTAssertEqual(block.textColor, .default)
        XCTAssertEqual(block.backgroundColor, .default)
        XCTAssertTrue(block.children.isEmpty)
    }

    func testBlockEquality() {
        let id = UUID()
        let a = Block(id: id, type: .paragraph, text: "Hello")
        let b = Block(id: id, type: .paragraph, text: "Hello")
        XCTAssertEqual(a, b)
    }

    func testBlockInequality() {
        let a = Block(type: .paragraph, text: "Hello")
        let b = Block(type: .paragraph, text: "World")
        XCTAssertNotEqual(a, b)
    }

    func testAllBlockTypes() {
        let types: [BlockType] = [
            .paragraph, .heading, .bulletListItem, .numberedListItem,
            .taskItem, .codeBlock, .blockquote, .horizontalRule,
            .image, .databaseEmbed, .pageLink, .column, .toggle,
            .headingToggle, .meeting, .table, .outline, .callout, .footnote
        ]
        // Verify all types can be used in Block init
        for type in types {
            let block = Block(type: type)
            XCTAssertEqual(block.type, type)
        }
    }

    func testBlockColorAllCases() {
        XCTAssertEqual(BlockColor.allCases.count, 10)
        for color in BlockColor.allCases {
            XCTAssertFalse(color.displayName.isEmpty)
        }
    }

    func testBlockWithChildren() {
        let child1 = Block(type: .paragraph, text: "Child 1", columnIndex: 0)
        let child2 = Block(type: .paragraph, text: "Child 2", columnIndex: 1)
        let column = Block(type: .column, children: [child1, child2])
        XCTAssertEqual(column.children.count, 2)
        XCTAssertEqual(column.children[0].columnIndex, 0)
        XCTAssertEqual(column.children[1].columnIndex, 1)
    }
}
