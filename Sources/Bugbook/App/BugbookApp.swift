import SwiftUI
import Sentry
import os
import UserNotifications
#if BUGBOOK_BROWSER_CHROMIUM && canImport(ChromiumBridge)
import ChromiumBridge
#endif

@main
struct BugbookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var updaterService = UpdaterService()

    var body: some Scene {
        WindowGroup {
            BugbookWindowRootView()
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

                Button("New Pane Item") {
                    NotificationCenter.default.post(name: .newPaneTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])

                Button("New Workspace") {
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

                Button("Find in Page") {
                    NotificationCenter.default.post(name: .findInPage, object: nil)
                }
                .keyboardShortcut("f")

                if BugbookFeatureGate.legacyPanesEnabled {
                    Button("Focus Address Bar") {
                        NotificationCenter.default.post(name: .browserFocusAddressBar, object: nil)
                    }
                    .keyboardShortcut("l")

                    Button("Print Page") {
                        NotificationCenter.default.post(name: .browserPrint, object: nil)
                    }
                    .keyboardShortcut("p")
                }

                Button("Previous Pane Item") {
                    NotificationCenter.default.post(name: .cyclePaneTabsBackward, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Next Pane Item") {
                    NotificationCenter.default.post(name: .cyclePaneTabsForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Reopen Closed Item") {
                    NotificationCenter.default.post(name: .reopenClosedItem, object: nil)
                }

                Button("Quick Open") {
                    NotificationCenter.default.post(name: .quickOpen, object: nil)
                }
                .keyboardShortcut("k")

                Button("Quick Open (P)") {
                    NotificationCenter.default.post(name: .quickOpen, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                if BugbookFeatureGate.legacyPanesEnabled {
                    Button("Toggle Chat Drawer") {
                        NotificationCenter.default.post(name: .openAIPanel, object: nil)
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }

                Button("Today's Note") {
                    NotificationCenter.default.post(name: .openDailyNote, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                if BugbookFeatureGate.legacyPanesEnabled {
                    Button("Graph View") {
                        NotificationCenter.default.post(name: .openGraphView, object: nil)
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])

                    Button("Mail") {
                        NotificationCenter.default.post(name: .openMail, object: nil)
                    }
                    .keyboardShortcut("m", modifiers: [.command, .shift])

                    Button("Calendar") {
                        NotificationCenter.default.post(name: .openCalendar, object: nil)
                    }
                    .keyboardShortcut("y", modifiers: [.command, .shift])

                    Button("Browser") {
                        NotificationCenter.default.post(name: .openBrowser, object: nil)
                    }
                    .keyboardShortcut("b", modifiers: [.command, .shift])

                    Button("Home") {
                        NotificationCenter.default.post(name: .openGateway, object: nil)
                    }
                    .keyboardShortcut("0", modifiers: [.command, .shift])
                }

                Button("Toggle Theme") {
                    NotificationCenter.default.post(name: .toggleTheme, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Zoom In") {
                    NotificationCenter.default.post(name: .editorZoomIn, object: nil)
                }
                .keyboardShortcut("=", modifiers: [.command, .shift])

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .editorZoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    NotificationCenter.default.post(name: .editorZoomReset, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Split Pane Right") {
                    NotificationCenter.default.post(name: .splitPaneRight, object: nil)
                }
                .keyboardShortcut("d")

                Button("Split Pane Down") {
                    NotificationCenter.default.post(name: .splitPaneDown, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .control])

                Button("Close Workspace") {
                    NotificationCenter.default.post(name: .closeWorkspace, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }

            // Block type shortcuts: Cmd+Option+0-9
            CommandGroup(after: .textFormatting) {
                Button("Text") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "paragraph")
                }
                .keyboardShortcut("0", modifiers: [.command, .option])

                Button("Heading 1") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "heading1")
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Heading 2") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "heading2")
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button("Heading 3") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "heading3")
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

                Button("To-do") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "taskItem")
                }
                .keyboardShortcut("4", modifiers: [.command, .option])

                Button("Bullet List") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "bulletListItem")
                }
                .keyboardShortcut("5", modifiers: [.command, .option])

                Button("Numbered List") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "numberedListItem")
                }
                .keyboardShortcut("6", modifiers: [.command, .option])

                Button("Toggle") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "toggle")
                }
                .keyboardShortcut("7", modifiers: [.command, .option])

                Button("Code Block") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "codeBlock")
                }
                .keyboardShortcut("8", modifiers: [.command, .option])

                Button("Page") {
                    NotificationCenter.default.post(name: .blockTypeShortcut, object: "createPage")
                }
                .keyboardShortcut("9", modifiers: [.command, .option])
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",")
            }

            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .toggleShortcutOverlay, object: nil)
                }
                .keyboardShortcut("/")
            }
        }
    }
}

