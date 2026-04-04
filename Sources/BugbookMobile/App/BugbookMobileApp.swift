import SwiftUI

@main
struct BugbookMobileApp: App {
    init() {
        #if os(iOS)
        // Set the window background so safe area edges match the app background
        // instead of defaulting to black
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.098, green: 0.098, blue: 0.098, alpha: 1)
                : UIColor(red: 0.973, green: 0.973, blue: 0.965, alpha: 1)
        }
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                #if os(iOS)
                .onAppear {
                    // Set all window backgrounds to match
                    for scene in UIApplication.shared.connectedScenes {
                        if let windowScene = scene as? UIWindowScene {
                            for window in windowScene.windows {
                                window.backgroundColor = UIColor { traits in
                                    traits.userInterfaceStyle == .dark
                                        ? UIColor(red: 0.098, green: 0.098, blue: 0.098, alpha: 1)
                                        : UIColor(red: 0.973, green: 0.973, blue: 0.965, alpha: 1)
                                }
                            }
                        }
                    }
                }
                #endif
        }
    }
}
