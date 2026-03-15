import XCTest
@testable import Bugbook

// MARK: - CanvasDocument Tests

@MainActor
final class CanvasDocumentTests: XCTestCase {

    private func makeDocument() -> CanvasDocument {
        let doc = CanvasDocument()
        return doc
    }

    // MARK: Node CRUD

    func testAddTextNodeCreatesNode() {
        let doc = makeDocument()
        doc.addTextNode(at: CGPoint(x: 100, y: 200))
        XCTAssertEqual(doc.nodes.count, 1)
        XCTAssertEqual(doc.nodes[0].type, .text)
        XCTAssertEqual(doc.nodes[0].x, 100)
        XCTAssertEqual(doc.nodes[0].y, 200)
        XCTAssertEqual(doc.nodes[0].width, 300)
        XCTAssertEqual(doc.nodes[0].height, 200)
        XCTAssertTrue(doc.isDirty)
    }

    func testAddTextNodeSelectsIt() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        XCTAssertEqual(doc.selectedNodeId, doc.nodes[0].id)
    }

    func testAddTextNodeCreatesEmptyText() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        XCTAssertEqual(doc.nodeTexts[doc.nodes[0].id], "")
    }

    func testAddFileNodeCreatesNode() {
        let doc = makeDocument()
        doc.addFileNode(at: CGPoint(x: 50, y: 75), filePath: "/Users/test/notes/page.md")
        XCTAssertEqual(doc.nodes.count, 1)
        XCTAssertEqual(doc.nodes[0].type, .file)
        XCTAssertEqual(doc.nodes[0].x, 50)
        XCTAssertEqual(doc.nodes[0].height, 80)
    }

    func testRemoveNodeDeletesNode() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        let id = doc.nodes[0].id
        doc.removeNode(id: id)
        XCTAssertTrue(doc.nodes.isEmpty)
        XCTAssertNil(doc.nodeTexts[id])
    }

    func testRemoveNodeClearsSelection() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        let id = doc.nodes[0].id
        doc.selectedNodeId = id
        doc.removeNode(id: id)
        XCTAssertNil(doc.selectedNodeId)
    }

    func testRemoveNodeRemovesConnectedEdges() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        doc.addTextNode(at: CGPoint(x: 400, y: 0))
        let id1 = doc.nodes[0].id
        let id2 = doc.nodes[1].id
        doc.addEdge(from: id1, to: id2)
        XCTAssertEqual(doc.edges.count, 1)
        doc.removeNode(id: id1)
        XCTAssertTrue(doc.edges.isEmpty)
    }

    func testMoveNode() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        let id = doc.nodes[0].id
        doc.moveNode(id: id, to: CGPoint(x: 500, y: 300))
        XCTAssertEqual(doc.nodes[0].x, 500)
        XCTAssertEqual(doc.nodes[0].y, 300)
    }

    func testResizeNodeClampsMinimum() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        let id = doc.nodes[0].id
        doc.resizeNode(id: id, width: 50, height: 30)
        XCTAssertEqual(doc.nodes[0].width, 120) // min width
        XCTAssertEqual(doc.nodes[0].height, 60)  // min height
    }

    func testResizeNodeAllowsLargeValues() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        let id = doc.nodes[0].id
        doc.resizeNode(id: id, width: 800, height: 600)
        XCTAssertEqual(doc.nodes[0].width, 800)
        XCTAssertEqual(doc.nodes[0].height, 600)
    }

    func testUpdateNodeText() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        let id = doc.nodes[0].id
        doc.updateNodeText(id: id, text: "Hello World")
        XCTAssertEqual(doc.nodeTexts[id], "Hello World")
        XCTAssertTrue(doc.isDirty)
    }

    // MARK: Edge CRUD

    func testAddEdgeCreatesEdge() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        doc.addTextNode(at: CGPoint(x: 400, y: 0))
        let id1 = doc.nodes[0].id
        let id2 = doc.nodes[1].id
        doc.addEdge(from: id1, to: id2)
        XCTAssertEqual(doc.edges.count, 1)
        XCTAssertEqual(doc.edges[0].fromNode, id1)
        XCTAssertEqual(doc.edges[0].toNode, id2)
        XCTAssertEqual(doc.edges[0].toEnd, "arrow")
    }

    func testAddEdgePreventssSelfLoop() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        let id = doc.nodes[0].id
        doc.addEdge(from: id, to: id)
        XCTAssertTrue(doc.edges.isEmpty)
    }

    func testAddEdgePreventsDuplicate() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        doc.addTextNode(at: CGPoint(x: 400, y: 0))
        let id1 = doc.nodes[0].id
        let id2 = doc.nodes[1].id
        doc.addEdge(from: id1, to: id2)
        doc.addEdge(from: id1, to: id2)
        XCTAssertEqual(doc.edges.count, 1)
    }

    func testAddEdgeWithSides() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        doc.addTextNode(at: CGPoint(x: 400, y: 0))
        let id1 = doc.nodes[0].id
        let id2 = doc.nodes[1].id
        doc.addEdge(from: id1, to: id2, fromSide: "right", toSide: "left")
        XCTAssertEqual(doc.edges[0].fromSide, "right")
        XCTAssertEqual(doc.edges[0].toSide, "left")
    }

    func testRemoveEdge() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        doc.addTextNode(at: CGPoint(x: 400, y: 0))
        doc.addEdge(from: doc.nodes[0].id, to: doc.nodes[1].id)
        let edgeId = doc.edges[0].id
        doc.selectedEdgeId = edgeId
        doc.removeEdge(id: edgeId)
        XCTAssertTrue(doc.edges.isEmpty)
        XCTAssertNil(doc.selectedEdgeId)
    }

    // MARK: Selection

    func testClearSelection() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        doc.selectedNodeId = doc.nodes[0].id
        doc.editingNodeId = doc.nodes[0].id
        doc.clearSelection()
        XCTAssertNil(doc.selectedNodeId)
        XCTAssertNil(doc.editingNodeId)
        XCTAssertTrue(doc.selectedNodeIds.isEmpty)
    }

    func testToggleNodeSelection() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        doc.addTextNode(at: CGPoint(x: 400, y: 0))
        let id1 = doc.nodes[0].id
        let id2 = doc.nodes[1].id
        // After second addTextNode, selectedNodeIds = [id2]
        doc.clearSelection()
        // Start fresh
        doc.toggleNodeSelection(id1)
        XCTAssertEqual(doc.selectedNodeIds, [id1])
        doc.toggleNodeSelection(id2)
        XCTAssertEqual(doc.selectedNodeIds.count, 2)
        XCTAssertTrue(doc.selectedNodeIds.contains(id1))
        XCTAssertTrue(doc.selectedNodeIds.contains(id2))
        doc.toggleNodeSelection(id1)
        XCTAssertEqual(doc.selectedNodeIds, [id2])
    }

    func testSelectedNodeIdSingleSelect() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        doc.addTextNode(at: CGPoint(x: 400, y: 0))
        doc.selectedNodeId = doc.nodes[0].id
        XCTAssertEqual(doc.selectedNodeId, doc.nodes[0].id)
        XCTAssertEqual(doc.selectedNodeIds.count, 1)
    }

    func testSelectedNodeIdNilWhenMultiple() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        doc.addTextNode(at: CGPoint(x: 400, y: 0))
        doc.selectedNodeIds = [doc.nodes[0].id, doc.nodes[1].id]
        XCTAssertNil(doc.selectedNodeId) // nil when multiple selected
    }

    // MARK: Undo/Redo

    func testUndoRestoresPreviousState() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        XCTAssertEqual(doc.nodes.count, 1)
        doc.undo()
        XCTAssertTrue(doc.nodes.isEmpty)
    }

    func testRedoRestoresUndoneState() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        let nodeId = doc.nodes[0].id
        doc.undo()
        XCTAssertTrue(doc.nodes.isEmpty)
        doc.redo()
        XCTAssertEqual(doc.nodes.count, 1)
        XCTAssertEqual(doc.nodes[0].id, nodeId)
    }

    func testUndoOnEmptyStackDoesNothing() {
        let doc = makeDocument()
        doc.undo() // should not crash
        XCTAssertTrue(doc.nodes.isEmpty)
    }

    func testRedoOnEmptyStackDoesNothing() {
        let doc = makeDocument()
        doc.redo() // should not crash
        XCTAssertTrue(doc.nodes.isEmpty)
    }

    func testMultipleUndos() {
        let doc = makeDocument()
        doc.addTextNode(at: .zero)
        doc.addTextNode(at: CGPoint(x: 400, y: 0))
        doc.addTextNode(at: CGPoint(x: 800, y: 0))
        XCTAssertEqual(doc.nodes.count, 3)
        doc.undo()
        XCTAssertEqual(doc.nodes.count, 2)
        doc.undo()
        XCTAssertEqual(doc.nodes.count, 1)
        doc.undo()
        XCTAssertEqual(doc.nodes.count, 0)
    }

    // MARK: Relative Path

    func testRelativePathSameDirectory() {
        let result = CanvasDocument.relativePath(from: "/notes/canvas", to: "/notes/canvas/file.md")
        XCTAssertEqual(result, "file.md")
    }

    func testRelativePathSiblingDirectory() {
        let result = CanvasDocument.relativePath(from: "/notes/canvas", to: "/notes/pages/file.md")
        XCTAssertEqual(result, "../pages/file.md")
    }

    func testRelativePathDeeplyNested() {
        let result = CanvasDocument.relativePath(from: "/a/b/c", to: "/a/x/y/z.md")
        XCTAssertEqual(result, "../../x/y/z.md")
    }

    // MARK: File Node Display Name

    func testFileNodeDisplayNameMarkdown() {
        let node = CanvasNodeMeta(id: "n1", type: .file, x: 0, y: 0, width: 300, height: 80, file: "path/to/My Note.md")
        let doc = makeDocument()
        XCTAssertEqual(doc.fileNodeDisplayName(for: node), "My Note")
    }

    func testFileNodeDisplayNameNonMarkdown() {
        let node = CanvasNodeMeta(id: "n1", type: .file, x: 0, y: 0, width: 300, height: 80, file: "image.png")
        let doc = makeDocument()
        XCTAssertEqual(doc.fileNodeDisplayName(for: node), "image.png")
    }

    func testFileNodeDisplayNameNilFile() {
        let node = CanvasNodeMeta(id: "n1", type: .file, x: 0, y: 0, width: 300, height: 80)
        let doc = makeDocument()
        XCTAssertEqual(doc.fileNodeDisplayName(for: node), "Unknown")
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

    func testMarkdownRoundTrip() {
        let md = "# Title\n\nSome text here\n\n- List item 1\n- List item 2\n"
        let doc = BlockDocument(markdown: md)
        let output = doc.markdown
        // Should contain the same content elements
        XCTAssertTrue(output.contains("Title"))
        XCTAssertTrue(output.contains("Some text here"))
        XCTAssertTrue(output.contains("List item 1"))
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

    func testChangeBlockTypeToFlashcardStartsCollapsed() {
        let doc = BlockDocument(markdown: "# Title\nQuestion\n")
        guard doc.blocks.count >= 2 else {
            XCTFail("Expected at least 2 blocks")
            return
        }

        let paragraphId = doc.blocks[1].id
        doc.changeBlockType(id: paragraphId, to: .flashcard)

        XCTAssertEqual(doc.blocks[1].type, .flashcard)
        XCTAssertFalse(doc.blocks[1].isExpanded)
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

    func testMarkdownRoundTripsFlashcardBlocks() {
        let markdown = """
        # Title
        <!-- flashcard collapsed -->
        Front of card
        Back paragraph
        - Back bullet
        <!-- /flashcard -->
        """

        let doc = BlockDocument(markdown: markdown)
        XCTAssertEqual(doc.blocks.count, 2)
        XCTAssertEqual(doc.blocks[1].type, .flashcard)
        XCTAssertEqual(doc.blocks[1].text, "Front of card")
        XCTAssertFalse(doc.blocks[1].isExpanded)
        XCTAssertEqual(doc.blocks[1].children.count, 2)
        XCTAssertEqual(doc.blocks[1].children[0].text, "Back paragraph")
        XCTAssertEqual(doc.blocks[1].children[1].type, .bulletListItem)

        let output = doc.markdown
        XCTAssertTrue(output.contains("<!-- flashcard collapsed -->"))
        XCTAssertTrue(output.contains("<!-- /flashcard -->"))

        let reparsed = BlockDocument(markdown: output)
        XCTAssertEqual(reparsed.blocks[1].type, .flashcard)
        XCTAssertEqual(reparsed.blocks[1].text, "Front of card")
        XCTAssertFalse(reparsed.blocks[1].isExpanded)
        XCTAssertEqual(reparsed.blocks[1].children.count, 2)
        XCTAssertEqual(reparsed.blocks[1].children[0].text, "Back paragraph")
        XCTAssertEqual(reparsed.blocks[1].children[1].type, .bulletListItem)
    }
}

// MARK: - AppState Tests

@MainActor
final class AppStateTests: XCTestCase {

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

    func testOpenCanvasTab() {
        let state = AppState()
        let entry = makeEntry(name: "Canvas", path: "/test/Canvas", kind: .canvas)
        state.openFile(entry)
        XCTAssertTrue(state.openTabs[0].isCanvas)
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

    func testViewModeTransitions() {
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
}

// MARK: - Canvas Model Tests

final class CanvasModelTests: XCTestCase {

    func testCanvasViewportCodable() throws {
        let viewport = CanvasViewport(x: 100, y: -200, zoom: 1.5)
        let data = try JSONEncoder().encode(viewport)
        let decoded = try JSONDecoder().decode(CanvasViewport.self, from: data)
        XCTAssertEqual(decoded.x, 100)
        XCTAssertEqual(decoded.y, -200)
        XCTAssertEqual(decoded.zoom, 1.5)
    }

    func testCanvasNodeMetaCodable() throws {
        let node = CanvasNodeMeta(
            id: "test_node",
            type: .text,
            x: 50, y: 75,
            width: 300, height: 200,
            file: nil,
            color: "blue"
        )
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(CanvasNodeMeta.self, from: data)
        XCTAssertEqual(decoded.id, "test_node")
        XCTAssertEqual(decoded.type, .text)
        XCTAssertEqual(decoded.color, "blue")
    }

    func testCanvasEdgeMetaCodable() throws {
        let edge = CanvasEdgeMeta(
            id: "edge_1",
            fromNode: "n1",
            toNode: "n2",
            fromSide: "right",
            toSide: "left",
            toEnd: "arrow",
            label: "connects to",
            color: "red"
        )
        let data = try JSONEncoder().encode(edge)
        let decoded = try JSONDecoder().decode(CanvasEdgeMeta.self, from: data)
        XCTAssertEqual(decoded.id, "edge_1")
        XCTAssertEqual(decoded.fromSide, "right")
        XCTAssertEqual(decoded.label, "connects to")
    }

    func testCanvasFileMetaCodable() throws {
        let meta = CanvasFileMeta(
            id: "canvas_1",
            name: "My Canvas",
            version: 1,
            viewport: CanvasViewport(x: 0, y: 0, zoom: 1.0),
            nodes: [
                CanvasNodeMeta(id: "n1", type: .text, x: 0, y: 0, width: 300, height: 200)
            ],
            edges: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(meta)
        let decoded = try JSONDecoder().decode(CanvasFileMeta.self, from: data)
        XCTAssertEqual(decoded.name, "My Canvas")
        XCTAssertEqual(decoded.nodes.count, 1)
    }

    func testCanvasNodeTypeRawValues() {
        XCTAssertEqual(CanvasNodeType.text.rawValue, "text")
        XCTAssertEqual(CanvasNodeType.file.rawValue, "file")
        XCTAssertEqual(CanvasNodeType.image.rawValue, "image")
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
            .image, .databaseEmbed, .pageLink, .column, .toggle, .flashcard
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
