import AppKit
import Observation
import SwiftUI

struct BrowserPaneView: View {
    let leaf: PaneNode.Leaf
    let paneID: UUID
    @Bindable var session: BrowserPaneSession
    @Bindable var appState: AppState
    let fileTree: [FileEntry]
    let isSinglePane: Bool
    let browserManager: BrowserManager
    let workspaceManager: WorkspaceManager
    let fileSystem: FileSystemService
    let aiService: AiService
    let onOpenBugbookEntry: (FileEntry) -> Void

    @FocusState private var omnibarFocused: Bool
    @FocusState private var newTabSearchFocused: Bool
    @FocusState private var findFocused: Bool
    @State private var omnibarText = ""
    @State private var newTabSearchText = ""
    @State private var showFindBar = false
    @State private var findQuery = ""
    @State private var showCleanupSheet = false
    @State private var cleanupProposals: [BrowserCleanupProposal] = []
    @State private var isApplyingCleanup = false
    @State private var saveMessage: String?
    @State private var searchableEntries: [BrowserSearchableEntry] = []
    @State private var savedRecords: [SavedWebPageRecord] = []
    @State private var omnibarSuggestions: [BrowserSuggestionItem] = []
    @State private var newTabSuggestions: [BrowserSuggestionItem] = []

    private let agentService = BrowserAgentService()
    private let savedPageStore = SavedWebPageStore()
    private let relativeDateFormatter = RelativeDateTimeFormatter()

    private var browserTabs: [BrowserTabState] {
        browserManager.tabs(in: paneID)
    }

    private var activeTab: BrowserTabState? {
        browserManager.activeTab(in: paneID)
    }

    private var activeSavedRecord: SavedWebPageRecord? {
        guard let activeTab else { return nil }
        if let recordID = activeTab.savedRecordID {
            return savedRecords.first(where: { $0.id == recordID })
        }
        if !activeTab.urlString.isEmpty {
            return savedRecords.first(where: { $0.urlString == activeTab.urlString })
        }
        return nil
    }

    private var chrome: BrowserChromeConfiguration {
        appState.settings.browserChrome
    }

    private var readLaterRecords: [SavedWebPageRecord] {
        savedRecords.filter { $0.status == .unread }
    }

    private var recentHistory: [BrowserRecentVisit] {
        guard appState.settings.browserHistoryEnabled else { return [] }
        return browserManager.browsingHistory
    }

    private var selectedTabID: UUID? {
        guard let file = leaf.activeOpenFile, file.isBrowser else { return nil }
        return file.id
    }

    var body: some View {
        applyBrowserNotifications(
            to: applyBrowserLifecycle(to: browserSurface)
        )
    }

