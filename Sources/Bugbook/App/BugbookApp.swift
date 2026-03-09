import SwiftUI
import Sentry
import os

@main
struct BugbookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var updaterService = UpdaterService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color.fallbackAccent)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterService.checkForUpdates()
                }
                .disabled(!updaterService.canCheckForUpdates)
            }

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

                Divider()

                Button("Back") {
                    NotificationCenter.default.post(name: .navigateBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Forward") {
                    NotificationCenter.default.post(name: .navigateForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Quick Open") {
                    NotificationCenter.default.post(name: .quickOpen, object: nil)
                }
                .keyboardShortcut("k")

                Button("Quick Open (P)") {
                    NotificationCenter.default.post(name: .quickOpen, object: nil)
                }
                .keyboardShortcut("p")

                Button("Ask AI") {
                    NotificationCenter.default.post(name: .openAIPanel, object: nil)
                }
                .keyboardShortcut("i")

                Button("Today's Note") {
                    NotificationCenter.default.post(name: .openDailyNote, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Graph View") {
                    NotificationCenter.default.post(name: .openGraphView, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Toggle Theme") {
                    NotificationCenter.default.post(name: .toggleTheme, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            // Block type shortcuts: Cmd+Shift+0-9
            // Use shifted chars (!, @, #...) with .command — workaround for SwiftUI shift+number bug
            CommandGroup(after: .textFormatting) {
                Button("Text") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "paragraph")
                }
                .keyboardShortcut(")", modifiers: .command) // Shift+0

                Button("Heading 1") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "heading1")
                }
                .keyboardShortcut("!", modifiers: .command) // Shift+1

                Button("Heading 2") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "heading2")
                }
                .keyboardShortcut("@", modifiers: .command) // Shift+2

                Button("Heading 3") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "heading3")
                }
                .keyboardShortcut("#", modifiers: .command) // Shift+3

                Button("To-do") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "taskItem")
                }
                .keyboardShortcut("$", modifiers: .command) // Shift+4

                Button("Bullet List") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "bulletListItem")
                }
                .keyboardShortcut("%", modifiers: .command) // Shift+5

                Button("Numbered List") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "numberedListItem")
                }
                .keyboardShortcut("^", modifiers: .command) // Shift+6

                Button("Toggle") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "toggle")
                }
                .keyboardShortcut("&", modifiers: .command) // Shift+7

                Button("Code Block") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "codeBlock")
                }
                .keyboardShortcut("*", modifiers: .command) // Shift+8

                Button("Page") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "createPage")
                }
                .keyboardShortcut("(", modifiers: .command) // Shift+9
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
        Log.app.info("Bugbook launching")

        SentrySDK.start { options in
            options.dsn = "https://a534c38e8813ac89c36946aa4b426e3f@o4510963078856704.ingest.us.sentry.io/4510963091177472"
#if DEBUG
            options.debug = true
#else
            options.debug = false
#endif
            // Avoid collecting personal data by default.
            options.sendDefaultPii = false
            options.enableMetricKit = true
        }

        // Observe new windows to configure their title bars
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        // Configure any existing windows
        DispatchQueue.main.async { self.configureWindows() }

        // Cmd+Shift+0-9 block type shortcuts via local event monitor
        // (SwiftUI .keyboardShortcut is unreliable for shifted number combos)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCommandShiftOnly = flags.contains([.command, .shift])
                && !flags.contains(.option)
                && !flags.contains(.control)
            guard isCommandShiftOnly else { return event }

            let keyToAction: [String: String] = [
                "0": "paragraph",
                "1": "heading1",
                "2": "heading2",
                "3": "heading3",
                "4": "taskItem",
                "5": "bulletListItem",
                "6": "numberedListItem",
                "7": "toggle",
                "8": "codeBlock",
                "9": "createPage",
            ]
            if let chars = event.charactersIgnoringModifiers?.lowercased(),
               let action = keyToAction[chars] {
                NotificationCenter.default.post(name: .blockTypeShortcut, object: action)
                return nil
            }

            let keyCodeToAction: [UInt16: String] = [
                29: "paragraph",        // 0
                18: "heading1",         // 1
                19: "heading2",         // 2
                20: "heading3",         // 3
                21: "taskItem",         // 4
                23: "bulletListItem",   // 5
                22: "numberedListItem", // 6
                26: "toggle",           // 7
                28: "codeBlock",        // 8
                25: "createPage",       // 9
            ]

            if let action = keyCodeToAction[event.keyCode] {
                NotificationCenter.default.post(name: .blockTypeShortcut, object: action)
                return nil
            }
            return event
        }
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
    static let blockTypeShortcut = Notification.Name("blockTypeShortcut")
    static let navigateBack = Notification.Name("navigateBack")
    static let navigateForward = Notification.Name("navigateForward")
    static let openDailyNote = Notification.Name("openDailyNote")
    static let openGraphView = Notification.Name("openGraphView")
    static let newCanvas = Notification.Name("newCanvas")
    static let fileDeleted = Notification.Name("fileDeleted")
    static let fileMoved = Notification.Name("fileMoved")
    static let movePage = Notification.Name("movePage")
    static let movePageToDir = Notification.Name("movePageToDir")
}
