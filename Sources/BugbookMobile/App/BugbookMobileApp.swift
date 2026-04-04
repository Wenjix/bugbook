import SwiftUI

@main
struct BugbookMobileApp: App {
    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .background(Color.mobileBgPrimary.ignoresSafeArea(.all))
        }
    }
}