    private var browserSurface: some View {
        VStack(spacing: 0) {
            chromeBar

            if showFindBar {
                browserFindBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            progressBar

            HStack(spacing: 0) {
                browserContent

                if isSinglePane && session.isReadLaterDrawerOpen {
                    Divider()
                    readLaterDrawer
                        .frame(width: 280)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            if chrome.showsStatusBar, let hoverURL = activeTab?.hoverURLString, !hoverURL.isEmpty {
                Divider()
                HStack {
                    Text(hoverURL)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.fallbackTabBarBg)
            }
        }
        .background(Color.fallbackEditorBg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-pane")
    }

    private func applyBrowserLifecycle<V: View>(to view: V) -> some View {
        view
        .onAppear {
            refreshSavedRecords()
            refreshSearchableEntries()
            refreshSelectedTabDisplay(force: true)
            refreshSuggestions()
            if let selectedTabID {
                browserManager.cancelInactivePageDiscard(for: selectedTabID, in: paneID)
            }
            DispatchQueue.main.async {
                if activeTab?.urlString.isEmpty != false {
                    newTabSearchFocused = true
                } else {
                    omnibarFocused = true
                }
            }
        }
        .onChange(of: leaf.activeTabID) { oldValue, newValue in
            if oldValue != newValue {
                browserManager.scheduleInactivePageDiscard(for: oldValue, in: paneID)
                browserManager.cancelInactivePageDiscard(for: newValue, in: paneID)
            }
            refreshSelectedTabDisplay(force: true)
            refreshSuggestions()
        }
        .onDisappear {
            if let selectedTabID {
                browserManager.scheduleInactivePageDiscard(for: selectedTabID, in: paneID)
            }
        }
        .onChange(of: leaf.tabs) { _, _ in
            syncDisplayedText()
        }
        .onChange(of: fileTree) { _, _ in
            refreshSearchableEntries()
            refreshSuggestions()
        }
        .onChange(of: appState.workspacePath) { _, _ in
            refreshSavedRecords()
        }
        .onChange(of: appState.settings.browserSuggestionsEnabled) { _, _ in
            refreshSuggestions()
        }
        .onChange(of: appState.settings.browserSuggestsBugbookPages) { _, _ in
            refreshSuggestions()
        }
        .onChange(of: appState.settings.browserSuggestionLimit) { _, _ in
            refreshSuggestions()
        }
        .onChange(of: appState.settings.browserSearchEngine) { _, _ in
            refreshSuggestions()
        }
        .onChange(of: appState.settings.browserQuickLaunchItems) { _, _ in
            refreshSuggestions()
        }
        .onChange(of: appState.settings.browserHistoryEnabled) { _, _ in
            refreshSuggestions()
        }
        .onChange(of: browserManager.browsingHistory) { _, _ in
            refreshSuggestions()
        }
        .onChange(of: omnibarText) { _, _ in
            omnibarSuggestions = suggestions(for: omnibarText)
        }
        .onChange(of: newTabSearchText) { _, _ in
            newTabSuggestions = suggestions(for: newTabSearchText)
        }
    }

    private func applyBrowserNotifications<V: View>(to view: V) -> some View {
        view
        .onReceive(NotificationCenter.default.publisher(for: .browserFocusAddressBar)) { notification in
            guard shouldHandleBrowserCommand(notification) else { return }
            newTabSearchFocused = false
            omnibarFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserNewTab)) { notification in
            guard shouldHandleBrowserCommand(notification) else { return }
            createNewTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserCloseTab)) { notification in
            guard shouldHandleBrowserCommand(notification),
                  let selected = selectedTabID else { return }
            session.closeTab(selected)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserBack)) { notification in
            guard shouldHandleBrowserCommand(notification) else { return }
            browserManager.goBack(in: paneID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserForward)) { notification in
            guard shouldHandleBrowserCommand(notification) else { return }
            browserManager.goForward(in: paneID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserFind)) { notification in
            guard shouldHandleBrowserCommand(notification) else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                showFindBar = true
            }
            findFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserPrint)) { notification in
            guard shouldHandleBrowserCommand(notification) else { return }
            browserManager.printActiveTab(in: paneID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserSavePage)) { notification in
            guard shouldHandleBrowserCommand(notification) else { return }
            Task { await saveCurrentTab() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserZoomIn)) { notification in
            guard shouldHandleBrowserCommand(notification) else { return }
            adjustZoom(by: 0.1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserZoomOut)) { notification in
            guard shouldHandleBrowserCommand(notification) else { return }
            adjustZoom(by: -0.1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserZoomReset)) { notification in
            guard shouldHandleBrowserCommand(notification) else { return }
            browserManager.setPageZoom(BrowserPageState.defaultPageZoom, in: paneID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserOpenCleanup)) { notification in
            guard let targetPaneID = notification.object as? UUID,
                  targetPaneID == paneID else { return }
            prepareCleanup()
        }
        .sheet(isPresented: $showCleanupSheet) {
            cleanupSheet
        }
    }

    private var isFocusedPane: Bool {
        workspaceManager.activeWorkspace?.focusedPaneId == paneID
    }

    private func shouldHandleBrowserCommand(_ notification: Notification) -> Bool {
        if let targetPaneID = notification.object as? UUID {
            return targetPaneID == paneID
        }
        return isFocusedPane
    }

    private func refreshSelectedTabDisplay(force: Bool = false) {
        syncDisplayedText(force: force)
        guard let tabID = selectedTabID,
              let activeTab,
              isRenderableBrowserURL(activeTab.urlString) else { return }
        _ = browserManager.ensurePage(for: paneID, tabID: tabID)
    }

    private func isRenderableBrowserURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "bugbook://browser"
    }

    private var chromeBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if chrome.showsBackForwardButtons {
                    navButton("chevron.left", enabled: activeTab?.canGoBack == true) {
                        browserManager.goBack(in: paneID)
                    }
                    navButton("chevron.right", enabled: activeTab?.canGoForward == true) {
                        browserManager.goForward(in: paneID)
                    }
                }

                // Full-width URL bar
                HStack(spacing: 8) {
                    Image(systemName: activeTab?.securityIconName ?? "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Search or enter URL", text: $omnibarText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .accessibilityIdentifier("browser-omnibar")
                        .focused($omnibarFocused)
                        .onSubmit {
                            submitOmnibar(omnibarText)
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(Container.urlBarBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(omnibarFocused ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                )

                if chrome.showsSaveButton {
                    Button {
                        Task { await saveCurrentTab() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(activeTab?.urlString.isEmpty ?? true)
                }

                browserActionMenu
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if omnibarFocused && !omnibarSuggestions.isEmpty {
                suggestionsList(omnibarSuggestions)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }

            if chrome.showsBookmarksBar && !appState.settings.browserQuickLaunchItems.isEmpty {
                bookmarksBar
            }

            if let saveMessage, !saveMessage.isEmpty {
                HStack {
                    Text(saveMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .background(Container.cardBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private var browserFindBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Find on page", text: $findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($findFocused)
                .onSubmit {
                    browserManager.find(findQuery, in: paneID)
                }
                .onChange(of: findQuery) { _, value in
                    guard !value.isEmpty else { return }
                    browserManager.find(value, in: paneID)
                }

            Button {
                browserManager.find(findQuery, in: paneID, forward: false)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(findQuery.isEmpty)

            Button {
                browserManager.find(findQuery, in: paneID, forward: true)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(findQuery.isEmpty)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showFindBar = false
                }
                findQuery = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.fallbackTabBarBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.fallbackChromeBorder)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if let activeTab, activeTab.isLoading {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.clear)
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: max(geometry.size.width * max(activeTab.estimatedProgress, 0.08), 24))
                }
            }
            .frame(height: 2)
        }
    }

    private var bookmarksBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.settings.browserQuickLaunchItems) { item in
                    Button {
                        openQuickLaunch(item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon.isEmpty ? "globe" : item.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(item.title)
                                .font(.system(size: 12))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func suggestionsList(_ suggestions: [BrowserSuggestionItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    applySuggestion(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.iconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)

                if index < suggestions.count - 1 {
                    Divider()
                        .padding(.leading, 38)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Container.cardBg)
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var browserActionMenu: some View {
        Menu {
            saveSection

            if isSinglePane {
                Button(session.isReadLaterDrawerOpen ? "Hide View Later Queue" : "Show View Later Queue") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        session.toggleReadLaterDrawer()
                    }
                }
            }

            if !readLaterRecords.isEmpty {
                Menu("View Later Queue") {
                    ForEach(readLaterRecords.prefix(10)) { record in
                        Button(record.title) {
                            if let url = record.url {
                                browserManager.openURL(url, in: paneID, newTab: true)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("New Browser Page") {
                createNewTab()
            }
            Button("Clean Browser Pages") {
                prepareCleanup()
            }
            Button(activeTab?.isLoading == true ? "Stop Loading" : "Reload") {
                if activeTab?.isLoading == true {
                    browserManager.stopLoading(in: paneID)
                } else {
                    browserManager.reload(in: paneID)
                }
            }
            Button("Open in External Browser") {
                openInExternalBrowser()
            }
            Button("Print") {
                browserManager.printActiveTab(in: paneID)
            }
            Button(showFindBar ? "Hide Find Bar" : "Find on Page") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showFindBar.toggle()
                }
                if showFindBar {
                    findFocused = true
                }
            }
            Menu("Zoom") {
                Button("Zoom In") {
                    adjustZoom(by: 0.1)
                }
                Button("Zoom Out") {
                    adjustZoom(by: -0.1)
                }
                Button("Actual Size") {
                    browserManager.setPageZoom(BrowserPageState.defaultPageZoom, in: paneID)
                }
            }
            Menu("Quick Pane Switching") {
                Button("Mail") {
                    NotificationCenter.default.post(name: .openMail, object: nil)
                }
                Button("Calendar") {
                    NotificationCenter.default.post(name: .openCalendar, object: nil)
                }
                Button("Terminal") {
                    NotificationCenter.default.post(name: .openTerminal, object: nil)
                }
            }
            if AppEnvironment.isDev {
                Button("View Source") {
                    openViewSource()
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var saveSection: some View {
        if let savedRecord = activeSavedRecord {
            Text(savedRecord.status == .read
                 ? "Saved to \((savedRecord.folderPath as NSString).lastPathComponent)/"
                 : "Saved to view later")
            Button("Open Saved Note") {
                openSavedNote(savedRecord)
            }
            Button(savedRecord.status == .read ? "Mark Read Later" : "Mark Read") {
                toggleSavedStatus(savedRecord)
            }
            Button("Unsave") {
                unsave(savedRecord)
            }
        } else {
            Button("Save to Bugbook") {
                Task { await saveCurrentTab() }
            }
            .disabled(activeTab?.urlString.isEmpty ?? true)
        }
    }

    @ViewBuilder
    private var browserContent: some View {
        if let activeTab, isRenderableBrowserURL(activeTab.urlString) {
            if let hostView = browserManager.activeHostView(for: paneID) {
                BrowserHostViewContainer(hostView: hostView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.fallbackEditorBg
                    .onAppear {
                        _ = browserManager.ensurePage(for: paneID, tabID: activeTab.id)
                }
            }
        } else {
            newTabPage
        }
    }

    private var newTabPage: some View {
        VStack(spacing: 24) {
            Spacer()

            if chrome.showsNewTabGreeting {
                VStack(spacing: 4) {
                    Text(greetingTitle)
                        .font(.system(size: 28, weight: .semibold))
                    Text("Search the web or your notes from one place.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Search the web or your notes...", text: $newTabSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .accessibilityIdentifier("browser-new-tab-search")
                .focused($newTabSearchFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: 520)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(Color.primary.opacity(0.05))
                )
                .onSubmit {
                    submitOmnibar(newTabSearchText)
                }

            if newTabSearchFocused && !newTabSuggestions.isEmpty {
                suggestionsList(newTabSuggestions)
                    .frame(maxWidth: 520)
            }

            if chrome.showsNewTabQuickLaunch, !appState.settings.browserQuickLaunchItems.isEmpty {
                FlowLayout(spacing: 10) {
                    ForEach(appState.settings.browserQuickLaunchItems) { item in
                        Button {
                            openQuickLaunch(item)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.icon.isEmpty ? "globe" : item.icon)
                                    .font(.system(size: 12, weight: .medium))
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 620)
            }

            if chrome.showsNewTabRecentVisits, !recentHistory.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(recentHistory.prefix(8)) { visit in
                            Button {
                                if let url = visit.url {
                                    browserManager.openURL(url, in: paneID, newTab: false)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(tabColorSeed(visit.host))
                                        .frame(width: 10, height: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(visit.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text("\(visit.host) · \(relativeDateFormatter.localizedString(for: visit.visitedAt, relativeTo: .now))")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(Color.primary.opacity(0.03))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readLaterDrawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Read Later")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        session.toggleReadLaterDrawer()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(readLaterRecords) { record in
                        Button {
                            if let url = record.url {
                                browserManager.openURL(url, in: paneID, newTab: true)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(record.status == .unread ? Color.orange : Color.teal)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text("\(record.host) · \(relativeDateFormatter.localizedString(for: record.savedAt, relativeTo: .now))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.fallbackEditorBg)
    }

    private var cleanupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clean Browser Pages")
                .font(.system(size: 18, weight: .semibold))

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($cleanupProposals) { $proposal in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(proposal.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(proposal.urlString)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(proposal.reason)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Picker("Decision", selection: $proposal.decision) {
                                Text("Keep").tag(BrowserCleanupDecision.keep)
                                Text("Save").tag(BrowserCleanupDecision.save)
                                Text("Read Later").tag(BrowserCleanupDecision.readLater)
                                Text("Close").tag(BrowserCleanupDecision.close)
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    showCleanupSheet = false
                }
                Spacer()
                Button(isApplyingCleanup ? "Applying…" : "Apply All") {
                    Task { await applyCleanup() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplyingCleanup)
            }
        }
        .padding(24)
        .frame(width: 720, height: 520)
    }

    private func navButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func createNewTab() {
        workspaceManager.setFocusedPane(id: paneID)
        let content = PaneContent.browserDocument(urlString: "bugbook://browser", title: "Browser")
        _ = workspaceManager.addPaneTab(to: paneID, content: content)
        _ = browserManager.ensurePage(for: paneID, tabID: content.id)
        newTabSearchText = ""
        omnibarText = ""
        omnibarSuggestions = []
        newTabSuggestions = []
        newTabSearchFocused = true
        omnibarFocused = false
    }

    private func syncDisplayedText(force: Bool = false) {
        if force || !omnibarFocused {
            omnibarText = activeTab?.displayURL ?? ""
        }
        if (force || !newTabSearchFocused), activeTab?.urlString.isEmpty != false {
            newTabSearchText = ""
        }
    }

    private func refreshSavedRecords() {
        guard let workspacePath = appState.workspacePath else {
            savedRecords = []
            return
        }
        savedRecords = savedPageStore.records(in: workspacePath)
    }

    private func refreshSearchableEntries() {
        searchableEntries = makeSearchableEntries(from: fileTree)
    }

    private func refreshSuggestions() {
        omnibarSuggestions = suggestions(for: omnibarText)
        newTabSuggestions = suggestions(for: newTabSearchText)
    }

    private func suggestions(for input: String) -> [BrowserSuggestionItem] {
        guard appState.settings.browserSuggestionsEnabled else { return [] }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let normalized = trimmed.lowercased()
        let limit = appState.settings.browserSuggestionLimit
        var suggestions: [BrowserSuggestionItem] = []
        var seenIDs = Set<String>()

        func append(_ suggestion: BrowserSuggestionItem) {
            guard seenIDs.insert(suggestion.id).inserted else { return }
            suggestions.append(suggestion)
        }

        if appState.settings.browserHistoryEnabled {
            for visit in recentHistory where suggestions.count < limit {
                let haystack = [visit.title, visit.urlString, visit.host].joined(separator: " ").lowercased()
                guard haystack.contains(normalized) else { continue }
                append(
                    BrowserSuggestionItem(
                        id: "history:\(visit.urlString)",
                        title: visit.title,
                        subtitle: visit.urlString,
                        iconName: "clock.arrow.circlepath",
                        destination: .url(URL(string: visit.urlString))
                    )
                )
            }
        }

        for item in appState.settings.browserQuickLaunchItems where suggestions.count < limit {
            let haystack = [item.title, item.url].joined(separator: " ").lowercased()
            guard haystack.contains(normalized) else { continue }
            append(
                BrowserSuggestionItem(
                    id: "shortcut:\(item.id.uuidString)",
                    title: item.title,
                    subtitle: item.url,
                    iconName: item.icon.isEmpty ? "globe" : item.icon,
                    destination: .url(URL(string: item.url))
                )
            )
        }

        if appState.settings.browserSuggestsBugbookPages {
            for entry in searchableEntries where suggestions.count < limit {
                guard entry.normalizedHaystack.contains(normalized) else { continue }
                append(
                    BrowserSuggestionItem(
                        id: "entry:\(entry.id)",
                        title: entry.displayName,
                        subtitle: entry.entry.path,
                        iconName: entry.iconName,
                        destination: .entry(entry.entry)
                    )
                )
            }
        }

        if let directURL = resolvedURL(from: trimmed), suggestions.count < limit {
            append(
                BrowserSuggestionItem(
                    id: "url:\(directURL.absoluteString)",
                    title: directURL.absoluteString,
                    subtitle: "Open address",
                    iconName: "link",
                    destination: .url(directURL)
                )
            )
        }

        if suggestions.count < limit {
            append(
                BrowserSuggestionItem(
                    id: "search:\(normalized)",
                    title: "Search \(appState.settings.browserSearchEngine.displayName)",
                    subtitle: trimmed,
                    iconName: "magnifyingglass",
                    destination: .search(trimmed)
                )
            )
        }

        return Array(suggestions.prefix(limit))
    }

    private func applySuggestion(_ suggestion: BrowserSuggestionItem) {
        switch suggestion.destination {
        case .url(let url):
            guard let url else { return }
            browserManager.openURL(url, in: paneID, newTab: false)
            omnibarText = url.absoluteString
            newTabSearchText = ""
            dismissSuggestionUI()
        case .entry(let entry):
            dismissSuggestionUI()
            newTabSearchText = ""
            onOpenBugbookEntry(entry)
        case .search(let query):
            submitOmnibar(query)
        }
    }

    private func submitOmnibar(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch resolveDestination(for: trimmed) {
        case .directURL(let url), .webSearch(let url):
            browserManager.openURL(url, in: paneID, newTab: false)
            omnibarText = url.absoluteString
            newTabSearchText = ""
            dismissSuggestionUI()
        case .bugbookEntry(let entry):
            dismissSuggestionUI()
            newTabSearchText = ""
            onOpenBugbookEntry(entry)
        }
    }

    private func openQuickLaunch(_ item: BrowserQuickLaunchItem) {
        guard let url = URL(string: item.url) else { return }
        browserManager.openURL(url, in: paneID, newTab: false)
        omnibarText = url.absoluteString
        newTabSearchText = ""
        dismissSuggestionUI()
    }

    private func resolveDestination(for input: String) -> BrowserOmnibarDestination {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let wikiLink = trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]")
            ? String(trimmed.dropFirst(2).dropLast(2))
            : trimmed

        if let directURL = resolvedURL(from: trimmed) {
            return .directURL(directURL)
        }

        if let entry = matchEntry(for: wikiLink) {
            return .bugbookEntry(entry)
        }

        let searchURL = appState.settings.browserSearchEngine.searchURL(for: trimmed)
            ?? URL(string: "https://duckduckgo.com/?q=\(trimmed)")!
        return .webSearch(searchURL)
    }

    private func resolvedURL(from input: String) -> URL? {
        if input.hasPrefix("http://") || input.hasPrefix("https://") {
            return URL(string: input)
        }
        if input.contains(".") && !input.contains(" ") {
            return URL(string: "https://\(input)")
        }
        return nil
    }

    private func matchEntry(for input: String) -> FileEntry? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return searchableEntries.first {
            $0.normalizedDisplayName == normalized || $0.normalizedPath == normalized
        }?.entry
    }

    private func makeSearchableEntries(from entries: [FileEntry]) -> [BrowserSearchableEntry] {
        entries.flatMap { entry in
            var searchable: [BrowserSearchableEntry] = []
            if !entry.isDirectory {
                searchable.append(BrowserSearchableEntry(entry: entry))
            }
            searchable.append(contentsOf: makeSearchableEntries(from: entry.children ?? []))
            return searchable
        }
    }

    private func tabColor(for tab: BrowserTabState) -> Color {
        tabColorSeed(tab.host.isEmpty ? tab.displayTitle : tab.host)
    }

    private func tabColorSeed(_ seed: String) -> Color {
        let scalar = abs(seed.hashValue % 360)
        return Color(hue: Double(scalar) / 360.0, saturation: 0.55, brightness: 0.82)
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = NSFullUserName().components(separatedBy: " ").first ?? "there"
        switch hour {
        case 5..<12:
            return "Good morning, \(name)"
        case 12..<18:
            return "Good afternoon, \(name)"
        default:
            return "Good evening, \(name)"
        }
    }

    private func saveCurrentTab() async {
        guard let workspacePath = appState.workspacePath,
              let tabID = selectedTabID else { return }

        if let result = try? await agentService.saveTab(
            from: paneID,
            tabID: tabID,
            browserManager: browserManager,
            fileSystem: fileSystem,
            workspacePath: workspacePath,
            settings: appState.settings,
            aiService: aiService
        ) {
            refreshSavedRecords()
            saveMessage = "Saved to \((result.record.folderPath as NSString).lastPathComponent)/"
        }
    }

    private func openSavedNote(_ record: SavedWebPageRecord) {
        let name = (record.notePath as NSString).lastPathComponent
        let entry = FileEntry(
            id: record.notePath,
            name: name,
            path: record.notePath,
            isDirectory: false,
            kind: .page
        )
        onOpenBugbookEntry(entry)
    }

    private func toggleSavedStatus(_ record: SavedWebPageRecord) {
        guard let workspacePath = appState.workspacePath else { return }
        let nextStatus: SavedWebPageStatus = record.status == .read ? .unread : .read
        savedPageStore.markStatus(nextStatus, for: record.id, in: workspacePath)
        refreshSavedRecords()
        saveMessage = nextStatus == .read ? "Marked read" : "Marked unread"
    }

    private func unsave(_ record: SavedWebPageRecord) {
        guard let workspacePath = appState.workspacePath else { return }
        savedPageStore.remove(recordID: record.id, in: workspacePath)
        refreshSavedRecords()
        if let tabID = selectedTabID {
            session.updateSavedRecordID(nil, for: tabID)
        }
        saveMessage = "Removed from saved pages"
    }

    private func openInExternalBrowser() {
        guard let url = activeTab?.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func openViewSource() {
        guard let urlString = activeTab?.urlString,
              !urlString.isEmpty,
              let sourceURL = URL(string: "view-source:\(urlString)") else {
            return
        }
        NSWorkspace.shared.open(sourceURL)
    }

    private func adjustZoom(by delta: Double) {
        let currentZoom = activeTab?.pageZoom ?? 1.0
        let nextZoom = max(0.5, min(3.0, currentZoom + delta))
        browserManager.setPageZoom(nextZoom, in: paneID)
    }

    func prepareCleanup() {
        cleanupProposals = agentService.proposeCleanup(
            for: paneID,
            browserManager: browserManager,
            workspacePath: appState.workspacePath
        )
        showCleanupSheet = true
    }

    private func applyCleanup() async {
        guard let workspacePath = appState.workspacePath else { return }
        isApplyingCleanup = true
        let summary = await agentService.applyCleanup(
            cleanupProposals,
            paneID: paneID,
            browserManager: browserManager,
            fileSystem: fileSystem,
            workspacePath: workspacePath,
            settings: appState.settings,
            aiService: aiService
        )
        isApplyingCleanup = false
        refreshSavedRecords()
        saveMessage = summary
        showCleanupSheet = false
    }

    private func dismissSuggestionUI() {
        omnibarSuggestions = []
        newTabSuggestions = []
        omnibarFocused = false
        newTabSearchFocused = false
    }
}

struct BrowserSuggestionItem: Identifiable {
    enum Destination {
        case url(URL?)
        case entry(FileEntry)
        case search(String)
    }

    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let destination: Destination
}

private struct BrowserSearchableEntry: Identifiable {
    let entry: FileEntry
    let displayName: String
    let normalizedDisplayName: String
    let normalizedPath: String
    let normalizedHaystack: String
    let iconName: String

    var id: String { entry.id }

    init(entry: FileEntry) {
        let displayName = entry.name.hasSuffix(".md") ? String(entry.name.dropLast(3)) : entry.name
        self.entry = entry
        self.displayName = displayName
        self.normalizedDisplayName = displayName.lowercased()
        self.normalizedPath = entry.path.lowercased()
        self.normalizedHaystack = [displayName, entry.path].joined(separator: " ").lowercased()
        self.iconName = entry.icon ?? "doc.text"
    }
}

private struct BrowserTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct BrowserHostViewContainer: NSViewRepresentable {
    let hostView: NSView

    func makeNSView(context: Context) -> BrowserWebContainerView {
        let view = BrowserWebContainerView()
        view.host(view: hostView)
        return view
    }

    func updateNSView(_ nsView: BrowserWebContainerView, context: Context) {
        nsView.host(view: hostView)
    }
}

private final class BrowserWebContainerView: NSView {
    private weak var hostedView: NSView?

    func host(view: NSView) {
        guard hostedView !== view else { return }
        hostedView?.removeFromSuperview()
        hostedView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: spacing)], spacing: spacing) {
            content
        }
    }
}
