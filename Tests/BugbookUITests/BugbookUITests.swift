import XCTest

/// UI tests that catch render loops, CPU spikes, and UI freezes.
/// Run via Xcode: Product → Test (Cmd+U) with the BugbookApp scheme.
final class BugbookUITests: XCTestCase {

    var app: XCUIApplication!
    private var workspaceURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try seedDailyNotesDatabase(in: workspaceURL)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let workspaceURL {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        workspaceURL = nil
        app = nil
    }

    private func launchApp(legacyPanes: Bool = false) {
        app.launchEnvironment["BUGBOOK_LEGACY_PANES"] = legacyPanes ? "1" : "0"
        app.launchEnvironment["BUGBOOK_PROFILE_WORKSPACE_PATH"] = workspaceURL.path
        app.launchEnvironment["BUGBOOK_SKIP_KEYCHAIN_SECRETS"] = "1"
        app.launchEnvironment["BUGBOOK_DISABLE_SENTRY"] = "1"
        app.launch()
    }

    private func sidebarItem(named name: String, timeout: TimeInterval = 5) -> XCUIElement? {
        let item = app.descendants(matching: .any)["file-tree-item-\(name)"]
        return item.waitForExistence(timeout: timeout) ? item : nil
    }

    private func editorAppeared(timeout: TimeInterval = 5) -> Bool {
        app.descendants(matching: .any)["editor"].waitForExistence(timeout: timeout)
    }

    private func seedDailyNotesDatabase(in workspaceURL: URL) throws {
        let databaseURL = workspaceURL
            .appendingPathComponent("Daily Notes", isDirectory: true)
            .appendingPathComponent("Daily Notes Database", isDirectory: true)
        try FileManager.default.createDirectory(at: databaseURL, withIntermediateDirectories: true)

        let hubPath = workspaceURL.appendingPathComponent("Daily Notes.md")
        try """
        # Daily Notes

        <!-- database: \(databaseURL.path) -->
        """.write(to: hubPath, atomically: true, encoding: .utf8)

        try """
        {
          "id": "db_daily_notes",
          "name": "Daily Notes Database",
          "version": 1,
          "properties": [
            { "id": "name", "name": "Name", "type": "title" },
            { "id": "date", "name": "Date", "type": "date" }
          ],
          "views": [
            {
              "id": "view_daily_table",
              "name": "Table",
              "type": "table",
              "sorts": [
                { "id": "sort_daily_date_desc", "property": "date", "direction": "desc" }
              ],
              "filters": []
            },
            {
              "id": "view_daily_calendar",
              "name": "Calendar",
              "type": "calendar",
              "sorts": [],
              "filters": [],
              "dateProperty": "date"
            }
          ],
          "default_view": "view_daily_table",
          "created_at": "2026-05-18T00:00:00Z"
        }
        """.write(to: databaseURL.appendingPathComponent("_schema.json"), atomically: true, encoding: .utf8)

        try """
        {
          "version": 1,
          "updated_at": "2026-05-18T00:00:00Z",
          "rows": {},
          "indexes": {}
        }
        """.write(to: databaseURL.appendingPathComponent("_index.json"), atomically: true, encoding: .utf8)

        try """
        # Project Note

        This regular workspace note should stay visible in the Pages sidebar.
        """.write(to: workspaceURL.appendingPathComponent("Project Note.md"), atomically: true, encoding: .utf8)
    }

    // MARK: - Responsiveness Tests

    /// Selecting a note must not freeze the UI.
    /// If a render loop or CPU spike occurs, the editor won't appear within the timeout.
    func testSelectNoteDoesNotFreeze() {
        launchApp()

        guard let item = sidebarItem(named: "Daily Notes") else {
            XCTFail("Daily Notes sidebar item did not appear")
            return
        }

        item.click()

        // The editor area must appear within 3 seconds.
        // A render loop / CPU spike would cause this to timeout.
        XCTAssertTrue(
            editorAppeared(),
            "Editor did not appear within 5 seconds after selecting a note — possible render loop or CPU spike"
        )
    }

