import XCTest
@testable import Bugbook

final class MeetingSummaryServiceTests: XCTestCase {
    func testGenerateSummaryParsesCommandOutput() async throws {
        let service = MeetingSummaryService()
        let command = """
        cat >/dev/null; printf '%s\\n' \
        'TITLE: Parent Interview' \
        '' \
        'SUMMARY:' \
        '- They want smoother notes' \
        '- Meeting capture should stay simple' \
        '' \
        'ACTION ITEMS:' \
        '- Send follow-up'
        """

        let result = try await service.generateSummary(transcript: "raw transcript", command: command)

        XCTAssertEqual(result.title, "Parent Interview")
        XCTAssertEqual(result.summary, [
            "They want smoother notes",
            "Meeting capture should stay simple"
        ])
        XCTAssertEqual(result.actionItems, ["Send follow-up"])
    }

    func testGenerateSummaryRejectsOutputWithoutSummaryBullets() async {
        let service = MeetingSummaryService()
        let command = "cat >/dev/null; printf '%s\\n' 'TITLE: Empty' 'SUMMARY:'"

        do {
            _ = try await service.generateSummary(transcript: "raw transcript", command: command)
            XCTFail("Expected missing summary error")
        } catch let error as MeetingSummaryGenerationError {
            XCTAssertEqual(error.localizedDescription, "Summary generation did not return a usable summary.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateSummaryTimesOutHungCommand() async {
        let service = MeetingSummaryService(commandTimeout: 1)
        let command = "sleep 5"

        do {
            _ = try await service.generateSummary(transcript: "raw transcript", command: command)
            XCTFail("Expected timeout error")
        } catch let error as MeetingSummaryGenerationError {
            XCTAssertEqual(error.localizedDescription, "Summary generation timed out after 1 seconds.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateSummaryTimesOutNestedChildCommand() async {
        let service = MeetingSummaryService(commandTimeout: 1)
        let command = "sh -c 'sleep 5'"

        do {
            _ = try await service.generateSummary(transcript: "raw transcript", command: command)
            XCTFail("Expected timeout error")
        } catch let error as MeetingSummaryGenerationError {
            XCTAssertEqual(error.localizedDescription, "Summary generation timed out after 1 seconds.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