private struct BugbookWindowRootView: View {
    let bootstrap: ContentViewBootstrap?

    init(bootstrap: ContentViewBootstrap? = nil) {
        self.bootstrap = bootstrap
    }

    var body: some View {
        ContentView(bootstrap: bootstrap)
            .tint(Color.fallbackAccent)
            .overlay(alignment: .topTrailing) {
                if AppEnvironment.isDev {
                    Text("DEV")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.85))
                        .clipShape(.capsule)
                        .padding(.top, 4)
                        .padding(.trailing, 72)
                        .allowsHitTesting(false)
                }
            }
    }
}

@MainActor
final class DetachedWindowManager {
    static let shared = DetachedWindowManager()

    private var windows: [UUID: NSWindow] = [:]
    private var delegates: [UUID: DetachedWindowDelegate] = [:]

    func openWindow(
        title: String,
        bootstrap: ContentViewBootstrap? = nil,
        size: CGSize = CGSize(width: 1100, height: 700)
    ) {
        let windowID = UUID()
        let contentView = BugbookWindowRootView(bootstrap: bootstrap)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(windowID.uuidString)
        configureBugbookWindowChrome(window, title: title)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: contentView)
        let delegate = DetachedWindowDelegate { [weak self] in
            self?.closeWindow(id: windowID)
        }
        window.delegate = delegate
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        windows[windowID] = window
        delegates[windowID] = delegate
    }

    private func closeWindow(id: UUID) {
        windows.removeValue(forKey: id)
        delegates.removeValue(forKey: id)
    }
}

