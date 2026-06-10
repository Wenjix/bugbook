import XCTest
import WebKit
@testable import Bugbook

/// Records everything the handler sends. WKURLSchemeTask is a protocol, so the
/// handler is exercised directly without loading a page.
private final class MockSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    private(set) var receivedResponse: URLResponse?
    private(set) var receivedData = Data()
    private(set) var didFinishCalled = false
    private(set) var failedError: Error?

    init(url: URL) {
        self.request = URLRequest(url: url)
    }

    func didReceive(_ response: URLResponse) { receivedResponse = response }
    func didReceive(_ data: Data) { receivedData.append(data) }
    func didFinish() { didFinishCalled = true }
    func didFailWithError(_ error: Error) { failedError = error }
}

@MainActor
final class ArtifactSchemeHandlerTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!
    private let html = #"<!doctype html><meta name="bugbook-artifact" content="1"><h1>ok</h1>"#

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtifactSchemeHandlerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("a.html")
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testServesRegisteredTokenWithCSPHeader() {
        let handler = ArtifactSchemeHandler(fileURL: fileURL)
        let task = MockSchemeTask(url: handler.artifactURL)
        handler.webView(WKWebView(), start: task)

        let response = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(response?.statusCode, 200)
        XCTAssertEqual(
            response?.value(forHTTPHeaderField: "Content-Security-Policy"),
            ArtifactSandbox.contentSecurityPolicy
        )
        XCTAssertEqual(response?.value(forHTTPHeaderField: "Content-Type"), "text/html; charset=utf-8")
        XCTAssertEqual(task.receivedData, Data(html.utf8))
        XCTAssertTrue(task.didFinishCalled)
        XCTAssertNil(task.failedError)
    }

    func testRefusesUnregisteredToken() {
        let handler = ArtifactSchemeHandler(fileURL: fileURL)
        let task = MockSchemeTask(
            url: URL(string: "bugbook-artifact://a/00000000-0000-0000-0000-000000000000")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertNotNil(task.failedError)
        XCTAssertNil(task.receivedResponse)
        XCTAssertTrue(task.receivedData.isEmpty)
        XCTAssertFalse(task.didFinishCalled)
    }

    func testRefusesSubResourceUnderToken() {
        let handler = ArtifactSchemeHandler(fileURL: fileURL)
        let task = MockSchemeTask(url: handler.artifactURL.appendingPathComponent("x.png"))
        handler.webView(WKWebView(), start: task)
        XCTAssertNotNil(task.failedError)
        XCTAssertNil(task.receivedResponse)
    }

    func testServesFreshBytesAfterFileChangeWithSameToken() throws {
        // Locks the live-reload contract: same token, fresh bytes (decision 2).
        let handler = ArtifactSchemeHandler(fileURL: fileURL)
        let first = MockSchemeTask(url: handler.artifactURL)
        handler.webView(WKWebView(), start: first)
        XCTAssertEqual(first.receivedData, Data(html.utf8))

        let updated = html + "<p>v2</p>"
        try updated.write(to: fileURL, atomically: true, encoding: .utf8)
        let second = MockSchemeTask(url: handler.artifactURL)
        handler.webView(WKWebView(), start: second)
        XCTAssertEqual(second.receivedData, Data(updated.utf8))
    }

    func testTokensAreUniquePerHandler() {
        XCTAssertNotEqual(
            ArtifactSchemeHandler(fileURL: fileURL).token,
            ArtifactSchemeHandler(fileURL: fileURL).token
        )
    }
}
