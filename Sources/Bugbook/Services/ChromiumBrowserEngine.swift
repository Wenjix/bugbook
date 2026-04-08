#if BUGBOOK_BROWSER_CHROMIUM
import AppKit
import Foundation
@preconcurrency import ChromiumBridge

@MainActor
final class ChromiumBrowserEngine: BrowserEngine {
    init() {}

    func makePage(
        for paneID: UUID,
        tabID: UUID,
        initialURL: URL?,
        eventHandler: @escaping BrowserPageEventHandler
    ) -> any BrowserPage {
        BBChromiumRuntime.startIfNeeded()
        return ChromiumBrowserPage(initialURL: initialURL, eventHandler: eventHandler)
    }
}

@MainActor
private final class ChromiumBrowserPage: NSObject, BrowserPage, @preconcurrency BBChromiumPageDelegate {
    private let page: BBChromiumPage
    private let eventHandler: BrowserPageEventHandler

    init(initialURL: URL?, eventHandler: @escaping BrowserPageEventHandler) {
        self.page = BBChromiumPage(initialURLString: nil)
        self.eventHandler = eventHandler
        super.init()
        page.delegate = self
        loadURL(initialURL)
    }

    var hostView: NSView {
        page.hostView
    }

    var state: BrowserPageState {
        state(from: page.state)
    }

    func load(_ request: URLRequest) {
        loadURL(request.url)
    }

    func goBack() {
        page.goBack()
    }

    func goForward() {
        page.goForward()
    }

    func reload() {
        page.reload()
    }

    func stopLoading() {
        page.stopLoading()
    }

    func setPageZoom(_ zoom: Double) {
        page.setPageZoom(zoom)
    }

    func printPage() {
        page.print()
    }

    func find(_ query: String, forward: Bool) {
        page.findText(query, forward: forward)
    }

    func evaluateJavaScript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            page.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: ChromiumBrowserError.invalidJavaScriptResult)
                }
            }
        }
    }

    func dispose() {
        page.delegate = nil
        page.dispose()
    }

    func chromiumPageDidUpdate(_ state: BBChromiumPageState) {
        eventHandler(.stateChanged(self.state(from: state)))
    }

    func chromiumPageDidChangeHoverURL(_ urlString: String?) {
        eventHandler(.hoverURLChanged(urlString))
    }

    func chromiumPageDidFinishNavigation(withTitle title: String, urlString: String) {
        guard let url = URL(string: urlString) else { return }
        eventHandler(.didFinishNavigation(title: title, url: url))
    }

    func chromiumPageDidRequestNewTab(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        eventHandler(.openInNewTab(url))
    }

    func chromiumPageDidUpdateDownloadStatus(_ status: String) {
        eventHandler(.downloadStatusChanged(status))
    }

    private func state(from state: BBChromiumPageState) -> BrowserPageState {
        BrowserPageState(
            title: state.title,
            url: state.urlString.flatMap(URL.init(string:)),
            isLoading: state.isLoading,
            estimatedProgress: state.estimatedProgress,
            canGoBack: state.canGoBack,
            canGoForward: state.canGoForward,
            pageZoom: state.pageZoom > 0 ? state.pageZoom : 1.0
        )
    }

    private func loadURL(_ url: URL?) {
        guard let url else { return }
        page.loadURLString(url.absoluteString)
    }
}

private enum ChromiumBrowserError: Error {
    case invalidJavaScriptResult
}
#endif
