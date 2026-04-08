import Foundation

enum BrowserEngineFactory {
    @MainActor
    static func makeDefault() -> any BrowserEngine {
        return WebKitBrowserEngine()
    }
}
