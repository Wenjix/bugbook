import XCTest

/// UI tests that catch render loops, CPU spikes, and UI freezes.
/// Run via Xcode: Product → Test (Cmd+U) with the BugbookApp scheme.
final class BugbookUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app.terminate()
    }

    private func launchApp(legacyPanes: Bool = false) {
        app.launchEnvironment["BUGBOOK_LEGACY_PANES"] = legacyPanes ? "1" : "0"
        app.launch()
    }

    /// Finds the first clickable file-tree item in the sidebar.
    private func firstSidebarItem() -> XCUIElement? {
        let fileTree = app.scrollViews["sidebar-file-tree"]
        guard fileTree.waitForExistence(timeout: 5) else { return nil }

        // File tree items have accessibilityIdentifier "file-tree-item-{name}"
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'file-tree-item-'")
        let items = fileTree.descendants(matching: .any).matching(predicate)
        // swiftlint:disable:next empty_count
        guard items.count > 0 else { return nil }
        return items.firstMatch
    }

    // MARK: - Responsiveness Tests

    /// Selecting a note must not freeze the UI.
    /// If a render loop or CPU spike occurs, the editor won't appear within the timeout.
    func testSelectNoteDoesNotFreeze() {
        launchApp()

        guard let item = firstSidebarItem() else {
            XCTFail("No files found in sidebar — need at least one note in workspace")
            return
        }

        item.click()

        // The editor area must appear within 3 seconds.
        // A render loop / CPU spike would cause this to timeout.
        let editor = app.scrollViews["editor"]
        XCTAssertTrue(
            editor.waitForExistence(timeout: 3),
            "Editor did not appear within 3 seconds after selecting a note — possible render loop or CPU spike"
        )
    }

    /// Measures CPU impact of opening a note.
    /// Run repeatedly to establish a baseline; Xcode flags regressions automatically.
    func testSelectNoteCPUBaseline() {
        launchApp()

        guard let item = firstSidebarItem() else {
            XCTFail("No files in sidebar")
            return
        }

        let cpuMetric = XCTCPUMetric(application: app)
        measure(metrics: [cpuMetric]) {
            item.click()
            let editor = app.scrollViews["editor"]
            _ = editor.waitForExistence(timeout: 3)
        }
    }

    /// Rapidly switching between notes must not accumulate CPU or crash.
    func testRapidNoteSwitchingDoesNotFreeze() {
        launchApp()

        let fileTree = app.scrollViews["sidebar-file-tree"]
        guard fileTree.waitForExistence(timeout: 5) else {
            XCTFail("Sidebar file tree did not appear")
            return
        }

        let predicate = NSPredicate(format: "identifier BEGINSWITH 'file-tree-item-'")
        let items = fileTree.descendants(matching: .any).matching(predicate)
        guard items.count >= 2 else {
            // Only one note — skip rapid switching test
            return
        }

        let first = items.element(boundBy: 0)
        let second = items.element(boundBy: 1)

        // Switch between first two notes 10 times
        for i in 0..<10 {
            let target = (i % 2 == 0) ? first : second
            if target.exists {
                target.click()
            }
            usleep(100_000) // 100ms
        }

        // App must still be responsive — editor should exist
        let editor = app.scrollViews["editor"]
        XCTAssertTrue(
            editor.waitForExistence(timeout: 3),
            "App became unresponsive after rapid note switching"
        )
    }

    func testDefaultModeNavigationExposesOnlyMeeting() {
        launchApp()

        XCTAssertTrue(app.buttons["shell-nav-meeting"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["shell-nav-notes"].exists)
        XCTAssertFalse(app.buttons["shell-nav-home"].exists)
        XCTAssertFalse(app.buttons["shell-nav-search"].exists)
        XCTAssertFalse(app.buttons["shell-nav-calendar"].exists)
        XCTAssertFalse(app.buttons["shell-nav-terminal"].exists)
        XCTAssertFalse(app.buttons["shell-nav-browser"].exists)
        XCTAssertFalse(app.buttons["shell-nav-mail"].exists)
    }

    func testDefaultModeBrowserShortcutDoesNotOpenBrowserPane() {
        launchApp()
        app.typeKey("b", modifierFlags: [.command, .shift])

        XCTAssertFalse(app.otherElements["browser-pane"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.textFields["browser-new-tab-search"].exists)
        XCTAssertFalse(app.textFields["browser-omnibar"].exists)
    }

    /// Opening the Browser pane via the app shortcut must surface browser UI
    /// without crashing the app. This exercises Chromium startup in the built
    /// macOS bundle.
    func testLegacyBrowserShortcutOpensBrowserPane() {
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
