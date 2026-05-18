import AppKit
import Foundation
import WebKit

@MainActor
final class WebKitBrowserEngine: BrowserEngine {
    private let websiteDataStore = WKWebsiteDataStore.default()
    private var popupWindows: [UUID: WebKitBrowserPopupWindowController] = [:]

    func makePage(
        for paneID: UUID,
        tabID: UUID,
        initialURL: URL?,
        eventHandler: @escaping BrowserPageEventHandler
    ) -> any BrowserPage {
        WebKitBrowserPage(
            websiteDataStore: websiteDataStore,
            initialURL: initialURL,
            eventHandler: eventHandler,
            popupPresenter: { [weak self] configuration in
                self?.presentPopup(using: configuration)
            }
        )
    }

    func configureExtensions(_ extensionPaths: [String]) {
        _ = extensionPaths
    }

    func clearCookies() async throws {
        let cookieDataTypes: Set<String> = [WKWebsiteDataTypeCookies]
        let records = await websiteDataStore.dataRecords(ofTypes: cookieDataTypes)
        guard !records.isEmpty else { return }
        await websiteDataStore.removeData(ofTypes: cookieDataTypes, for: records)
    }

    private func presentPopup(using configuration: WKWebViewConfiguration) -> WKWebView {
        let popupID = UUID()
        let controller = WebKitBrowserPopupWindowController(
            configuration: configuration,
            onClose: { [weak self] in
                self?.popupWindows.removeValue(forKey: popupID)
            },
            popupPresenter: { [weak self] nestedConfiguration in
                self?.presentPopup(using: nestedConfiguration)
            }
        )
        popupWindows[popupID] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return controller.webView
    }
}

@MainActor
private final class WebKitBrowserPage: NSObject, BrowserPage {
    let webView: WKWebView
    private let eventHandler: BrowserPageEventHandler
    private let popupPresenter: (WKWebViewConfiguration) -> WKWebView?
    private lazy var coordinator = WebKitBrowserPageCoordinator(page: self)
    private lazy var downloadDelegate = WebKitBrowserDownloadDelegate(page: self)

    init(
        websiteDataStore: WKWebsiteDataStore,
        initialURL: URL?,
        eventHandler: @escaping BrowserPageEventHandler,
        popupPresenter: @escaping (WKWebViewConfiguration) -> WKWebView?
    ) {
        self.eventHandler = eventHandler
        self.popupPresenter = popupPresenter

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

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

    fileprivate func presentPopup(configuration: WKWebViewConfiguration) -> WKWebView? {
        popupPresenter(configuration)
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
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let shouldPresentPopupWindow =
            navigationAction.navigationType != .linkActivated
            || windowFeatures.width != nil
            || windowFeatures.height != nil

        if shouldPresentPopupWindow,
           let popupWebView = page?.presentPopup(configuration: configuration) {
            return popupWebView
        }

        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url {
            page?.emitOpenInNewTab(url)
        }
        return nil
    }
}

@MainActor
private final class WebKitBrowserPopupWindowController: NSWindowController {
    let webView: WKWebView
    private let onClose: () -> Void
    private lazy var coordinator = WebKitPopupCoordinator(
        webView: webView,
        onClose: onClose,
        popupPresenter: popupPresenter
    )
    private let popupPresenter: (WKWebViewConfiguration) -> WKWebView?

    init(
        configuration: WKWebViewConfiguration,
        onClose: @escaping () -> Void,
        popupPresenter: @escaping (WKWebViewConfiguration) -> WKWebView?
    ) {
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.onClose = onClose
        self.popupPresenter = popupPresenter

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false

        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.autoresizingMask = [.width, .height]
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *), AppEnvironment.isDev {
            webView.isInspectable = true
        }
        container.addSubview(webView)
        window.contentView = container

        super.init(window: window)

        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinator.attach()
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [onClose] _ in
            onClose()
        }
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class WebKitPopupCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private weak var webView: WKWebView?
    private let onClose: () -> Void
    private let popupPresenter: (WKWebViewConfiguration) -> WKWebView?
    private var observations: [NSKeyValueObservation] = []
    private let downloadDelegate = WebKitPopupDownloadDelegate()

    init(
        webView: WKWebView,
        onClose: @escaping () -> Void,
        popupPresenter: @escaping (WKWebViewConfiguration) -> WKWebView?
    ) {
        self.webView = webView
        self.onClose = onClose
        self.popupPresenter = popupPresenter
    }

    func attach() {
        guard let webView else { return }
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { webView, _ in
                webView.window?.title = webView.title ?? "Browser"
                if let host = webView.url?.host, webView.window?.title == "Browser" {
                    webView.window?.title = host
                }
            }
        ]
    }

    func webViewDidClose(_ webView: WKWebView) {
        webView.window?.close()
        onClose()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let shouldPresentPopupWindow =
            navigationAction.navigationType != .linkActivated
            || windowFeatures.width != nil
            || windowFeatures.height != nil
        guard shouldPresentPopupWindow else { return nil }
        return popupPresenter(configuration)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = downloadDelegate
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = downloadDelegate
    }
}

@MainActor
private final class WebKitPopupDownloadDelegate: NSObject, WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        completionHandler(directory.appendingPathComponent(suggestedFilename))
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
