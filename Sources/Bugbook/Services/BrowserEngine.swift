import AppKit
import Foundation

struct BrowserPageState {
    /// Default zoom level for browser panes — slightly reduced from 1.0 so content
    /// renders at a natural scale in the split-pane context.
    static let defaultPageZoom: Double = 0.85

    var title: String?
    var url: URL?
    var isLoading: Bool
    var estimatedProgress: Double
    var canGoBack: Bool
    var canGoForward: Bool
    var pageZoom: Double

    static let empty = BrowserPageState(
        title: nil,
        url: nil,
        isLoading: false,
        estimatedProgress: 0,
        canGoBack: false,
        canGoForward: false,
        pageZoom: defaultPageZoom
    )
}

enum BrowserPageEvent {
    case stateChanged(BrowserPageState)
    case hoverURLChanged(String?)
    case didFinishNavigation(title: String, url: URL)
    case openInNewTab(URL)
    case downloadStatusChanged(String)
}

typealias BrowserPageEventHandler = @MainActor (BrowserPageEvent) -> Void

@MainActor
protocol BrowserEngine: AnyObject {
    func makePage(
        for paneID: UUID,
        tabID: UUID,
        initialURL: URL?,
        eventHandler: @escaping BrowserPageEventHandler
    ) -> any BrowserPage
    func clearCookies() async throws
}

@MainActor
protocol BrowserPage: AnyObject {
    var hostView: NSView { get }
    var state: BrowserPageState { get }

    func load(_ request: URLRequest)
    func goBack()
    func goForward()
    func reload()
    func stopLoading()
    func setPageZoom(_ zoom: Double)
    func printPage()
    func find(_ query: String, forward: Bool)
    func evaluateJavaScript(_ script: String) async throws -> String
    func dispose()
}
