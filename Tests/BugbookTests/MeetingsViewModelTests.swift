import XCTest
@testable import Bugbook

@MainActor
final class MeetingsViewModelTests: XCTestCase {
    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookMeetingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testScanFollowsSymlinkedWorkspaceRoot() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let target = root.appendingPathComponent("Bugbook Target", isDirectory: true)
        let link = root.appendingPathComponent("Bugbook", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let meeting = target.appendingPathComponent("Legacy Meeting.md")
        try """
        ---
        title: Legacy Meeting
        date: 2026-04-28T21:01:07Z
        type: meeting
        meeting_id: legacy-meeting
        ---

        # Restored meeting title
        """.write(to: meeting, atomically: true, encoding: .utf8)

        let viewModel = MeetingsViewModel()
        viewModel.scan(workspace: link.path)

        let deadline = Date().addingTimeInterval(2)
        while viewModel.isScanning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertFalse(viewModel.isScanning)
        XCTAssertEqual(viewModel.meetings.map(\.title), ["Restored meeting title"])
        XCTAssertEqual(
            viewModel.meetings.first.map { URL(fileURLWithPath: $0.filePath).standardizedFileURL.path },
            meeting.standardizedFileURL.path
        )
    }
}
