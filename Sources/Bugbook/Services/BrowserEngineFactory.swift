import Foundation

#if BUGBOOK_BROWSER_CHROMIUM
import ChromiumBridge
#endif

enum BrowserEngineFactory {
    @MainActor
    static func makeDefault() -> any BrowserEngine {
        #if BUGBOOK_BROWSER_CHROMIUM
        return ChromiumBrowserEngine()
        #else
        return WebKitBrowserEngine()
        #endif
    }
}
