import SwiftUI

@main
struct BugbookMobileApp: App {
    var body: some Scene {
        WindowGroup {
            MobileRootView()
                #if os(iOS)
                .preferredColorScheme(nil)
                #endif
        }
    }
}
