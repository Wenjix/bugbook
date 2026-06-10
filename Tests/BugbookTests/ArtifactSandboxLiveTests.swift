import XCTest
import WebKit
@testable import Bugbook

/// Live WKWebView verification of the sandbox — the design doc's mandated
/// empirical check that CSP-via-scheme-handler and content rule lists behave
/// on current WebKit. Set BUGBOOK_SKIP_WEBKIT_TESTS=1 to skip (headless CI).
@MainActor
final class ArtifactSandboxLiveTests: XCTestCase {
    private var tempDir: URL!
    private var retainedPolicies: [ArtifactNavigationPolicy] = []
    private var retainedWebViews: [WKWebView] = []

    override func setUp() async throws {
        if ProcessInfo.processInfo.environment["BUGBOOK_SKIP_WEBKIT_TESTS"] == "1" {
            throw XCTSkip("WebKit live tests disabled by BUGBOOK_SKIP_WEBKIT_TESTS")
        }
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtifactSandboxLiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for webView in retainedWebViews {
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.stopLoading()
        }
        retainedWebViews = []
        retainedPolicies = []
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testNetworkBlockRuleListCompiles() async throws {
        _ = try await ArtifactSandbox.networkBlockRuleList()
    }

    func testBenignArtifactRenders() async throws {
        // Control for fail-closed: scheme handler + rule list + CSP must not
        // break a legitimate inline-everything artifact.
        let url = try write("benign.html", html: """
        <!doctype html><html><head>
        <meta name="bugbook-artifact" content="1">
        <title>start</title>
        </head><body>
        <a id="anchor-link" href="#section">jump</a>
        <div id="section" style="margin-top: 2000px">target</div>
        <script>document.title = "rendered";</script>
        </body></html>
        """)
        let webView = try await loadArtifact(at: url)

        let title = await pollJS(webView, script: "document.title", until: { $0 == "rendered" })
        XCTAssertEqual(title, "rendered")

        // In-page anchor navigation must not be cancelled (decision 6).
        _ = await pollJS(
            webView,
            script: "document.getElementById('anchor-link').click(); 'clicked'",
            until: { $0 == "clicked" }
        )
        let hash = await pollJS(webView, script: "window.location.hash", until: { $0 == "#section" })
        XCTAssertEqual(hash, "#section")
    }

    func testHostileFixtureAllProbesBlocked() async throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(
            forResource: "hostile-artifact", withExtension: "html", subdirectory: "Fixtures"))
        let webView = try await loadArtifact(at: fixtureURL)
        try await assertAllProbesBlocked(webView)
    }

    func testNoPersistenceAcrossSessions() async throws {
        // Two separately-constructed sessions: anything surviving into the
        // second (localStorage item, cookie) flips its probe to "allowed".
        let fixtureURL = try XCTUnwrap(Bundle.module.url(
            forResource: "hostile-artifact", withExtension: "html", subdirectory: "Fixtures"))
        for _ in 0..<2 {
            let webView = try await loadArtifact(at: fixtureURL)
            try await assertAllProbesBlocked(webView)
        }
    }

    // MARK: - Harness

    private func write(_ name: String, html: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func loadArtifact(at url: URL) async throws -> WKWebView {
        let ruleList = try await ArtifactSandbox.networkBlockRuleList()
        let handler = ArtifactSchemeHandler(fileURL: url)
        let policy = ArtifactNavigationPolicy(artifactURL: handler.artifactURL)
        retainedPolicies.append(policy)  // delegates are weak — must retain
        let configuration = ArtifactSandbox.makeConfiguration(handler: handler, ruleList: ruleList)
        let webView = WKWebView(
            frame: .init(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        webView.navigationDelegate = policy
        webView.uiDelegate = policy
        retainedWebViews.append(webView)
        webView.load(URLRequest(url: handler.artifactURL))
        return webView
    }

    private func assertAllProbesBlocked(_ webView: WKWebView) async throws {
        let json = await pollJS(
            webView,
            script: "window.__probesComplete === true ? JSON.stringify(window.__results) : null",
            until: { $0 != nil },
            timeout: 30
        )
        let results = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data((json ?? "{}").utf8)) as? [String: String],
            "probes never completed — a navigation probe may have escaped (page unloaded)"
        )

        XCTAssertEqual(results["control-img-data"], "allowed",
                       "data: URI control must load — otherwise blocked results are meaningless")
        for (probe, outcome) in results where probe != "control-img-data" {
            XCTAssertEqual(outcome, "blocked", "escape probe '\(probe)' was not blocked")
        }
        XCTAssertGreaterThanOrEqual(results.count, 13, "fixture must report all probes")
    }

    private final class ResultBox { var value: String? }

    /// Polls `script` every 200 ms until `until` accepts the value.
    /// `fulfillment(of:)` keeps the main run loop serviced for WebKit callbacks.
    @discardableResult
    private func pollJS(
        _ webView: WKWebView,
        script: String,
        until accept: @escaping (String?) -> Bool,
        timeout: TimeInterval = 15
    ) async -> String? {
        let done = expectation(description: "pollJS")
        let box = ResultBox()
        var fulfilled = false

        func tick() {
            webView.evaluateJavaScript(script) { value, _ in
                guard !fulfilled else { return }
                let string = value as? String
                if accept(string) {
                    fulfilled = true
                    box.value = string
                    done.fulfill()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { tick() }
                }
            }
        }
        tick()
        await fulfillment(of: [done], timeout: timeout)
        fulfilled = true  // stop rescheduling after timeout
        return box.value
    }
}
