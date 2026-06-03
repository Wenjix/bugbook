import XCTest
@testable import Bugbook

final class EditorTypographyTests: XCTestCase {
    func testDefaultZoomScaleFallsBackToActualSize() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: EditorTypography.zoomScaleKey)
        defaults.removeObject(forKey: EditorTypography.zoomScaleKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: EditorTypography.zoomScaleKey)
            } else {
                defaults.removeObject(forKey: EditorTypography.zoomScaleKey)
            }
        }

        XCTAssertEqual(EditorTypography.defaultZoomScale, 1.0)
        XCTAssertEqual(EditorTypography.zoomScale, 1.0)
    }

    @MainActor
    func testTypingFocusStaysActiveUntilPointerMoves() {
        let state = EditorUIState()

        state.setFocusModeEnabled(true)
        state.triggerFocusMode()

        XCTAssertTrue(state.focusModeActive)

        state.handlePointerMovement()

        XCTAssertFalse(state.focusModeActive)
    }

    @MainActor
    func testTypingFocusDoesNotActivateWhenDisabled() {
        let state = EditorUIState()

        state.setFocusModeEnabled(false)
        state.triggerFocusMode()

        XCTAssertFalse(state.focusModeActive)
    }
}
