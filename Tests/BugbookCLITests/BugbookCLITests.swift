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
