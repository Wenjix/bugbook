import Foundation
import WebKit

/// Locked-down WKWebView plumbing for HTML artifacts (Level 1).
///
/// Threat model: the artifact author is an agent that may be operating under
/// prompt injection — every artifact is treated as attacker-controlled code.
/// Defenses, layered:
///  - custom scheme handler serving exactly one token-mapped file (T2),
///  - CSP response header denying all remote loads (T1),
///  - WKContentRuleList blocking http(s)/ws(s) in the network process (T1, kill switch),
///  - non-persistent website data store (T6),
///  - navigation delegate cancelling everything except the artifact itself,
///    with native confirmation for user-clicked external links (T1/T4).
enum ArtifactSandbox {
    static let scheme = "bugbook-artifact"

    /// Served as a real response header by the scheme handler.
    static let contentSecurityPolicy =
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; " +
        "img-src data: blob:; font-src data:; connect-src 'none'; form-action 'none'; " +
        "base-uri 'none'; frame-src 'none'"

    /// Compiled in the network process — blocks even loads CSP might miss.
    static let networkBlockRulesJSON = """
    [
        {"trigger": {"url-filter": "^https?://"}, "action": {"type": "block"}},
        {"trigger": {"url-filter": "^wss?://"}, "action": {"type": "block"}}
    ]
    """

    private static let ruleListIdentifier = "BugbookArtifactNetworkBlock.v1"
    @MainActor private static var cachedRuleList: WKContentRuleList?

    enum SandboxError: LocalizedError {
        case unknownResource
        case ruleListUnavailable

        var errorDescription: String? {
            switch self {
            case .unknownResource:
                return "Requested resource is not registered with this artifact pane."
            case .ruleListUnavailable:
                return "The artifact network-block rule list could not be compiled."
            }
        }
    }

    /// Compiles (or returns the cached) network-block rule list.
    /// Throws when compilation fails — callers must treat that as fatal for
    /// rendering (fail closed): an artifact never loads without the rule list.
    @MainActor
    static func networkBlockRuleList() async throws -> WKContentRuleList {
        if let cachedRuleList { return cachedRuleList }
        let compiled: WKContentRuleList? = try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: ruleListIdentifier,
                encodedContentRuleList: networkBlockRulesJSON
            ) { ruleList, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ruleList)
                }
            }
        }
        guard let compiled else { throw SandboxError.ruleListUnavailable }
        cachedRuleList = compiled
        return compiled
    }

    /// Builds the locked-down configuration. The scheme handler must be attached
    /// here, before WKWebView init — WebKit rejects later registration.
    @MainActor
    static func makeConfiguration(
        handler: ArtifactSchemeHandler,
        ruleList: WKContentRuleList
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(handler, forURLScheme: scheme)
        configuration.userContentController.add(ruleList)
        return configuration
    }
}

/// Serves exactly one registered file at `bugbook-artifact://a/<UUID-token>`.
/// Every other request — sub-resources, sibling tokens, traversal attempts —
/// fails. The real file path never reaches page JS (no file:// origin).
@MainActor
final class ArtifactSchemeHandler: NSObject, WKURLSchemeHandler {
    let fileURL: URL
    let token: String

    /// The only URL this handler will ever serve. One token per pane open;
    /// FSEvents live-reload re-serves fresh bytes through the same token (the
    /// data store is non-persistent and pane-scoped, so a stable within-open
    /// origin grants no cross-artifact persistence).
    var artifactURL: URL {
        URL(string: "\(ArtifactSandbox.scheme)://a/\(token)")!
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.token = UUID().uuidString
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requested = urlSchemeTask.request.url,
              requested.absoluteString == artifactURL.absoluteString else {
            Log.fileSystem.error("ArtifactSchemeHandler refused unregistered resource request")
            urlSchemeTask.didFailWithError(ArtifactSandbox.SandboxError.unknownResource)
            return
        }

        do {
            // Synchronous read is deliberate: artifacts are single small files
            // (CLI validate errors above 10 MB) and replies complete before any
            // concurrent stop() bookkeeping would be needed.
            let data = try Data(contentsOf: fileURL)
            guard let response = HTTPURLResponse(
                url: requested,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/html; charset=utf-8",
                    "Content-Length": String(data.count),
                    "Content-Security-Policy": ArtifactSandbox.contentSecurityPolicy,
                    "Cache-Control": "no-store",
                ]
            ) else {
                urlSchemeTask.didFailWithError(ArtifactSandbox.SandboxError.unknownResource)
                return
            }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            Log.fileSystem.error("ArtifactSchemeHandler failed to read artifact: \(error.localizedDescription)")
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Replies are synchronous in start(); nothing in flight to cancel.
    }
}

/// Navigation policy: the artifact document itself (initial load, reloads, and
/// same-document #anchor jumps) is the only permitted navigation. User-activated
/// http(s) links surface a native confirmation; everything else is cancelled.
/// Also the WKUIDelegate, so target=_blank routes through the same confirmation
/// and window.open never creates a window.
@MainActor
final class ArtifactNavigationPolicy: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let artifactURL: URL
    var onExternalLinkRequest: ((URL) -> Void)?
    var onLoadFinished: (() -> Void)?
    var onLoadFailed: ((String) -> Void)?

    init(artifactURL: URL) {
        self.artifactURL = artifactURL
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // The artifact itself, main frame only — covers the initial load,
        // FSEvents-driven reload(), and in-page #anchor navigation (TOC links
        // inside artifacts must keep working, decision 6). Sibling-token
        // probing has a different path → cancelled here AND refused by the
        // scheme handler.
        if navigationAction.targetFrame?.isMainFrame == true,
           stripFragment(url) == stripFragment(artifactURL) {
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            onExternalLinkRequest?(url)
        }

        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadFinished?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadFailed?(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadFailed?(error.localizedDescription)
    }

    private func stripFragment(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            onExternalLinkRequest?(url)
        }
        return nil  // window.open and target=_blank never spawn a window
    }
}
