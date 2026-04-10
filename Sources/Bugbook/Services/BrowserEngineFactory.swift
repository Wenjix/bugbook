import Foundation

#if BUGBOOK_BROWSER_CHROMIUM && canImport(ChromiumBridge)
import ChromiumBridge
#endif

enum BrowserEngineFactory {
    @MainActor
    static func makeDefault() -> any BrowserEngine {
        #if BUGBOOK_BROWSER_CHROMIUM && canImport(ChromiumBridge)
        return ChromiumBrowserEngine()
        #else
        return WebKitBrowserEngine()
        #endif
    }
}