@MainActor
private final class DetachedWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isRunningFromAppBundle {
            UNUserNotificationCenter.current().delegate = self
            if Self.shouldStartSentry {
                startSentry()
            } else {
                Log.app.info("Skipping Sentry setup because BUGBOOK_DISABLE_SENTRY is enabled")
            }
        } else {
            Log.app.info("Skipping notification center setup outside an app bundle")
            Log.app.info("Skipping Sentry setup outside an app bundle")
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Log.app.info("Bugbook launching")

        installWindowChromeObserver()
        installKeyboardMonitors()
        openProfileWindowIfNeeded()
        openDefaultWindowIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            DetachedWindowManager.shared.openWindow(title: "Bugbook")
        }
        return true
    }

    private func openProfileWindowIfNeeded() {
        guard ProcessInfo.processInfo.environment["BUGBOOK_PROFILE_AUTO_START_MEETING"] == "1" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !NSApp.windows.contains(where: \.isVisible) else { return }
            DetachedWindowManager.shared.openWindow(
                title: "Bugbook Profile",
                bootstrap: ContentViewBootstrap(workspaces: [], activeWorkspaceIndex: 0, layoutPersistenceEnabled: false)
            )
        }
    }

    private func openDefaultWindowIfNeeded() {
        guard ProcessInfo.processInfo.environment["BUGBOOK_PROFILE_AUTO_START_MEETING"] != "1" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !NSApp.windows.contains(where: \.isVisible) else { return }
            DetachedWindowManager.shared.openWindow(title: "Bugbook")
        }
    }

    private func startSentry() {
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
    }

    private static var shouldStartSentry: Bool {
        let value = ProcessInfo.processInfo.environment["BUGBOOK_DISABLE_SENTRY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return !["1", "true", "yes", "on"].contains(value ?? "")
    }

    private func installWindowChromeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        Task { @MainActor [weak self] in
            self?.configureWindows()
        }
    }

    private func installKeyboardMonitors() {
        installBlockTypeShortcutMonitor()
        installEditorZoomMonitor()
        installPaneFocusMonitor()
        installWorkspaceSwitchingMonitor()
        installPaneFocusSwitchingMonitor()
        installQuickOpenMonitor()
        installFindMonitor()
        installPaneTabCyclingMonitor()
    }

    private func installBlockTypeShortcutMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCommandOptionOnly = flags.contains([.command, .option])
                && !flags.contains(.shift)
                && !flags.contains(.control)
            guard isCommandOptionOnly else { return event }

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

            guard let action = keyCodeToAction[event.keyCode] else { return event }
            if let textView = NSApp.keyWindow?.firstResponder as? BlockNSTextView,
               let handler = textView.blockTypeShortcutAction {
                handler(action)
                return nil
            }

            NotificationCenter.default.post(name: .blockTypeShortcut, object: action)
            return nil
        }
    }

    private func installEditorZoomMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCommandOnly = flags.contains(.command)
                && !flags.contains(.option)
                && !flags.contains(.control)
            guard isCommandOnly else { return event }

            switch event.keyCode {
            case 24:
                NotificationCenter.default.post(name: .editorZoomIn, object: nil)
                return nil
            case 27 where !flags.contains(.shift):
                NotificationCenter.default.post(name: .editorZoomOut, object: nil)
                return nil
            case 29 where !flags.contains(.shift):
                NotificationCenter.default.post(name: .editorZoomReset, object: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func installPaneFocusMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains([.command, .option]),
                  !flags.contains(.shift),
                  !flags.contains(.control) else { return event }

            switch event.keyCode {
            case 123:
                NotificationCenter.default.post(name: .movePaneFocusLeft, object: nil)
                return nil
            case 124:
                NotificationCenter.default.post(name: .movePaneFocusRight, object: nil)
                return nil
            case 126:
                NotificationCenter.default.post(name: .movePaneFocusUp, object: nil)
                return nil
            case 125:
                NotificationCenter.default.post(name: .movePaneFocusDown, object: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func installWorkspaceSwitchingMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command,
                  let index = Self.digitKeyCodes[event.keyCode] else { return event }
            NotificationCenter.default.post(name: .switchWorkspace, object: index)
            return nil
        }
    }

    private func installPaneFocusSwitchingMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.command, .shift],
                  let index = Self.digitKeyCodes[event.keyCode] else { return event }
            NotificationCenter.default.post(name: .focusPaneByIndex, object: index)
            return nil
        }
    }

    private func installQuickOpenMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, event.charactersIgnoringModifiers == "k" else { return event }
            NotificationCenter.default.post(name: .quickOpen, object: nil)
            return nil
        }
    }

    private func installFindMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, event.charactersIgnoringModifiers == "f" else { return event }
            NotificationCenter.default.post(name: .findInPage, object: nil)
            return nil
        }
    }

    private func installPaneTabCyclingMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.control),
                  !flags.contains(.command),
                  !flags.contains(.option),
                  event.keyCode == 48 else { return event }

            if flags.contains(.shift) {
                NotificationCenter.default.post(name: .cyclePaneTabsBackward, object: nil)
            } else {
                NotificationCenter.default.post(name: .cyclePaneTabsForward, object: nil)
            }
            return nil
        }
    }

    private static let digitKeyCodes: [UInt16: Int] = [
        18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8
    ]

    @MainActor
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        configureWindows()
    }

    @MainActor
    private func configureWindows() {
        for window in NSApplication.shared.windows {
            configureBugbookWindowChrome(window)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handle notification action buttons.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let eventId = userInfo["eventId"] as? String ?? ""
        let eventTitle = userInfo["eventTitle"] as? String ?? "Meeting"

        switch response.actionIdentifier {
        case MeetingNotificationService.recordActionIdentifier:
            NotificationCenter.default.post(
                name: .meetingNotificationRecord,
                object: nil,
                userInfo: ["eventId": eventId, "eventTitle": eventTitle]
            )
        case MeetingNotificationService.openNotesActionIdentifier,
             UNNotificationDefaultActionIdentifier:
            NotificationCenter.default.post(
                name: .meetingNotificationOpenNotes,
                object: nil,
                userInfo: ["eventId": eventId, "eventTitle": eventTitle]
            )
        default:
            break
        }

        completionHandler()
    }
}