    /// Measures CPU impact of opening a note.
    /// Run repeatedly to establish a baseline; Xcode flags regressions automatically.
    func testSelectNoteCPUBaseline() {
        launchApp()

        guard let item = sidebarItem(named: "Daily Notes") else {
            XCTFail("Daily Notes sidebar item did not appear")
            return
        }

        let cpuMetric = XCTCPUMetric(application: app)
        measure(metrics: [cpuMetric]) {
            item.click()
            _ = editorAppeared()
        }
    }

    /// Rapidly switching between notes must not accumulate CPU or crash.
    func testRapidNoteSwitchingDoesNotFreeze() {
        launchApp()

        guard let dailyNotes = sidebarItem(named: "Daily Notes"),
              app.buttons["shell-nav-meeting"].waitForExistence(timeout: 5) else {
            XCTFail("Default sidebar navigation did not appear")
            return
        }

        let meeting = app.buttons["shell-nav-meeting"]

        // Switch between the two always-visible daily-driver surfaces.
        for i in 0..<10 {
            let target = (i % 2 == 0) ? dailyNotes : meeting
            if target.exists { target.click() }
            usleep(100_000) // 100ms
        }

        dailyNotes.click()
        XCTAssertTrue(
            editorAppeared(),
            "App became unresponsive after rapid navigation switching"
        )
    }

    func testDefaultModeNavigationExposesMeetingDailyNotesAndPages() {
        launchApp()

        XCTAssertTrue(app.buttons["shell-nav-meeting"].waitForExistence(timeout: 5))
        XCTAssertNotNil(sidebarItem(named: "Daily Notes"))
        XCTAssertNotNil(sidebarItem(named: "Project Note"))
        XCTAssertFalse(app.buttons["shell-nav-notes"].exists)
        XCTAssertFalse(app.buttons["shell-nav-home"].exists)
        XCTAssertFalse(app.buttons["shell-nav-search"].exists)
        XCTAssertFalse(app.buttons["shell-nav-calendar"].exists)
        XCTAssertFalse(app.buttons["shell-nav-terminal"].exists)
        XCTAssertFalse(app.buttons["shell-nav-browser"].exists)
        XCTAssertFalse(app.buttons["shell-nav-mail"].exists)
    }

    func testDefaultModeDoesNotExposeBrowserPane() {
        launchApp()

        XCTAssertFalse(app.otherElements["browser-pane"].exists)
        XCTAssertFalse(app.textFields["browser-new-tab-search"].exists)
        XCTAssertFalse(app.textFields["browser-omnibar"].exists)
    }

    /// Opening the Browser pane via the app shortcut must surface browser UI
    /// without crashing the app. This exercises Chromium startup in the built
    /// macOS bundle.
    func testLegacyBrowserShortcutOpensBrowserPane() throws {
        guard ProcessInfo.processInfo.environment["BUGBOOK_RUN_LEGACY_PANE_UI_TESTS"] == "1" else {
            throw XCTSkip("Legacy panes are feature-flagged off by default; run with BUGBOOK_RUN_LEGACY_PANE_UI_TESTS=1.")
        }

        launchApp(legacyPanes: true)
        app.typeKey("b", modifierFlags: [.command, .shift])

        let newTabSearch = app.textFields["browser-new-tab-search"]
        let omnibar = app.textFields["browser-omnibar"]
        let browserPane = app.otherElements["browser-pane"]

        let browserAppeared =
            newTabSearch.waitForExistence(timeout: 5) ||
            omnibar.waitForExistence(timeout: 5) ||
            browserPane.waitForExistence(timeout: 5)

        XCTAssertTrue(
            browserAppeared,
            "Browser pane did not appear after Cmd-Shift-B — possible Chromium startup or helper bundle regression"
        )
    }
}
