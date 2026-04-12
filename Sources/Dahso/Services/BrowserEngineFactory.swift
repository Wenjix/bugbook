import Foundation

#if DAHSO_BROWSER_CHROMIUM && canImport(ChromiumBridge)
import ChromiumBridge
#endif

enum BrowserEngineFactory {
    @MainActor
    static func makeDefault() -> any BrowserEngine {
        #if DAHSO_BROWSER_CHROMIUM && canImport(ChromiumBridge)
        return ChromiumBrowserEngine()
        #else
        return WebKitBrowserEngine()
        #endif
    }
}
