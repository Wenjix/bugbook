import Foundation

/// Detects whether this is a dev or release build of Bugbook.
enum AppEnvironment {
    /// True when running a development build (Xcode Debug / swift build debug).
    static var isDev: Bool {
        #if DEBUG
        return true
        #else
        // Release builds use the Bugbook bundle ID.
        // Dev/Xcode builds keep the legacy Dahso dev bundle ID for local TCC continuity.
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        return bundleID.hasSuffix(".dev")
        #endif
    }

    /// Human-readable version string, e.g. "0.408 (build 408)".
    static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (build \(build))"
    }
}
