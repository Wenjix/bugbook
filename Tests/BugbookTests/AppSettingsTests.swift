import XCTest
@testable import Bugbook

final class AppSettingsTests: XCTestCase {
    func testNotesFolderPathRoundTripsThroughSettingsJSON() throws {
        var settings = AppSettings.default
        settings.notesFolderPath = "/tmp/Bugbook Notes"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.notesFolderPath, "/tmp/Bugbook Notes")
    }

    func testMissingNotesFolderPathDefaultsToDynamicWorkspaceResolution() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"theme":"system"}"#.utf8))

        XCTAssertEqual(decoded.notesFolderPath, "")
    }

    func testFocusModeWhileTypingDefaultsToEnabled() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"theme":"system"}"#.utf8))

        XCTAssertTrue(AppSettings.default.focusModeOnType)
        XCTAssertTrue(decoded.focusModeOnType)
    }

    func testResolvedNotesFolderPathUsesTrimmedSettingsPathByDefault() {
        var settings = AppSettings.default
        settings.notesFolderPath = "  /tmp/Bugbook Notes  "

        XCTAssertEqual(
            settings.resolvedNotesFolderPath(environment: [:]),
            "/tmp/Bugbook Notes"
        )
    }

    func testResolvedNotesFolderPathAllowsProfileWorkspaceOverride() {
        var settings = AppSettings.default
        settings.notesFolderPath = "/tmp/Real Notes"

        XCTAssertEqual(
            settings.resolvedNotesFolderPath(environment: [
                AppSettings.profileWorkspacePathEnvironmentKey: "  /tmp/Bugbook Profile Notes  "
            ]),
            "/tmp/Bugbook Profile Notes"
        )
    }
}
