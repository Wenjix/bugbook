import AppKit
import Foundation
import WebKit

@MainActor
final class WebKitBrowserEngine: BrowserEngine {
    private let websiteDataStore = WKWebsiteDataStore.default()

    func makePage(
        for paneID: UUID,
        tabID: UUID,
        initialURL: URL?,
        eventHandler: @escaping BrowserPageEventHandler
    ) -> any BrowserPage {
        WebKitBrowserPage(
            websiteDataStore: websiteDataStore,
            initialURL: initialURL,
            eventHandler: eventHandler
        )
    }
}

@MainActor
private final class WebKitBrowserPage: NSObject, BrowserPage {
    let webView: WKWebView
    private let eventHandler: BrowserPageEventHandler
    private lazy var coordinator = WebKitBrowserPageCoordinator(page: self)
    private lazy var downloadDelegate = WebKitBrowserDownloadDelegate(page: self)

    init(
        websiteDataStore: WKWebsiteDataStore,
        initialURL: URL?,
        eventHandler: @escaping BrowserPageEventHandler
    ) {
        self.eventHandler = eventHandler

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.applicationNameForUserAgent = "HarborDesktop"

        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *), AppEnvironment.isDev {
            webView.isInspectable = true
        }
        self.webView = webView

        super.init()

        userContentController.add(coordinator, name: WebKitBrowserPageCoordinator.hoverScriptName)
        userContentController.addUserScript(coordinator.hoverUserScript)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinator.attach(to: webView)

        if let initialURL {
            load(URLRequest(url: initialURL))
        } else {
            emitStateChange()
        }
    }

    var hostView: NSView {
        webView
    }

    var state: BrowserPageState {
        BrowserPageState(
            title: webView.title,
            url: webView.url,
            isLoading: webView.isLoading,
            estimatedProgress: webView.estimatedProgress,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward,
            pageZoom: max(Double(webView.pageZoom), 0.01)
        )
    }

    func load(_ request: URLRequest) {
        webView.load(request)
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func stopLoading() {
        webView.stopLoading()
    }

    func setPageZoom(_ zoom: Double) {
        webView.pageZoom = zoom
        emitStateChange()
    }

    func printPage() {
        let operation = webView.printOperation(with: .shared)
        operation.run()
    }

    func find(_ query: String, forward: Bool) {
        guard !query.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.wraps = true
        webView.find(query, configuration: configuration) { _ in }
    }

    func evaluateJavaScript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let string = result as? String {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(throwing: BrowserPageJavaScriptError.invalidResult)
                }
            }
        }
    }

    func dispose() {
        coordinator.detach(from: webView)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    fileprivate func emitStateChange() {
        eventHandler(.stateChanged(state))
    }

    fileprivate func emitHoverURL(_ urlString: String?) {
        eventHandler(.hoverURLChanged(urlString))
    }

    fileprivate func emitDidFinishNavigation() {
        guard let url = webView.url else { return }
        eventHandler(.didFinishNavigation(title: navigationTitle(for: url), url: url))
    }

    fileprivate func emitOpenInNewTab(_ url: URL) {
        eventHandler(.openInNewTab(url))
    }

    fileprivate func emitDownloadStatus(_ message: String) {
        eventHandler(.downloadStatusChanged(message))
    }

    fileprivate func attachDownloadDelegate(to download: WKDownload) {
        download.delegate = downloadDelegate
    }

    private func navigationTitle(for url: URL) -> String {
        let trimmedTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTitle, !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return url.host ?? url.absoluteString
    }
}

private enum BrowserPageJavaScriptError: Error {
    case invalidResult
}

@MainActor
private final class WebKitBrowserPageCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let hoverScriptName = "browserLinkHover"

    private weak var page: WebKitBrowserPage?
    private var observations: [NSKeyValueObservation] = []

    init(page: WebKitBrowserPage) {
        self.page = page
    }

    var hoverUserScript: WKUserScript {
        let source = """
        document.addEventListener('mouseover', function(event) {
          const anchor = event.target.closest('a[href]');
          window.webkit.messageHandlers.\(Self.hoverScriptName).postMessage(anchor ? anchor.href : "");
        }, true);
        document.addEventListener('mouseout', function(event) {
          const anchor = event.target.closest('a[href]');
          if (anchor) {
            window.webkit.messageHandlers.\(Self.hoverScriptName).postMessage("");
          }
        }, true);
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    func attach(to webView: WKWebView) {
        observations = makeObservations(for: webView)
    }

    func detach(from webView: WKWebView) {
        observations.removeAll()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.hoverScriptName)
    }

    nonisolated private func scheduleStateUpdate() {
        Task { @MainActor [weak self] in
            self?.page?.emitStateChange()
        }
    }

    private func makeObservations(for webView: WKWebView) -> [NSKeyValueObservation] {
        [
            observe(webView, \.title),
            observe(webView, \.url),
            observe(webView, \.estimatedProgress),
            observe(webView, \.isLoading),
            observe(webView, \.canGoBack),
            observe(webView, \.canGoForward),
        ]
    }

    private func observe<Value>(_ webView: WKWebView, _ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        webView.observe(keyPath, options: [.initial, .new]) { [weak self] _, _ in
            self?.scheduleStateUpdate()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.hoverScriptName else { return }
        let urlString = message.body as? String
        page?.emitHoverURL(urlString?.isEmpty == true ? nil : urlString)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        page?.emitStateChange()
        page?.emitDidFinishNavigation()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        page?.emitStateChange()
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        page?.attachDownloadDelegate(to: download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        page?.attachDownloadDelegate(to: download)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else {
            return nil
        }
        page?.emitOpenInNewTab(url)
        return nil
    }
}

@MainActor
private final class WebKitBrowserDownloadDelegate: NSObject, WKDownloadDelegate {
    private weak var page: WebKitBrowserPage?

    init(page: WebKitBrowserPage) {
        self.page = page
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let destination = uniqueDestination(in: directory, suggestedFilename: suggestedFilename)
        completionHandler(destination)
        page?.emitDownloadStatus("Downloading \(suggestedFilename)…")
    }

    func downloadDidFinish(_ download: WKDownload) {
        page?.emitDownloadStatus("Download finished")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        page?.emitDownloadStatus(error.localizedDescription)
    }

    private func uniqueDestination(in directory: URL, suggestedFilename: String) -> URL {
        let baseName = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(suggestedFilename)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName: String
            if ext.isEmpty {
                nextName = "\(baseName) \(suffix)"
            } else {
                nextName = "\(baseName) \(suffix).\(ext)"
            }
            candidate = directory.appendingPathComponent(nextName)
            suffix += 1
        }
        return candidate
    }
}