@MainActor
private func configureBugbookWindowChrome(_ window: NSWindow, title: String = "Bugbook") {
    guard !(window is NSPanel) else { return }
    window.title = title
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.styleMask.insert(.fullSizeContentView)
    window.toolbarStyle = .unifiedCompact
    window.isMovableByWindowBackground = false
    window.backgroundColor = NSColor(Container.groutBg)
}

extension Notification.Name {
    static let newNote = Notification.Name("newNote")
    static let newPaneTab = Notification.Name("newPaneTab")
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
    static let openMail = Notification.Name("openMail")
    static let editorZoomIn = Notification.Name("editorZoomIn")
    static let editorZoomOut = Notification.Name("editorZoomOut")
    static let editorZoomReset = Notification.Name("editorZoomReset")
    static let openCalendar = Notification.Name("openCalendar")
    static let openMeetings = Notification.Name("openMeetings")
    static let openGateway = Notification.Name("openGateway")
    static let openTerminal = Notification.Name("openTerminal")
    static let openBrowser = Notification.Name("openBrowser")
    static let toggleShortcutOverlay = Notification.Name("toggleShortcutOverlay")
    static let fileDeleted = Notification.Name("fileDeleted")
    static let fileMoved = Notification.Name("fileMoved")
    static let movePage = Notification.Name("movePage")
    static let movePageToDir = Notification.Name("movePageToDir")
    static let addToSidebar = Notification.Name("addToSidebar")

    static let stopMeetingRecording = Notification.Name("stopMeetingRecording")
    static let meetingNotificationRecord = Notification.Name("meetingNotificationRecord")
    static let meetingNotificationOpenNotes = Notification.Name("meetingNotificationOpenNotes")
    static let findInPage = Notification.Name("findInPage")
    static let findInPane = Notification.Name("findInPane")

    // Pane/Workspace system
    static let splitPaneRight = Notification.Name("splitPaneRight")
    static let splitPaneDown = Notification.Name("splitPaneDown")
    static let closeWorkspace = Notification.Name("closeWorkspace")
    static let movePaneFocusLeft = Notification.Name("movePaneFocusLeft")
    static let movePaneFocusRight = Notification.Name("movePaneFocusRight")
    static let movePaneFocusUp = Notification.Name("movePaneFocusUp")
    static let movePaneFocusDown = Notification.Name("movePaneFocusDown")
    static let switchWorkspace = Notification.Name("switchWorkspace")
    static let focusPaneByIndex = Notification.Name("focusPaneByIndex")
    static let cyclePaneTabsForward = Notification.Name("cyclePaneTabsForward")
    static let cyclePaneTabsBackward = Notification.Name("cyclePaneTabsBackward")
    static let reopenClosedItem = Notification.Name("reopenClosedItem")

    static let browserFocusAddressBar = Notification.Name("browserFocusAddressBar")
    static let browserNewTab = Notification.Name("browserNewTab")
    static let browserCloseTab = Notification.Name("browserCloseTab")
    static let browserBack = Notification.Name("browserBack")
    static let browserForward = Notification.Name("browserForward")
    static let browserFind = Notification.Name("browserFind")
    static let browserPrint = Notification.Name("browserPrint")
    static let browserSavePage = Notification.Name("browserSavePage")
    static let browserZoomIn = Notification.Name("browserZoomIn")
    static let browserZoomOut = Notification.Name("browserZoomOut")
    static let browserZoomReset = Notification.Name("browserZoomReset")
    static let browserOpenCleanup = Notification.Name("browserOpenCleanup")
}
