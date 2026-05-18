import Foundation

private func prepareTestDirectory(at directoryURL: URL) throws {
    if FileManager.default.fileExists(atPath: directoryURL.path) {
        try FileManager.default.removeItem(at: directoryURL)
    }

    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    try "hello from Bugbook MCP\n"
        .write(to: directoryURL.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)

    try FileManager.default.createDirectory(
        at: directoryURL.appendingPathComponent("notes", isDirectory: true),
        withIntermediateDirectories: true
    )
}

let testDirectoryURL = URL(fileURLWithPath: "/tmp/bugbook-mcp-test", isDirectory: true)

do {
    try prepareTestDirectory(at: testDirectoryURL)
    let report = try await MCPFilesystemSpike.run(testDirectoryURL: testDirectoryURL)
    print(report.prettyPrintedSummary())
} catch {
    fputs("BugbookMCPSpike failed: \(error.localizedDescription)\n", stderr)
    Foundation.exit(1)
}
