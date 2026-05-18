import Foundation

#if BUGBOOK_BROWSER_CHROMIUM && canImport(ChromiumBridge)
import ChromiumBridge
#endif

enum BrowserEngineFactory {
    static let engineEnvironmentKey = "BUGBOOK_BROWSER_ENGINE"
    static let unsafeChromiumStartEnvironmentKey = "BUGBOOK_BROWSER_UNSAFE_CHROMIUM_START"

    @MainActor
    static func makeDefault(environment: [String: String] = ProcessInfo.processInfo.environment) -> any BrowserEngine {
        #if BUGBOOK_BROWSER_CHROMIUM && canImport(ChromiumBridge)
        if requestedEngine(from: environment) == .chromium,
           allowsUnsafeChromiumStart(from: environment) {
            return ChromiumBrowserEngine()
        }
        #else
        _ = environment
        #endif
        return WebKitBrowserEngine()
    }

    static func requestedEngine(from environment: [String: String] = ProcessInfo.processInfo.environment) -> BrowserEngineKind {
        guard let rawValue = environment[engineEnvironmentKey] else { return .webKit }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "chromium", "cef":
            return .chromium
        default:
            return .webKit
        }
    }

    static func allowsUnsafeChromiumStart(from environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let rawValue = environment[unsafeChromiumStartEnvironmentKey] else { return false }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["1", "true", "yes", "on"].contains(normalized)
    }
}

enum BrowserEngineKind: Equatable {
    case webKit
    case chromium
}
