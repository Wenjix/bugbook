import XCTest
@testable import DahsoCore

final class AttachmentPathResolverTests: XCTestCase {
    private func makeTemporaryWorkspace() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DahsoAttachmentResolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    func testResolveWorkspaceAttachmentPathPrefersWorkspaceAttachmentsFolder() throws {
        let workspace = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let museumDirectory = (workspace as NSString).appendingPathComponent("Museum")
        let pagePath = (museumDirectory as NSString).appendingPathComponent("Field Notes.md")
        let attachmentsDirectory = (workspace as NSString).appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(atPath: attachmentsDirectory, withIntermediateDirectories: true)

        let attachmentPath = (attachmentsDirectory as NSString).appendingPathComponent("capture.jpg")
        FileManager.default.createFile(atPath: attachmentPath, contents: Data())

        let resolved = resolveWorkspaceAttachmentPath(
            "Attachments/capture.jpg",
            pagePath: pagePath,
            workspacePath: workspace
        )

        XCTAssertEqual(resolved, attachmentPath)
    }

    func testResolveWorkspaceAttachmentPathFallsBackToPageDirectoryForRelativeFiles() throws {
        let workspace = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let pageDirectory = (workspace as NSString).appendingPathComponent("Museum")
        try FileManager.default.createDirectory(atPath: pageDirectory, withIntermediateDirectories: true)

        let pagePath = (pageDirectory as NSString).appendingPathComponent("Field Notes.md")
        let imagePath = (pageDirectory as NSString).appendingPathComponent("detail.jpg")
        FileManager.default.createFile(atPath: imagePath, contents: Data())

        let resolved = resolveWorkspaceAttachmentPath(
            "detail.jpg",
            pagePath: pagePath,
            workspacePath: workspace
        )

        XCTAssertEqual(resolved, imagePath)
    }

    func testResolveWorkspaceAttachmentPathDecodesPercentEscapedRelativeFiles() throws {
        let workspace = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let pageDirectory = (workspace as NSString).appendingPathComponent("Museum")
        try FileManager.default.createDirectory(atPath: pageDirectory, withIntermediateDirectories: true)

        let pagePath = (pageDirectory as NSString).appendingPathComponent("Field Notes.md")
        let imagePath = (pageDirectory as NSString).appendingPathComponent("detail 01.jpg")
        FileManager.default.createFile(atPath: imagePath, contents: Data())

        let resolved = resolveWorkspaceAttachmentPath(
            "detail%2001.jpg",
            pagePath: pagePath,
            workspacePath: workspace
        )

        XCTAssertEqual(resolved, imagePath)
    }
}
