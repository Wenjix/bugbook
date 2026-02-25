import SwiftUI

@main
struct BugbookSwiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .newNote, object: nil)
                }
                .keyboardShortcut("n")

                Button("New Tab") {
                    NotificationCenter.default.post(name: .quickOpenNewTab, object: nil)
                }
                .keyboardShortcut("t")

                Divider()

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeTab, object: nil)
                }
                .keyboardShortcut("w")
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveFile, object: nil)
                }
                .keyboardShortcut("s")
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)

                Button("Quick Open") {
                    NotificationCenter.default.post(name: .quickOpen, object: nil)
                }
                .keyboardShortcut("k")

                Button("Ask AI") {
                    NotificationCenter.default.post(name: .openAIPanel, object: nil)
                }
                .keyboardShortcut("i")
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",")
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Observe new windows to configure their title bars
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        // Configure any existing windows
        DispatchQueue.main.async { self.configureWindows() }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        configureWindows()
    }

    private func configureWindows() {
        for window in NSApplication.shared.windows {
            guard !window.titlebarAppearsTransparent else { continue }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Notification.Name {
    static let newNote = Notification.Name("newNote")
    static let newTab = Notification.Name("newTab")
    static let closeTab = Notification.Name("closeTab")
    static let saveFile = Notification.Name("saveFile")
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let quickOpen = Notification.Name("quickOpen")
    static let quickOpenNewTab = Notification.Name("quickOpenNewTab")
    static let openSettings = Notification.Name("openSettings")
    static let openAIPanel = Notification.Name("openAIPanel")
    static let askAI = Notification.Name("askAI")
    static let toggleTheme = Notification.Name("toggleTheme")
    static let newDatabase = Notification.Name("newDatabase")
}
