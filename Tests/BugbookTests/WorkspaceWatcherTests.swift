import XCTest
@testable import Bugbook

final class WorkspaceWatcherTests: XCTestCase {
    func testRapidObservedChangesAreDebounced() async {
        let expectation = expectation(description: "debounced workspace refresh")
        expectation.expectedFulfillmentCount = 1
        expectation.assertForOverFulfill = true

        let watcher = WorkspaceWatcher(debounceInterval: 0.03) {
            expectation.fulfill()
        }
        defer { watcher.stop() }

        watcher.handleObservedChange()
        watcher.handleObservedChange()
        watcher.handleObservedChange()

        await fulfillment(of: [expectation], timeout: 1)
        try? await Task.sleep(for: .milliseconds(80))
    }

    func testStopCancelsPendingDebouncedRefresh() async {
        let expectation = expectation(description: "cancelled workspace refresh")
        expectation.isInverted = true

        let watcher = WorkspaceWatcher(debounceInterval: 0.03) {
            expectation.fulfill()
        }

        watcher.handleObservedChange()
        watcher.stop()

        await fulfillment(of: [expectation], timeout: 0.12)
    }
}
