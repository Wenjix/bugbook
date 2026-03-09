import XCTest
import ArgumentParser
import Foundation
import BugbookCore
import Darwin
@testable import BugbookCLI

final class BugbookCLITests: XCTestCase {
    func testPageCommandsAndBacklinksSmoke() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/2026-03-07",
                "--content-file", try writeTempFile(in: workspace, name: "strategy.md", contents: """
                ---
                aliases:
                  - Strategy Alias
                ---

                # Bugbook Strategy

                Human habit first.
                """)
            ])
        )

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Linking Note",
                "--content-file", try writeTempFile(in: workspace, name: "linking.md", contents: """
                # Linking Note

                See [[Bugbook Strategy]] and #strategy.
                """)
            ])
        )

        let appended = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy",
                "--append-file", try writeTempFile(in: workspace, name: "append.md", contents: "\n## Next\n\nFocus on trust.\n")
            ])
        )
        XCTAssertEqual(appended["title"] as? String, "Bugbook Strategy")
        XCTAssertTrue((appended["content"] as? String)?.contains("## Next") == true)

        let fetched = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy"
            ])
        )
        XCTAssertEqual(fetched["relative_path"] as? String, "Notes/2026-03-07.md")

        let backlinks = try runJSON(
            Backlinks.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy"
            ])
        )
        XCTAssertEqual(backlinks["total_count"] as? Int, 1)
        let results = try XCTUnwrap(backlinks["results"] as? [[String: Any]])
        XCTAssertEqual(results.first?["title"] as? String, "Linking Note")
    }

    func testPageUpdateRejectsReplacementCombinedWithAppend() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Target",
                "--title", "Target"
            ])
        )

        let replacementPath = try writeTempFile(in: workspace, name: "replacement.md", contents: "# Target\n\nReplacement\n")
        let appendPath = try writeTempFile(in: workspace, name: "append.md", contents: "\nExtra\n")
        var command = try Page.Update.parseAsRoot([
            "--workspace", workspace,
            "Target",
            "--content-file", replacementPath,
            "--append-file", appendPath
        ])

        XCTAssertThrowsError(try command.run()) { error in
            guard case CLIError.invalidInput(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("--content-file"))
        }
    }

    func testPageGetSupportsRawMarkdownAndBlocks() throws {
        let workspace = try makeWorkspace()
        let pageContent = """
        ---
        title: Structured Note
        ---
        <!-- icon:bolt.fill -->
        <!-- full-width -->

        # Structured Note

        - First bullet
        - [x] Done item
        [[Another Page]]
        """

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Structured Note",
                "--content-file", try writeTempFile(in: workspace, name: "structured.md", contents: pageContent)
            ])
        )

        let raw = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Structured Note",
                "--raw"
            ])
            try command.run()
        }
        XCTAssertEqual(raw, pageContent)

        let blocks = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Structured Note",
                "--blocks"
            ])
        )

        let metadata = try XCTUnwrap(blocks["document_metadata"] as? [String: Any])
        XCTAssertEqual(metadata["icon"] as? String, "bolt.fill")
        XCTAssertEqual(metadata["full_width"] as? Bool, true)

        let items = try XCTUnwrap(blocks["blocks"] as? [[String: Any]])
        let semanticItems = items.filter { item in
            let type = item["type"] as? String
            let text = item["text"] as? String
            return type != "paragraph" || !(text ?? "").isEmpty
        }

        XCTAssertEqual(semanticItems[0]["type"] as? String, "heading")
        XCTAssertEqual(semanticItems[0]["text"] as? String, "Structured Note")
        XCTAssertEqual(semanticItems[1]["type"] as? String, "bullet_list_item")
        XCTAssertEqual(semanticItems[2]["type"] as? String, "task_item")
        XCTAssertEqual(semanticItems[2]["checked"] as? Bool, true)
        XCTAssertEqual(semanticItems[3]["type"] as? String, "page_link")
        XCTAssertEqual(semanticItems[3]["page_name"] as? String, "Another Page")
    }

    func testPageGetRawStripsInternalBlockIDsUnlessRequested() throws {
        let workspace = try makeWorkspace()
        let blockID = "11111111-1111-1111-1111-111111111111"
        let content = """
        <!-- block-id: \(blockID) -->
        # Raw Note

        <!-- block-id: 22222222-2222-2222-2222-222222222222 -->
        Body
        """

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Raw Note",
                "--content-file", try writeTempFile(in: workspace, name: "raw-note.md", contents: content)
            ])
        )

        let defaultRaw = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Raw Note",
                "--raw"
            ])
            try command.run()
        }
        XCTAssertFalse(defaultRaw.contains("<!-- block-id:"))
        XCTAssertTrue(defaultRaw.contains("# Raw Note"))
        XCTAssertTrue(defaultRaw.contains("Body"))

        let fileRaw = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Raw Note",
                "--raw",
                "--include-internal-comments"
            ])
            try command.run()
        }
        XCTAssertTrue(fileRaw.contains("<!-- block-id: \(blockID) -->"))
    }

    func testPageUpdateCanTargetMarkdownSection() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Plan",
                "--content-file", try writeTempFile(in: workspace, name: "plan.md", contents: """
                # Plan

                ## Roadmap
                Keep this scoped.

                ## Notes
                Leave this alone.
                """)
            ])
        )

        let appended = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Plan",
                "--section", "Roadmap",
                "--append-file", try writeTempFile(in: workspace, name: "roadmap-append.md", contents: """
                - Add raw markdown mode
                - Add block JSON mode
                """)
            ])
        )

        let appendedBody = try XCTUnwrap(appended["body"] as? String)
        XCTAssertTrue(appendedBody.contains("## Roadmap\nKeep this scoped.\n\n- Add raw markdown mode\n- Add block JSON mode"))
        XCTAssertTrue(appendedBody.contains("## Notes\nLeave this alone."))

        let replaced = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Plan",
                "--section", "Notes",
                "--content-file", try writeTempFile(in: workspace, name: "notes-replacement.md", contents: """
                Fresh notes only.
                """)
            ])
        )

        let replacedBody = try XCTUnwrap(replaced["body"] as? String)
        XCTAssertTrue(replacedBody.contains("## Notes\nFresh notes only."))
        XCTAssertFalse(replacedBody.contains("Leave this alone."))
        XCTAssertTrue(replacedBody.contains("- Add raw markdown mode"))
    }

    func testPageHeadingsAndSectionCreation() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Heading Note",
                "--content-file", try writeTempFile(in: workspace, name: "headings.md", contents: """
                ---
                title: Heading Note
                ---

                # Heading Note

                ## Existing
                Already here.
                """)
            ])
        )

        let headings = try runJSON(
            Page.Headings.parseAsRoot([
                "--workspace", workspace,
                "Heading Note"
            ])
        )
        let headingItems = try XCTUnwrap(headings["headings"] as? [[String: Any]])
        XCTAssertEqual(headingItems.count, 2)
        XCTAssertEqual(headingItems[0]["title"] as? String, "Heading Note")
        XCTAssertEqual(headingItems[0]["line"] as? Int, 5)
        XCTAssertEqual(headingItems[1]["title"] as? String, "Existing")
        XCTAssertEqual(headingItems[1]["level"] as? Int, 2)

        let updated = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Heading Note",
                "--section", "Roadmap",
                "--create-section",
                "--section-level", "2",
                "--content-file", try writeTempFile(in: workspace, name: "roadmap.md", contents: """
                Add heading discovery.
                """)
            ])
        )

        let body = try XCTUnwrap(updated["body"] as? String)
        XCTAssertTrue(body.contains("## Roadmap\n\nAdd heading discovery."))
    }

    func testPageGetAndUpdateCanTargetSectionLine() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Repeated Headings",
                "--content-file", try writeTempFile(in: workspace, name: "repeated-headings.md", contents: """
                # Repeated Headings

                ## Notes
                First section.

                ## Notes
                Second section.
                """)
            ])
        )

        let fetched = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Repeated Headings",
                "--section-line", "6"
            ])
        )

        let selectedSection = try XCTUnwrap(fetched["selected_section"] as? [String: Any])
        XCTAssertEqual(selectedSection["title"] as? String, "Notes")
        XCTAssertEqual(selectedSection["heading_line"] as? Int, 6)
        XCTAssertEqual(selectedSection["body"] as? String, "Second section.")

        let updated = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Repeated Headings",
                "--section-line", "6",
                "--content-file", try writeTempFile(in: workspace, name: "notes-update.md", contents: """
                Updated second section.
                """)
            ])
        )

        let body = try XCTUnwrap(updated["body"] as? String)
        XCTAssertTrue(body.contains("## Notes\nFirst section."))
        XCTAssertTrue(body.contains("## Notes\nUpdated second section."))
        XCTAssertFalse(body.contains("Second section."))
    }

    func testPageGetRespectsExplicitHeadingLevelSelectors() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Level Selectors",
                "--content-file", try writeTempFile(in: workspace, name: "level-selectors.md", contents: """
                # Level Selectors

                ## Roadmap
                Parent section.

                ### Roadmap
                Nested section.
                """)
            ])
        )

        let fetched = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Level Selectors",
                "--section", "### Roadmap"
            ])
        )

        let selectedSection = try XCTUnwrap(fetched["selected_section"] as? [String: Any])
        XCTAssertEqual(selectedSection["level"] as? Int, 3)
        XCTAssertEqual(selectedSection["heading_line"] as? Int, 6)
        XCTAssertEqual(selectedSection["body"] as? String, "Nested section.")
    }

    func testPageGetSectionSelectorsRejectMissingMatches() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Missing Selector",
                "--content-file", try writeTempFile(in: workspace, name: "missing-selector.md", contents: """
                # Missing Selector

                ## Present
                Exists.
                """)
            ])
        )

        var missingHeading = try Page.Get.parseAsRoot([
            "--workspace", workspace,
            "Missing Selector",
            "--section", "Absent"
        ])

        XCTAssertThrowsError(try missingHeading.run()) { error in
            guard case CLIError.invalidInput(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("Heading not found"))
        }

        var missingLine = try Page.Get.parseAsRoot([
            "--workspace", workspace,
            "Missing Selector",
            "--section-line", "99"
        ])

        XCTAssertThrowsError(try missingLine.run()) { error in
            guard case CLIError.invalidInput(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("Heading not found"))
        }
    }

    func testPageUpdateDryRunPreviewsSectionCreationWithoutWriting() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Preview Note",
                "--content-file", try writeTempFile(in: workspace, name: "preview-note.md", contents: """
                # Preview Note

                Existing content.
                """)
            ])
        )

        let preview = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Preview Note",
                "--section", "Roadmap",
                "--create-section",
                "--section-level", "2",
                "--content-file", try writeTempFile(in: workspace, name: "preview-roadmap.md", contents: """
                Planned change.
                """),
                "--dry-run"
            ])
        )

        XCTAssertEqual(preview["dry_run"] as? Bool, true)
        XCTAssertEqual(preview["changed"] as? Bool, true)
        XCTAssertNil(preview["selected_section_before"])

        let selectedSection = try XCTUnwrap(preview["selected_section"] as? [String: Any])
        XCTAssertEqual(selectedSection["title"] as? String, "Roadmap")
        XCTAssertEqual(selectedSection["level"] as? Int, 2)

        let previewBody = try XCTUnwrap(preview["body"] as? String)
        XCTAssertTrue(previewBody.contains("## Roadmap\n\nPlanned change."))

        let lineChanges = try XCTUnwrap(preview["line_changes"] as? [[String: Any]])
        XCTAssertTrue(lineChanges.contains { change in
            change["op"] as? String == "insert" && change["text"] as? String == "## Roadmap"
        })

        let fetched = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Preview Note"
            ])
        )
        XCTAssertFalse((fetched["body"] as? String)?.contains("## Roadmap") == true)
    }

    func testPageUpdateSummaryOutputAvoidsFullPagePayloads() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Summary Mode",
                "--content-file", try writeTempFile(in: workspace, name: "summary-mode.md", contents: """
                # Summary Mode

                ## Roadmap
                Ship the basics.
                """)
            ])
        )

        let preview = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Summary Mode",
                "--section", "Roadmap",
                "--append-file", try writeTempFile(in: workspace, name: "summary-append.md", contents: """
                - Add quieter writes
                """),
                "--dry-run",
                "--output", "summary"
            ])
        )

        XCTAssertEqual(preview["dry_run"] as? Bool, true)
        XCTAssertEqual(preview["updated"] as? Bool, true)
        XCTAssertEqual(preview["changed"] as? Bool, true)
        XCTAssertNil(preview["content"])
        XCTAssertNil(preview["body"])
        let selectedSection = try XCTUnwrap(preview["selected_section"] as? [String: Any])
        XCTAssertEqual(selectedSection["title"] as? String, "Roadmap")
        XCTAssertNil(selectedSection["content"])

        let updated = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Summary Mode",
                "--section", "Roadmap",
                "--append-file", try writeTempFile(in: workspace, name: "summary-apply.md", contents: """
                - Add quieter writes
                """),
                "--output", "summary"
            ])
        )

        XCTAssertEqual(updated["updated"] as? Bool, true)
        XCTAssertEqual(updated["changed"] as? Bool, true)
        XCTAssertNil(updated["content"])
        XCTAssertNil(updated["body"])
    }

    func testPageCompactRemovesEmptyParagraphGaps() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Compact Me",
                "--content-file", try writeTempFile(in: workspace, name: "compact-me.md", contents: """
                # Compact Me

                Updated March 7, 2026

                ---

                ## Roadmap

                First paragraph.

                Second paragraph.
                """)
            ])
        )

        let preview = try runJSON(
            Page.Compact.parseAsRoot([
                "--workspace", workspace,
                "Compact Me",
                "--dry-run",
                "--output", "summary"
            ])
        )
        XCTAssertEqual(preview["dry_run"] as? Bool, true)
        XCTAssertEqual(preview["operation"] as? String, "compact")
        XCTAssertEqual(preview["changed"] as? Bool, true)
        XCTAssertEqual(preview["empty_paragraphs_removed"] as? Int, 5)
        XCTAssertNil(preview["content"])
        XCTAssertNil(preview["body"])

        let updated = try runJSON(
            Page.Compact.parseAsRoot([
                "--workspace", workspace,
                "Compact Me"
            ])
        )

        let body = try XCTUnwrap(updated["body"] as? String)
        XCTAssertEqual(updated["empty_paragraphs_removed"] as? Int, 5)
        XCTAssertEqual(body, """
        # Compact Me
        Updated March 7, 2026
        ---
        ## Roadmap
        First paragraph.
        Second paragraph.
        """)

        let blocks = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Compact Me",
                "--blocks"
            ])
        )
        let blockItems = try XCTUnwrap(blocks["blocks"] as? [[String: Any]])
        XCTAssertFalse(blockItems.contains { block in
            (block["type"] as? String) == "paragraph" && ((block["text"] as? String) ?? "").isEmpty
        })
    }

    func testPageCompactPreservesPersistedBlockIDs() throws {
        let workspace = try makeWorkspace()
        let headingID = "11111111-1111-1111-1111-111111111111"
        let bodyID = "22222222-2222-2222-2222-222222222222"

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Compact With IDs",
                "--content-file", try writeTempFile(in: workspace, name: "compact-with-ids.md", contents: """
                <!-- block-id: \(headingID) -->
                # Compact With IDs

                <!-- block-id: \(bodyID) -->
                Paragraph body.
                """)
            ])
        )

        _ = try runJSON(
            Page.Compact.parseAsRoot([
                "--workspace", workspace,
                "Compact With IDs"
            ])
        )

        let raw = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Compact With IDs",
                "--raw",
                "--include-internal-comments"
            ])
            try command.run()
        }

        XCTAssertTrue(raw.contains("<!-- block-id: \(headingID) -->"))
        XCTAssertTrue(raw.contains("<!-- block-id: \(bodyID) -->"))
        XCTAssertFalse(raw.contains("\n\n"))
    }

    func testPageCompactSummaryUsesPostWriteModifiedAt() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Compact Summary",
                "--content-file", try writeTempFile(in: workspace, name: "compact-summary.md", contents: """
                # Compact Summary

                Paragraph
                """)
            ])
        )

        usleep(1_100_000)

        let summary = try runJSON(
            Page.Compact.parseAsRoot([
                "--workspace", workspace,
                "Compact Summary",
                "--output", "summary"
            ])
        )

        let fetched = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Compact Summary"
            ])
        )

        XCTAssertEqual(summary["modified_at"] as? String, fetched["modified_at"] as? String)
    }

    func testPageFormatCommonMarkAddsStructuralBlankLines() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Format CommonMark",
                "--content-file", try writeTempFile(in: workspace, name: "format-commonmark.md", contents: """
                # Format CommonMark
                First paragraph
                Second paragraph
                - First bullet
                - Second bullet
                ## Next
                Tail paragraph
                """)
            ])
        )

        let preview = try runJSON(
            Page.Format.parseAsRoot([
                "--workspace", workspace,
                "Format CommonMark",
                "--style", "commonmark",
                "--dry-run",
                "--output", "summary"
            ])
        )

        XCTAssertEqual(preview["operation"] as? String, "format")
        XCTAssertEqual(preview["format_style"] as? String, "commonmark")
        XCTAssertEqual(preview["changed"] as? Bool, true)

        let updated = try runJSON(
            Page.Format.parseAsRoot([
                "--workspace", workspace,
                "Format CommonMark",
                "--style", "commonmark"
            ])
        )

        XCTAssertEqual(updated["format_style"] as? String, "commonmark")
        let body = try XCTUnwrap(updated["body"] as? String)
        XCTAssertEqual(body, """
        # Format CommonMark

        First paragraph

        Second paragraph

        - First bullet
        - Second bullet

        ## Next

        Tail paragraph
        """)
    }

    func testPageFormatCommonMarkRemovesBugbookCommentSyntax() throws {
        let workspace = try makeWorkspace()
        let blockID = "11111111-1111-1111-1111-111111111111"

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Format Portable",
                "--content-file", try writeTempFile(in: workspace, name: "format-portable.md", contents: """
                <!-- block-id: \(blockID) -->
                # Format Portable
                <!-- toggle -->
                Toggle Title
                Toggle body
                <!-- /toggle -->
                <!-- columns -->
                Left column
                <!-- column-separator -->
                Right column
                <!-- /columns -->
                <!-- database: /tmp/Bugbook/databases/Test Board -->
                """)
            ])
        )

        _ = try runJSON(
            Page.Format.parseAsRoot([
                "--workspace", workspace,
                "Format Portable",
                "--style", "commonmark"
            ])
        )

        let raw = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Format Portable",
                "--raw",
                "--include-internal-comments"
            ])
            try command.run()
        }

        XCTAssertFalse(raw.contains("<!-- block-id:"))
        XCTAssertFalse(raw.contains("<!-- toggle"))
        XCTAssertFalse(raw.contains("<!-- columns -->"))
        XCTAssertFalse(raw.contains("<!-- database:"))
        XCTAssertTrue(raw.contains("<details open>"))
        XCTAssertTrue(raw.contains("<summary>Toggle Title</summary>"))
        XCTAssertTrue(raw.contains("Left column\n\n---\n\nRight column"))
        XCTAssertTrue(raw.contains("**Bugbook database:** Test Board"))
    }

    func testPageFormatReportSurfacesDowngradedCommonMarkLinks() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Source Note",
                "--content-file", try writeTempFile(in: workspace, name: "source-note-report.md", contents: """
                # Source Note
                [[Target Note]]
                [[Missing Note]]
                [[Shared]]
                """)
            ])
        )

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Target Note",
                "--content-file", try writeTempFile(in: workspace, name: "target-note-report.md", contents: """
                # Target Note
                Linked target.
                """)
            ])
        )

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Area/Shared",
                "--content-file", try writeTempFile(in: workspace, name: "shared-area-report.md", contents: """
                # Shared
                First shared page.
                """)
            ])
        )

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Elsewhere/Shared",
                "--content-file", try writeTempFile(in: workspace, name: "shared-elsewhere-report.md", contents: """
                # Shared
                Second shared page.
                """)
            ])
        )

        let preview = try runJSON(
            Page.Format.parseAsRoot([
                "--workspace", workspace,
                "Notes/Source Note",
                "--style", "commonmark",
                "--dry-run",
                "--output", "summary",
                "--report"
            ])
        )

        XCTAssertEqual(preview["warning_count"] as? Int, 2)
        let warnings = try XCTUnwrap(preview["warnings"] as? [[String: Any]])
        XCTAssertEqual(warnings.count, 2)

        let missing = try XCTUnwrap(warnings.first { ($0["page_name"] as? String) == "Missing Note" })
        XCTAssertEqual(missing["kind"] as? String, "downgraded_page_link")
        XCTAssertEqual(missing["block_id"] as? String, "path:2")
        XCTAssertEqual(missing["reason"] as? String, "page_not_found")
        XCTAssertNil(missing["matches"])

        let ambiguous = try XCTUnwrap(warnings.first { ($0["page_name"] as? String) == "Shared" })
        XCTAssertEqual(ambiguous["block_id"] as? String, "path:3")
        XCTAssertEqual(ambiguous["reason"] as? String, "ambiguous_page_reference")
        let matches = try XCTUnwrap(ambiguous["matches"] as? [String])
        XCTAssertEqual(matches, ["Area/Shared.md", "Elsewhere/Shared.md"])
    }

    func testPageFormatReportCanConfirmNoWarnings() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Clean Links",
                "--content-file", try writeTempFile(in: workspace, name: "clean-links.md", contents: """
                # Clean Links
                [[Target Note]]
                """)
            ])
        )

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Target Note",
                "--content-file", try writeTempFile(in: workspace, name: "clean-target.md", contents: """
                # Target Note
                Linked target.
                """)
            ])
        )

        let preview = try runJSON(
            Page.Format.parseAsRoot([
                "--workspace", workspace,
                "Notes/Clean Links",
                "--style", "commonmark",
                "--dry-run",
                "--output", "summary",
                "--report"
            ])
        )

        XCTAssertEqual(preview["warning_count"] as? Int, 0)
        let warnings = try XCTUnwrap(preview["warnings"] as? [[String: Any]])
        XCTAssertTrue(warnings.isEmpty)
    }

    func testPageFormatFailOnWarningsRejectsDowngradedCommonMarkExport() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Source Note",
                "--content-file", try writeTempFile(in: workspace, name: "source-note-fail.md", contents: """
                # Source Note
                [[Missing Note]]
                """)
            ])
        )

        var format = try Page.Format.parseAsRoot([
            "--workspace", workspace,
            "Notes/Source Note",
            "--style", "commonmark",
            "--fail-on-warnings"
        ])

        XCTAssertThrowsError(try format.run()) { error in
            guard case CLIError.operationFailed(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("produced 1 warning"))
            XCTAssertTrue(message.contains("Missing Note"))
            XCTAssertTrue(message.contains("--report"))
        }

        let raw = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Notes/Source Note",
                "--raw"
            ])
            try command.run()
        }
        XCTAssertTrue(raw.contains("[[Missing Note]]"))
    }

    func testPageFormatFailOnWarningsAllowsCleanCommonMarkExport() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Clean Source",
                "--content-file", try writeTempFile(in: workspace, name: "clean-source-fail.md", contents: """
                # Clean Source
                [[Target Note]]
                """)
            ])
        )

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Target Note",
                "--content-file", try writeTempFile(in: workspace, name: "clean-target-fail.md", contents: """
                # Target Note
                Linked target.
                """)
            ])
        )

        let result = try runJSON(
            Page.Format.parseAsRoot([
                "--workspace", workspace,
                "Notes/Clean Source",
                "--style", "commonmark",
                "--fail-on-warnings",
                "--output", "summary"
            ])
        )

        XCTAssertEqual(result["format_style"] as? String, "commonmark")
        XCTAssertEqual(result["changed"] as? Bool, true)

        let raw = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Notes/Clean Source",
                "--raw"
            ])
            try command.run()
        }
        XCTAssertTrue(raw.contains("[Target Note](<Target Note.md>)"))
    }

    func testPageFormatCommonMarkResolvesPageLinksToPortableMarkdownLinks() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Source Note",
                "--content-file", try writeTempFile(in: workspace, name: "source-note.md", contents: """
                # Source Note
                [[Target Note]]
                [[Projects/Project Brief]]
                [[Missing Note]]
                [[Shared]]
                """)
            ])
        )

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Target Note",
                "--content-file", try writeTempFile(in: workspace, name: "target-note.md", contents: """
                # Target Note
                Linked target.
                """)
            ])
        )

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Projects/Project Brief",
                "--content-file", try writeTempFile(in: workspace, name: "project-brief.md", contents: """
                # Project Brief
                Sibling folder target.
                """)
            ])
        )

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Archives/Other",
                "--content-file", try writeTempFile(in: workspace, name: "title-collision.md", contents: """
                ---
                title: Target Note
                ---
                # Different File
                Title-only collision.
                """)
            ])
        )

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Area/Shared",
                "--content-file", try writeTempFile(in: workspace, name: "shared-area.md", contents: """
                # Shared
                First shared page.
                """)
            ])
        )

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Elsewhere/Shared",
                "--content-file", try writeTempFile(in: workspace, name: "shared-elsewhere.md", contents: """
                # Shared
                Second shared page.
                """)
            ])
        )

        _ = try runJSON(
            Page.Format.parseAsRoot([
                "--workspace", workspace,
                "Notes/Source Note",
                "--style", "commonmark"
            ])
        )

        let raw = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Notes/Source Note",
                "--raw"
            ])
            try command.run()
        }

        XCTAssertTrue(raw.contains("[Target Note](<Target Note.md>)"))
        XCTAssertTrue(raw.contains("[Projects/Project Brief](<../Projects/Project Brief.md>)"))
        XCTAssertTrue(raw.contains("\n\nMissing Note\n\n"))
        XCTAssertTrue(raw.contains("\n\nShared"))
        XCTAssertFalse(raw.contains("[[Target Note]]"))
        XCTAssertFalse(raw.contains("[[Projects/Project Brief]]"))
        XCTAssertFalse(raw.contains("[[Missing Note]]"))
        XCTAssertFalse(raw.contains("[[Shared]]"))
    }

    func testPageFormatBugbookMatchesCompactShortcut() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Format Bugbook",
                "--content-file", try writeTempFile(in: workspace, name: "format-bugbook.md", contents: """
                # Format Bugbook

                Paragraph one

                Paragraph two
                """)
            ])
        )

        let formatted = try runJSON(
            Page.Format.parseAsRoot([
                "--workspace", workspace,
                "Format Bugbook",
                "--style", "bugbook"
            ])
        )

        let compacted = try runJSON(
            Page.Compact.parseAsRoot([
                "--workspace", workspace,
                "Format Bugbook"
            ])
        )

        XCTAssertEqual(formatted["format_style"] as? String, "bugbook")
        XCTAssertEqual(formatted["body"] as? String, compacted["body"] as? String)
        XCTAssertFalse((formatted["body"] as? String)?.contains("\n\n") == true)
    }

    func testPageEnsureBlockIDsPersistsIDsAndIsIdempotent() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Block IDs",
                "--content-file", try writeTempFile(in: workspace, name: "block-ids.md", contents: """
                # Block IDs
                First paragraph
                Second paragraph
                """)
            ])
        )

        let first = try runJSON(
            Page.EnsureBlockIDs.parseAsRoot([
                "--workspace", workspace,
                "Block IDs",
                "--blocks"
            ])
        )
        XCTAssertEqual(first["changed"] as? Bool, true)
        XCTAssertEqual(first["block_count"] as? Int, 3)
        let firstBlocks = try XCTUnwrap(first["blocks"] as? [[String: Any]])
        XCTAssertTrue(firstBlocks.allSatisfy { ($0["stable_id"] as? Bool) == true })

        let second = try runJSON(
            Page.EnsureBlockIDs.parseAsRoot([
                "--workspace", workspace,
                "Block IDs"
            ])
        )
        XCTAssertEqual(second["changed"] as? Bool, false)
    }

    func testPageEnsureBlockIDsRepairsDuplicatePersistedIDs() throws {
        let workspace = try makeWorkspace()
        let duplicateID = "11111111-1111-1111-1111-111111111111"

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Duplicate Block IDs",
                "--content-file", try writeTempFile(in: workspace, name: "duplicate-block-ids.md", contents: """
                <!-- block-id: \(duplicateID) -->
                # Duplicate Block IDs
                <!-- block-id: \(duplicateID) -->
                First paragraph
                """)
            ])
        )

        var ambiguousGet = try Page.Get.parseAsRoot([
            "--workspace", workspace,
            "Duplicate Block IDs",
            "--block-id", duplicateID
        ])

        XCTAssertThrowsError(try ambiguousGet.run()) { error in
            guard case CLIError.invalidInput(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("ambiguous"))
        }

        let ensured = try runJSON(
            Page.EnsureBlockIDs.parseAsRoot([
                "--workspace", workspace,
                "Duplicate Block IDs",
                "--blocks"
            ])
        )

        XCTAssertEqual(ensured["changed"] as? Bool, true)
        let blocks = try XCTUnwrap(ensured["blocks"] as? [[String: Any]])
        let ids = try blocks.map { block -> String in
            try XCTUnwrap(block["id"] as? String)
        }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(blocks.allSatisfy { ($0["stable_id"] as? Bool) == true })
    }

    func testPageGetAndUpdateCanTargetBlockSelectors() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Block Target",
                "--content-file", try writeTempFile(in: workspace, name: "block-target.md", contents: """
                # Block Target
                First paragraph
                Second paragraph
                """)
            ])
        )

        let initialBlocks = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Block Target",
                "--blocks"
            ])
        )
        let initialItems = try XCTUnwrap(initialBlocks["blocks"] as? [[String: Any]])
        XCTAssertEqual(initialItems.count, 3)
        XCTAssertEqual(initialItems[1]["id"] as? String, "path:1")
        XCTAssertEqual(initialItems[1]["stable_id"] as? Bool, false)

        let rawBlock = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Block Target",
                "--block-id", "path:1",
                "--raw"
            ])
            try command.run()
        }
        XCTAssertEqual(rawBlock, "First paragraph")

        let preview = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Block Target",
                "--block-id", "path:1",
                "--content-file", try writeTempFile(in: workspace, name: "block-replacement.md", contents: """
                Updated paragraph
                """),
                "--dry-run"
            ])
        )
        XCTAssertEqual(preview["dry_run"] as? Bool, true)
        let selectedBlockBefore = try XCTUnwrap(preview["selected_block_before"] as? [String: Any])
        XCTAssertEqual(selectedBlockBefore["id"] as? String, "path:1")
        let selectedBlocksAfter = try XCTUnwrap(preview["selected_blocks_after"] as? [[String: Any]])
        XCTAssertEqual(selectedBlocksAfter.count, 1)
        XCTAssertEqual(selectedBlocksAfter[0]["stable_id"] as? Bool, false)

        let updated = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Block Target",
                "--block-id", "path:1",
                "--content-file", try writeTempFile(in: workspace, name: "block-apply.md", contents: """
                Updated paragraph
                """)
            ])
        )
        let body = try XCTUnwrap(updated["body"] as? String)
        XCTAssertTrue(body.contains("Updated paragraph"))

        let blocksAfter = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Block Target",
                "--blocks"
            ])
        )
        let updatedItems = try XCTUnwrap(blocksAfter["blocks"] as? [[String: Any]])
        XCTAssertTrue(updatedItems.allSatisfy { ($0["stable_id"] as? Bool) == false })
        XCTAssertEqual(updatedItems[1]["text"] as? String, "Updated paragraph")
    }

    func testPageUpdateBlockTextPreservesMarkdownType() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Typed Block",
                "--content-file", try writeTempFile(in: workspace, name: "typed-block.md", contents: """
                # Typed Block
                - Original bullet
                """)
            ])
        )

        let preview = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Typed Block",
                "--block-id", "path:1",
                "--text-file", try writeTempFile(in: workspace, name: "typed-block-preview.md", contents: "Updated bullet"),
                "--dry-run"
            ])
        )
        let selectedBlocksAfter = try XCTUnwrap(preview["selected_blocks_after"] as? [[String: Any]])
        XCTAssertEqual(selectedBlocksAfter.first?["type"] as? String, "bullet_list_item")
        XCTAssertEqual(selectedBlocksAfter.first?["text"] as? String, "Updated bullet")

        let updated = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Typed Block",
                "--block-id", "path:1",
                "--text-file", try writeTempFile(in: workspace, name: "typed-block-apply.md", contents: "Updated bullet")
            ])
        )

        let body = try XCTUnwrap(updated["body"] as? String)
        XCTAssertTrue(body.contains("- Updated bullet"))
        XCTAssertFalse(body.contains("<!-- block-id:"))
    }

    func testPageUpdateBlockTextPreservesParagraphTypeForMarkdownLookingText() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Paragraph Block",
                "--content-file", try writeTempFile(in: workspace, name: "paragraph-block.md", contents: """
                # Paragraph Block
                Original paragraph
                """)
            ])
        )

        let preview = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Paragraph Block",
                "--block-id", "path:1",
                "--text-file", try writeTempFile(in: workspace, name: "paragraph-block-preview.txt", contents: "- not a list"),
                "--dry-run"
            ])
        )
        let selectedBlocksAfter = try XCTUnwrap(preview["selected_blocks_after"] as? [[String: Any]])
        XCTAssertEqual(selectedBlocksAfter.first?["type"] as? String, "paragraph")
        XCTAssertEqual(selectedBlocksAfter.first?["text"] as? String, "- not a list")

        _ = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Paragraph Block",
                "--block-id", "path:1",
                "--text-file", try writeTempFile(in: workspace, name: "paragraph-block-apply.txt", contents: "- not a list")
            ])
        )

        let blocks = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Paragraph Block",
                "--blocks"
            ])
        )
        let blockItems = try XCTUnwrap(blocks["blocks"] as? [[String: Any]])
        XCTAssertEqual(blockItems[1]["type"] as? String, "paragraph")
        XCTAssertEqual(blockItems[1]["text"] as? String, "- not a list")
    }

    func testBlockCommandsProvideDedicatedAgentSurface() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Block Commands",
                "--content-file", try writeTempFile(in: workspace, name: "block-commands.md", contents: """
                # Block Commands
                - First bullet
                Paragraph
                """)
            ])
        )

        let listed = try runJSON(
            Block.List.parseAsRoot([
                "--workspace", workspace,
                "Block Commands"
            ])
        )
        let blocks = try XCTUnwrap(listed["blocks"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1]["type"] as? String, "bullet_list_item")

        let rawBlock = try captureStandardOutput {
            var command = try Block.Get.parseAsRoot([
                "--workspace", workspace,
                "Block Commands",
                "path:1",
                "--raw"
            ])
            try command.run()
        }
        XCTAssertEqual(rawBlock, "- First bullet")

        let updatePreview = try runJSON(
            Block.UpdateText.parseAsRoot([
                "--workspace", workspace,
                "Block Commands",
                "path:1",
                "--text-file", try writeTempFile(in: workspace, name: "block-text.txt", contents: "Updated bullet"),
                "--dry-run"
            ])
        )
        XCTAssertEqual(updatePreview["dry_run"] as? Bool, true)
        XCTAssertNil(updatePreview["content"])
        let updatedBlocks = try XCTUnwrap(updatePreview["selected_blocks_after"] as? [[String: Any]])
        XCTAssertEqual(updatedBlocks.first?["type"] as? String, "bullet_list_item")
        XCTAssertEqual(updatedBlocks.first?["text"] as? String, "Updated bullet")

        _ = try runJSON(
            Block.UpdateText.parseAsRoot([
                "--workspace", workspace,
                "Block Commands",
                "path:1",
                "--text-file", try writeTempFile(in: workspace, name: "block-text-apply.txt", contents: "Updated bullet")
            ])
        )

        _ = try runJSON(
            Block.Insert.parseAsRoot([
                "--workspace", workspace,
                "Block Commands",
                "path:1",
                "--after",
                "--content-file", try writeTempFile(in: workspace, name: "block-insert.md", contents: "Inserted paragraph")
            ])
        )

        let previewDelete = try runJSON(
            Block.Delete.parseAsRoot([
                "--workspace", workspace,
                "Block Commands",
                "path:2",
                "--dry-run"
            ])
        )
        XCTAssertEqual(previewDelete["dry_run"] as? Bool, true)
        XCTAssertEqual(previewDelete["changed"] as? Bool, true)
        let blocksAfterDelete = try XCTUnwrap(previewDelete["selected_blocks_after"] as? [[String: Any]])
        XCTAssertTrue(blocksAfterDelete.isEmpty)

        _ = try runJSON(
            Block.Delete.parseAsRoot([
                "--workspace", workspace,
                "Block Commands",
                "path:2"
            ])
        )

        let fetched = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Block Commands"
            ])
        )
        let body = try XCTUnwrap(fetched["body"] as? String)
        XCTAssertTrue(body.contains("- Updated bullet"))
        XCTAssertFalse(body.contains("Inserted paragraph"))
    }

    func testBlockSummaryUsesPostWriteModifiedAt() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Block Summary",
                "--content-file", try writeTempFile(in: workspace, name: "block-summary.md", contents: """
                # Block Summary
                Original paragraph
                """)
            ])
        )

        usleep(1_100_000)

        let summary = try runJSON(
            Block.UpdateText.parseAsRoot([
                "--workspace", workspace,
                "Block Summary",
                "path:1",
                "--text-file", try writeTempFile(in: workspace, name: "block-summary.txt", contents: "Updated paragraph"),
                "--output", "summary"
            ])
        )

        let fetched = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Block Summary"
            ])
        )

        XCTAssertEqual(summary["modified_at"] as? String, fetched["modified_at"] as? String)
    }

    func testBlockMoveReordersBlocksAndRejectsDescendantTargets() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Move Blocks",
                "--content-file", try writeTempFile(in: workspace, name: "move-blocks.md", contents: """
                # Move Blocks
                Alpha
                Beta
                Gamma
                """)
            ])
        )

        let preview = try runJSON(
            Block.Move.parseAsRoot([
                "--workspace", workspace,
                "Move Blocks",
                "path:1",
                "path:3",
                "--after"
            ])
        )
        XCTAssertEqual(preview["updated"] as? Bool, true)
        XCTAssertEqual(preview["changed"] as? Bool, true)
        XCTAssertNil(preview["content"])
        let selectedAfter = try XCTUnwrap(preview["selected_blocks_after"] as? [[String: Any]])
        XCTAssertEqual(selectedAfter.first?["id"] as? String, "path:3")
        XCTAssertEqual(selectedAfter.first?["text"] as? String, "Alpha")

        let fetched = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Move Blocks"
            ])
        )
        let body = try XCTUnwrap(fetched["body"] as? String)
        XCTAssertTrue(body.contains("# Move Blocks\nBeta\nGamma\nAlpha"))

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Nested Move",
                "--content-file", try writeTempFile(in: workspace, name: "nested-move.md", contents: """
                <!-- toggle -->
                Parent
                Child
                <!-- /toggle -->
                Sibling
                """)
            ])
        )

        var invalidMove = try Block.Move.parseAsRoot([
            "--workspace", workspace,
            "Nested Move",
            "path:0",
            "path:0/0",
            "--after"
        ])

        XCTAssertThrowsError(try invalidMove.run()) { error in
            guard case CLIError.invalidInput(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("descendants"))
        }
    }

    func testPageStripBlockIDsRemovesPersistedComments() throws {
        let workspace = try makeWorkspace()
        let blockID = "11111111-1111-1111-1111-111111111111"

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Strip Block IDs",
                "--content-file", try writeTempFile(in: workspace, name: "strip-block-ids.md", contents: """
                <!-- block-id: \(blockID) -->
                # Strip Block IDs
                """)
            ])
        )

        let stripped = try runJSON(
            Page.StripBlockIDs.parseAsRoot([
                "--workspace", workspace,
                "Strip Block IDs"
            ])
        )
        XCTAssertEqual(stripped["changed"] as? Bool, true)
        XCTAssertEqual(stripped["stable_block_ids"] as? Bool, false)

        let raw = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Strip Block IDs",
                "--raw",
                "--include-internal-comments"
            ])
            try command.run()
        }
        XCTAssertFalse(raw.contains("<!-- block-id:"))
    }

    func testInstallCommandCanSymlinkRelativeSourcePath() throws {
        let workspace = try makeWorkspace()
        let source = try writeTempFile(in: workspace, name: "BugbookCLI-bin", contents: "binary")
        let destinationDirectory = normalizePath((workspace as NSString).appendingPathComponent("bin"))
        let originalDirectory = FileManager.default.currentDirectoryPath
        defer { _ = chdir(originalDirectory) }
        XCTAssertEqual(chdir(workspace), 0)

        let output = try installBugbookBinary(
            sourcePath: ".tmp/BugbookCLI-bin",
            destinationDirectory: destinationDirectory,
            installedName: "bugbook",
            method: .symlink,
            force: false
        )

        let destination = try XCTUnwrap(output["destination"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination), source)
    }

    func testInstallCommandReplacesBrokenSymlinkWhenForced() throws {
        let workspace = try makeWorkspace()
        let source = try writeTempFile(in: workspace, name: "BugbookCLI-bin", contents: "binary")
        let destinationDirectory = normalizePath((workspace as NSString).appendingPathComponent("bin"))
        try FileManager.default.createDirectory(atPath: destinationDirectory, withIntermediateDirectories: true)

        let destination = normalizePath((destinationDirectory as NSString).appendingPathComponent("bugbook"))
        try FileManager.default.createSymbolicLink(atPath: destination, withDestinationPath: "/tmp/does-not-exist")

        let output = try installBugbookBinary(
            sourcePath: source,
            destinationDirectory: destinationDirectory,
            installedName: "bugbook",
            method: .symlink,
            force: true
        )

        XCTAssertEqual(output["updated"] as? Bool, true)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination), source)
    }

    func testPageUpdateBlockIgnoresEmptyPrependAndAppendContent() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Empty Block Insert",
                "--content-file", try writeTempFile(in: workspace, name: "empty-block-insert.md", contents: """
                # Empty Block Insert
                First paragraph
                Second paragraph
                """)
            ])
        )

        _ = try runJSON(
            Page.EnsureBlockIDs.parseAsRoot([
                "--workspace", workspace,
                "Empty Block Insert"
            ])
        )

        let blocks = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Empty Block Insert",
                "--blocks"
            ])
        )
        let blockItems = try XCTUnwrap(blocks["blocks"] as? [[String: Any]])
        let targetID = try XCTUnwrap(blockItems[1]["id"] as? String)

        let preview = try runJSON(
            Page.Update.parseAsRoot([
                "--workspace", workspace,
                "Empty Block Insert",
                "--block-id", targetID,
                "--append-file", try writeTempFile(in: workspace, name: "empty-block.md", contents: ""),
                "--dry-run"
            ])
        )

        XCTAssertEqual(preview["changed"] as? Bool, false)
        let lineChanges = try XCTUnwrap(preview["line_changes"] as? [[String: Any]])
        XCTAssertTrue(lineChanges.isEmpty)
        let selectedBefore = try XCTUnwrap(preview["selected_block_before"] as? [String: Any])
        XCTAssertEqual(selectedBefore["id"] as? String, targetID)
        let selectedAfter = try XCTUnwrap(preview["selected_blocks_after"] as? [[String: Any]])
        XCTAssertEqual(selectedAfter.count, 1)
        XCTAssertEqual(selectedAfter[0]["id"] as? String, targetID)
    }

    func testBoardAndDatabaseViewCommandsSmoke() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy",
                "--title", "Bugbook Strategy"
            ])
        )

        let created = try runJSON(
            Board.Create.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy Board",
                "--group-name", "Phase",
                "--column", "Now",
                "--column", "Next",
                "--column", "Later",
                "--view", "list",
                "--view", "calendar",
                "--no-table",
                "--embed-in", "Bugbook Strategy"
            ])
        )

        let createdViews = try XCTUnwrap(created["views"] as? [[String: Any]])
        XCTAssertEqual(createdViews.map { $0["type"] as? String }, ["kanban", "list", "calendar"])
        let createdViewIds = createdViews.compactMap { $0["id"] as? String }
        XCTAssertEqual(createdViewIds.count, Set(createdViewIds).count)
        let embed = try XCTUnwrap(created["embed"] as? [String: Any])
        XCTAssertEqual(embed["embedded"] as? Bool, true)

        let listedBeforeAdd = try runJSONArray(
            DBView.List.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy Board"
            ])
        )
        XCTAssertEqual(listedBeforeAdd.count, 3)

        let addedView = try runJSON(
            DBView.Add.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy Board",
                "--type", "table",
                "--name", "Table",
                "--set-default"
            ])
        )
        let addedViewPayload = try XCTUnwrap(addedView["view"] as? [String: Any])
        XCTAssertEqual(addedViewPayload["type"] as? String, "table")

        _ = try runJSON(
            DBView.Update.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy Board",
                "Table",
                "--name", "Grid"
            ])
        )

        let setDefault = try runJSON(
            DBView.SetDefault.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy Board",
                "Grid"
            ])
        )
        XCTAssertEqual((setDefault["default_view"] as? [String: Any])?["name"] as? String, "Grid")

        let card = try runJSON(
            Board.AddCard.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy Board",
                "Search trust",
                "--column", "Now",
                "--date", "2026-03-07"
            ])
        )
        let rowId = try XCTUnwrap(card["id"] as? String)

        let moved = try runJSON(
            Board.MoveCard.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy Board",
                rowId,
                "Next"
            ])
        )
        XCTAssertEqual((moved["column"] as? [String: Any])?["name"] as? String, "Next")

        let deleted = try runJSON(
            DBView.Delete.parseAsRoot([
                "--workspace", workspace,
                "Bugbook Strategy Board",
                "Grid"
            ])
        )
        XCTAssertEqual(deleted["deleted"] as? Bool, true)
    }

    func testBoardCommandsSupportMultiSelectGrouping() throws {
        let workspace = try makeWorkspace()
        let schema = DatabaseSchema(
            id: "db_multi_select_board",
            name: "Multi Select Board",
            properties: [
                PropertyDefinition(id: "prop_title", name: "Title", type: .title),
                PropertyDefinition(
                    id: "prop_status",
                    name: "Status",
                    type: .multiSelect,
                    config: PropertyConfig(options: [
                        SelectOption(id: "opt_backlog", name: "Backlog", color: "gray"),
                        SelectOption(id: "opt_done", name: "Done", color: "green"),
                    ])
                ),
            ],
            views: [
                ViewConfig(id: "view_board", name: "Board", type: .kanban, groupBy: "prop_status"),
            ],
            defaultView: "view_board",
            createdAt: "2026-03-07T00:00:00Z"
        )
        let schemaPath = try writeTempJSONFile(in: workspace, name: "multi-select-board.json", value: schema)

        _ = try runJSON(
            DB.CreateDB.parseAsRoot([
                "--workspace", workspace,
                "Multi Select Board",
                "--schema", schemaPath,
            ])
        )

        let created = try runJSON(
            Board.AddCard.parseAsRoot([
                "--workspace", workspace,
                "Multi Select Board",
                "Capture feedback",
                "--column", "Backlog",
            ])
        )
        let rowId = try XCTUnwrap(created["id"] as? String)

        let moved = try runJSON(
            Board.MoveCard.parseAsRoot([
                "--workspace", workspace,
                "Multi Select Board",
                rowId,
                "Done",
            ])
        )
        XCTAssertEqual((moved["column"] as? [String: Any])?["name"] as? String, "Done")

        let (dbPath, loadedSchema) = try resolveDatabase("Multi Select Board", workspace: workspace)
        let row = try XCTUnwrap(try loadRow(rowId: rowId, dbPath: dbPath, schema: loadedSchema))
        XCTAssertEqual(row.properties["prop_status"], .multiSelect(["opt_done"]))
    }

    func testDatabaseMoveDryRunPreviewsPageReparent() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--title", "Agent Tickets",
            ])
        )

        _ = try runJSON(
            Board.Create.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--directory", "Bugbook Team",
                "--embed-in", "Agent Tickets",
            ])
        )

        let preview = try runJSON(
            DB.Move.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--page", "Agent Tickets",
                "--dry-run",
            ])
        )

        XCTAssertEqual(preview["dry_run"] as? Bool, true)
        XCTAssertEqual(preview["planned_move"] as? Bool, true)
        XCTAssertEqual(preview["old_relative_path"] as? String, "Bugbook Team/Agent Tickets")
        XCTAssertEqual(preview["new_relative_path"] as? String, "Agent Tickets/Agent Tickets")
        XCTAssertEqual(preview["embed_update_count"] as? Int, 1)

        let pageRaw = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--raw",
            ])
            try command.run()
        }
        XCTAssertTrue(pageRaw.contains("Bugbook Team/Agent Tickets"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: (workspace as NSString).appendingPathComponent("Agent Tickets/Agent Tickets/_schema.json")))
    }

    func testDatabaseMoveCanReparentUnderPageAndRetargetEmbeds() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--title", "Agent Tickets",
            ])
        )

        _ = try runJSON(
            Board.Create.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--directory", "Bugbook Team",
                "--embed-in", "Agent Tickets",
            ])
        )

        let moved = try runJSON(
            DB.Move.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--page", "Agent Tickets",
            ])
        )

        XCTAssertEqual(moved["moved"] as? Bool, true)
        XCTAssertEqual(moved["old_relative_path"] as? String, "Bugbook Team/Agent Tickets")
        XCTAssertEqual(moved["new_relative_path"] as? String, "Agent Tickets/Agent Tickets")
        XCTAssertEqual(moved["embed_update_count"] as? Int, 1)
        let destinationPage = try XCTUnwrap(moved["destination_page"] as? [String: Any])
        XCTAssertEqual(destinationPage["relative_path"] as? String, "Agent Tickets.md")

        let schemaPath = (workspace as NSString).appendingPathComponent("Agent Tickets/Agent Tickets/_schema.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: schemaPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: (workspace as NSString).appendingPathComponent("Bugbook Team")))

        let pageRaw = try captureStandardOutput {
            var command = try Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--raw",
            ])
            try command.run()
        }
        XCTAssertTrue(pageRaw.contains("Agent Tickets/Agent Tickets"))
        XCTAssertFalse(pageRaw.contains("Bugbook Team/Agent Tickets"))

        let listed = try runJSONArray(
            DB.List.parseAsRoot([
                "--workspace", workspace,
            ])
        )
        let database = try XCTUnwrap(
            listed.first { ($0["name"] as? String) == "Agent Tickets" }
        )
        XCTAssertEqual(database["relative_path"] as? String, "Agent Tickets/Agent Tickets")
        let parentPage = try XCTUnwrap(database["parent_page"] as? [String: Any])
        XCTAssertEqual(parentPage["relative_path"] as? String, "Agent Tickets.md")
    }

    func testDatabaseMoveRetargetsEmbedsInsideMovedRowFiles() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--title", "Agent Tickets",
            ])
        )

        _ = try runJSON(
            Board.Create.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--directory", "Bugbook Team",
                "--embed-in", "Agent Tickets",
            ])
        )

        let (oldDatabasePath, _) = try resolveDatabase("Agent Tickets", workspace: workspace)
        let rowBodyPath = try writeTempFile(
            in: workspace,
            name: "row-body.md",
            contents: "<!-- database: \(oldDatabasePath) -->"
        )
        let created = try runJSON(
            Create.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--set", "Title=Nested Embed",
                "--body-file", rowBodyPath,
            ])
        )
        let rowId = try XCTUnwrap(created["id"] as? String)

        _ = try runJSON(
            DB.Move.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                "--page", "Agent Tickets",
            ])
        )

        let fetched = try runJSON(
            Get.parseAsRoot([
                "--workspace", workspace,
                "Agent Tickets",
                rowId,
                "--body",
            ])
        )

        let body = try XCTUnwrap(fetched["body"] as? String)
        XCTAssertTrue(body.contains("Agent Tickets/Agent Tickets"))
        XCTAssertFalse(body.contains("Bugbook Team/Agent Tickets"))
    }

    func testCreateUpdateAndQueryAcceptFriendlySchemaNames() throws {
        let workspace = try makeWorkspace()
        let schema = DatabaseSchema(
            id: "db_agent_cli",
            name: "Agent CLI Board",
            properties: [
                PropertyDefinition(id: "prop_title", name: "Title", type: .title),
                PropertyDefinition(
                    id: "prop_status",
                    name: "Status",
                    type: .select,
                    config: PropertyConfig(options: [
                        SelectOption(id: "opt_in_progress", name: "In Progress", color: "blue"),
                        SelectOption(id: "opt_done", name: "Done", color: "green"),
                    ])
                ),
                PropertyDefinition(id: "prop_priority", name: "Priority", type: .number),
            ],
            views: [ViewConfig(id: "view_table", name: "Table", type: .table)],
            defaultView: "view_table",
            createdAt: "2026-03-07T00:00:00Z"
        )
        let schemaPath = try writeTempJSONFile(in: workspace, name: "agent-cli-board.json", value: schema)

        _ = try runJSON(
            DB.CreateDB.parseAsRoot([
                "--workspace", workspace,
                "Agent CLI Board",
                "--schema", schemaPath,
            ])
        )

        let first = try runJSON(
            Create.parseAsRoot([
                "--workspace", workspace,
                "Agent CLI Board",
                "--set", "Title=Ship CLI",
                "--set", "Status=In Progress",
                "--set", "Priority=1"
            ])
        )
        let firstRowId = try XCTUnwrap(first["id"] as? String)

        _ = try runJSON(
            Create.parseAsRoot([
                "--workspace", workspace,
                "Agent CLI Board",
                "--set", "Title=Write docs",
                "--set", "Status=Done",
                "--set", "Priority=2"
            ])
        )

        let queried = try runJSON(
            QueryCmd.parseAsRoot([
                "--workspace", workspace,
                "Agent CLI Board",
                "--filter", "Status=In Progress",
                "--sort", "Priority:desc",
                "--fields", "Title,Status"
            ])
        )

        XCTAssertEqual(queried["total_count"] as? Int, 1)
        let rows = try XCTUnwrap(queried["rows"] as? [[String: Any]])
        let props = try XCTUnwrap(rows.first?["properties"] as? [String: Any])
        XCTAssertEqual(props["Title"] as? String, "Ship CLI")
        XCTAssertEqual(props["Status"] as? String, "In Progress")
        XCTAssertNil(props["Priority"])

        let rawQueried = try runJSON(
            QueryCmd.parseAsRoot([
                "--workspace", workspace,
                "Agent CLI Board",
                "--filter", "Status=In Progress",
                "--fields", "Title,Status",
                "--raw-properties"
            ])
        )
        let rawRows = try XCTUnwrap(rawQueried["rows"] as? [[String: Any]])
        let rawProps = try XCTUnwrap(rawRows.first?["raw_properties"] as? [String: Any])
        XCTAssertEqual(rawProps["prop_title"] as? String, "Ship CLI")
        XCTAssertEqual(rawProps["prop_status"] as? String, "opt_in_progress")

        _ = try runJSON(
            Update.parseAsRoot([
                "--workspace", workspace,
                "Agent CLI Board",
                firstRowId,
                "--set", "Status=Done"
            ])
        )

        let (dbPath, loadedSchema) = try resolveDatabase("Agent CLI Board", workspace: workspace)
        let row = try XCTUnwrap(try loadRow(rowId: firstRowId, dbPath: dbPath, schema: loadedSchema))
        XCTAssertEqual(row.properties["prop_status"], .select("opt_done"))

        let fetched = try runJSON(
            Get.parseAsRoot([
                "--workspace", workspace,
                "Agent CLI Board",
                firstRowId,
                "--fields", "Title,Status",
                "--raw-properties"
            ])
        )
        let fetchedProps = try XCTUnwrap(fetched["properties"] as? [String: Any])
        XCTAssertEqual(fetchedProps["Title"] as? String, "Ship CLI")
        XCTAssertEqual(fetchedProps["Status"] as? String, "Done")
        XCTAssertNil(fetchedProps["Priority"])
        let fetchedRaw = try XCTUnwrap(fetched["raw_properties"] as? [String: Any])
        XCTAssertEqual(fetchedRaw["prop_status"] as? String, "opt_done")
    }

    func testFriendlySchemaResolutionRejectsAmbiguousMatches() throws {
        let workspace = try makeWorkspace()
        let schema = DatabaseSchema(
            id: "db_ambiguous",
            name: "Ambiguous Board",
            properties: [
                PropertyDefinition(id: "prop_title", name: "Title", type: .title),
                PropertyDefinition(id: "prop_status_flag", name: "Status Flag", type: .text),
                PropertyDefinition(id: "prop_status_flag_alt", name: "Status_Flag", type: .text),
            ],
            views: [ViewConfig(id: "view_table", name: "Table", type: .table)],
            defaultView: "view_table",
            createdAt: "2026-03-07T00:00:00Z"
        )
        let schemaPath = try writeTempJSONFile(in: workspace, name: "ambiguous-board.json", value: schema)

        _ = try runJSON(
            DB.CreateDB.parseAsRoot([
                "--workspace", workspace,
                "Ambiguous Board",
                "--schema", schemaPath,
            ])
        )

        var command = try Create.parseAsRoot([
            "--workspace", workspace,
            "Ambiguous Board",
            "--set", "Title=Test",
            "--set", "status-flag=value"
        ])

        XCTAssertThrowsError(try command.run()) { error in
            guard case CLIError.invalidInput(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("ambiguous"))
        }
    }

    func testDatabaseResolutionRejectsAmbiguousIDs() throws {
        let workspace = try makeWorkspace()
        let firstSchema = DatabaseSchema(
            id: "db_shared_id",
            name: "First Database",
            properties: [
                PropertyDefinition(id: "prop_title", name: "Title", type: .title),
            ],
            views: [ViewConfig(id: "view_table", name: "Table", type: .table)],
            defaultView: "view_table",
            createdAt: "2026-03-07T00:00:00Z"
        )
        let secondSchema = DatabaseSchema(
            id: "db_shared_id",
            name: "Second Database",
            properties: [
                PropertyDefinition(id: "prop_title", name: "Title", type: .title),
            ],
            views: [ViewConfig(id: "view_table", name: "Table", type: .table)],
            defaultView: "view_table",
            createdAt: "2026-03-07T00:00:00Z"
        )
        let firstSchemaPath = try writeTempJSONFile(in: workspace, name: "first-database.json", value: firstSchema)
        let secondSchemaPath = try writeTempJSONFile(in: workspace, name: "second-database.json", value: secondSchema)

        _ = try runJSON(
            DB.CreateDB.parseAsRoot([
                "--workspace", workspace,
                "First Database",
                "--schema", firstSchemaPath,
            ])
        )
        _ = try runJSON(
            DB.CreateDB.parseAsRoot([
                "--workspace", workspace,
                "Second Database",
                "--schema", secondSchemaPath,
            ])
        )

        var command = try DB.Schema.parseAsRoot([
            "--workspace", workspace,
            "db_shared_id",
        ])

        XCTAssertThrowsError(try command.run()) { error in
            guard case CLIError.invalidInput(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("Database ID is ambiguous"))
            XCTAssertTrue(message.contains("First Database"))
            XCTAssertTrue(message.contains("Second Database"))
        }
    }

    func testFriendlySchemaResolutionRejectsUnknownPropertyAndOption() throws {
        let workspace = try makeWorkspace()
        let schema = DatabaseSchema(
            id: "db_unknowns",
            name: "Unknowns Board",
            properties: [
                PropertyDefinition(id: "prop_title", name: "Title", type: .title),
                PropertyDefinition(
                    id: "prop_status",
                    name: "Status",
                    type: .select,
                    config: PropertyConfig(options: [
                        SelectOption(id: "opt_done", name: "Done", color: "green"),
                    ])
                ),
            ],
            views: [ViewConfig(id: "view_table", name: "Table", type: .table)],
            defaultView: "view_table",
            createdAt: "2026-03-07T00:00:00Z"
        )
        let schemaPath = try writeTempJSONFile(in: workspace, name: "unknowns-board.json", value: schema)

        _ = try runJSON(
            DB.CreateDB.parseAsRoot([
                "--workspace", workspace,
                "Unknowns Board",
                "--schema", schemaPath,
            ])
        )

        var missingProperty = try QueryCmd.parseAsRoot([
            "--workspace", workspace,
            "Unknowns Board",
            "--filter", "Priority=1"
        ])

        XCTAssertThrowsError(try missingProperty.run()) { error in
            guard case CLIError.invalidInput(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("Property not found"))
        }

        var missingOption = try QueryCmd.parseAsRoot([
            "--workspace", workspace,
            "Unknowns Board",
            "--filter", "Status=Blocked"
        ])

        XCTAssertThrowsError(try missingOption.run()) { error in
            guard case CLIError.invalidInput(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("Option not found"))
        }
    }

    func testSkillCommandsSmoke() throws {
        let workspace = try makeWorkspace()
        let description = """
        Summarize source notes into one page.
        Include claims: evidence and next steps.
        """

        let created = try runJSON(
            Skill.Create.parseAsRoot([
                "--workspace", workspace,
                "research-summarizer",
                "--description", description
            ])
        )
        XCTAssertEqual(created["relative_path"] as? String, "Skills/research-summarizer.skill.md")

        let listed = try runJSONArray(
            Skill.List.parseAsRoot([
                "--workspace", workspace
            ])
        )
        XCTAssertEqual(listed.count, 1)

        let fetched = try runJSON(
            Skill.Get.parseAsRoot([
                "--workspace", workspace,
                "research-summarizer"
            ])
        )
        XCTAssertEqual(fetched["description"] as? String, description)
    }

    func testPageDeleteRecursiveRemovesCompanionFolder() throws {
        let workspace = try makeWorkspace()

        let created = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/With Companion",
                "--title", "With Companion"
            ])
        )
        let pagePath = try XCTUnwrap(created["path"] as? String)
        let companionPath = URL(fileURLWithPath: pagePath).deletingPathExtension().path
        try FileManager.default.createDirectory(atPath: companionPath, withIntermediateDirectories: true)
        try "asset".write(
            toFile: (companionPath as NSString).appendingPathComponent("asset.txt"),
            atomically: true,
            encoding: .utf8
        )

        var nonRecursive = try Page.Delete.parseAsRoot([
            "--workspace", workspace,
            "With Companion"
        ])
        XCTAssertThrowsError(try nonRecursive.run())

        let deleted = try runJSON(
            Page.Delete.parseAsRoot([
                "--workspace", workspace,
                "With Companion",
                "--recursive"
            ])
        )

        XCTAssertEqual(deleted["deleted"] as? Bool, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pagePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: companionPath))
    }

    func testPageCreateForcesMarkdownExtension() throws {
        let workspace = try makeWorkspace()

        let created = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/spec.txt",
                "--title", "Spec",
            ])
        )

        XCTAssertEqual(created["relative_path"] as? String, "Notes/spec.md")
        let createdPath = try XCTUnwrap(created["path"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: (workspace as NSString).appendingPathComponent("Notes/spec.txt")))

        let fetched = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "Notes/spec.md",
            ])
        )
        XCTAssertEqual(fetched["relative_path"] as? String, "Notes/spec.md")
    }

    func testFrontmatterParsesNestedYAMLAndMultilineStrings() throws {
        let workspace = try makeWorkspace()

        _ = try runJSON(
            Page.Create.parseAsRoot([
                "--workspace", workspace,
                "Notes/Yaml Example",
                "--content-file", try writeTempFile(in: workspace, name: "yaml.md", contents: """
                ---
                title: YAML Example
                tags:
                  - pkm
                  - agents
                metadata:
                  owner: Max
                  links:
                    - "alpha:beta"
                    - gamma
                summary: |
                  first: line
                  second line
                ---

                # Ignored Heading

                Body text.
                """)
            ])
        )

        let fetched = try runJSON(
            Page.Get.parseAsRoot([
                "--workspace", workspace,
                "YAML Example"
            ])
        )

        XCTAssertEqual(fetched["title"] as? String, "YAML Example")

        let frontmatter = try XCTUnwrap(fetched["frontmatter"] as? [String: Any])
        XCTAssertEqual(frontmatter["tags"] as? [String], ["pkm", "agents"])

        let metadata = try XCTUnwrap(frontmatter["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["owner"] as? String, "Max")
        XCTAssertEqual(metadata["links"] as? [String], ["alpha:beta", "gamma"])

        let summary = try XCTUnwrap(frontmatter["summary"] as? String)
        XCTAssertTrue(summary.contains("first: line"))
        XCTAssertTrue(summary.contains("second line"))
    }

    func testSharedAgentsTemplateCoversNotesBoardsSkillsAndTracking() {
        let template = AgentWorkspaceTemplate.agentsMarkdown(workspace: "/tmp/Bugbook")
        XCTAssertTrue(template.contains("## Notes And Pages"))
        XCTAssertTrue(template.contains("bugbook page get \"Bugbook Strategy\" --raw"))
        XCTAssertTrue(template.contains("bugbook page headings \"Bugbook Strategy\""))
        XCTAssertTrue(template.contains("bugbook page format \"Bugbook Strategy\" --style commonmark"))
        XCTAssertTrue(template.contains("bugbook page get \"Bugbook Strategy\" --section-line 110"))
        XCTAssertTrue(template.contains("--dry-run"))
        XCTAssertTrue(template.contains("bugbook board create"))
        XCTAssertTrue(template.contains("bugbook skill list"))
        XCTAssertTrue(template.contains("bugbook agent task create"))
    }
}

private func makeWorkspace() throws -> String {
    let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent("BugbookCLITests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    return workspaceURL.path
}

private func writeTempFile(in workspace: String, name: String, contents: String) throws -> String {
    let url = URL(fileURLWithPath: workspace).appendingPathComponent(".tmp").appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url.path
}

private func writeTempJSONFile<T: Encodable>(in workspace: String, name: String, value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return try writeTempFile(in: workspace, name: name, contents: String(decoding: data, as: UTF8.self))
}

private func runJSON<C: ParsableCommand>(_ command: C) throws -> [String: Any] {
    var command = command
    let string = try captureStandardOutput {
        try command.run()
    }
    let data = Data(string.utf8)
    return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func runJSONArray<C: ParsableCommand>(_ command: C) throws -> [[String: Any]] {
    var command = command
    let string = try captureStandardOutput {
        try command.run()
    }
    let data = Data(string.utf8)
    return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
}

private func captureStandardOutput(_ body: () throws -> Void) throws -> String {
    let pipe = Pipe()
    let stdoutFD = dup(STDOUT_FILENO)
    precondition(stdoutFD >= 0, "Failed to duplicate stdout")

    fflush(stdout)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    do {
        try body()
    } catch {
        fflush(stdout)
        dup2(stdoutFD, STDOUT_FILENO)
        close(stdoutFD)
        pipe.fileHandleForWriting.closeFile()
        throw error
    }

    fflush(stdout)
    dup2(stdoutFD, STDOUT_FILENO)
    close(stdoutFD)
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self)
}
