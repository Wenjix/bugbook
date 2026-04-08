import AppKit
import Observation
import SwiftUI
import WebKit

struct BrowserPaneView: View {
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
    @FocusState private var findFocused: Bool
    @State private var omnibarText = ""
    @State private var newTabSearchText = ""
    @State private var showFindBar = false
    @State private var findQuery = ""
    @State private var showCleanupSheet = false
    @State private var cleanupProposals: [BrowserCleanupProposal] = []
    @State private var isApplyingCleanup = false
    @State private var saveMessage: String?
    @State private var hoveredTabID: UUID?

    private let agentService = BrowserAgentService()
    private let savedPageStore = SavedWebPageStore()
    private let relativeDateFormatter = RelativeDateTimeFormatter()

    private var activeTab: BrowserTabState? {
        session.activeTab
    }

    private var activeSavedRecord: SavedWebPageRecord? {
        guard let workspacePath = appState.workspacePath else { return nil }
        if let recordID = activeTab?.savedRecordID {
            return savedPageStore.records(in: workspacePath).first(where: { $0.id == recordID })
        }
        if let urlString = activeTab?.urlString {
            return savedPageStore.record(forURL: urlString, in: workspacePath)
        }
        return nil
    }

    private var chrome: BrowserChromeConfiguration {
        appState.settings.browserChrome
    }

    private var readLaterRecords: [SavedWebPageRecord] {
        guard let workspacePath = appState.workspacePath else { return [] }
        return agentService.listReadLater(in: workspacePath)
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
    }

    private func applyBrowserLifecycle<V: View>(to view: V) -> some View {
        view
        .onAppear {
            syncDisplayedText()
            if let tabID = session.selectedTabID {
                _ = browserManager.ensureWebView(for: paneID, tabID: tabID)
            }
        }
        .onChange(of: session.selectedTabID) { _, _ in
            syncDisplayedText()
            if let tabID = session.selectedTabID {
                _ = browserManager.ensureWebView(for: paneID, tabID: tabID)
            }
        }
        .onChange(of: session.tabs) { _, _ in
            syncDisplayedText()
        }
    }

    private func applyBrowserNotifications<V: View>(to view: V) -> some View {
        view
        .onReceive(NotificationCenter.default.publisher(for: .browserFocusAddressBar)) { _ in
            guard isFocusedPane else { return }
            omnibarFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserNewTab)) { _ in
            guard isFocusedPane else { return }
            createNewTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserCloseTab)) { notification in
            let targetPaneID = notification.object as? UUID
            if let targetPaneID, targetPaneID != paneID {
                return
            }
            guard isFocusedPane, let selected = session.selectedTabID else { return }
            session.closeTab(selected)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserBack)) { _ in
            guard isFocusedPane else { return }
            browserManager.goBack(in: paneID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserForward)) { _ in
            guard isFocusedPane else { return }
            browserManager.goForward(in: paneID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserFind)) { _ in
            guard isFocusedPane else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                showFindBar = true
            }
            findFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserPrint)) { _ in
            guard isFocusedPane else { return }
            browserManager.printActiveTab(in: paneID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserSavePage)) { _ in
            guard isFocusedPane else { return }
            Task { await saveCurrentTab() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserZoomIn)) { _ in
            guard isFocusedPane else { return }
            adjustZoom(by: 0.1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserZoomOut)) { _ in
            guard isFocusedPane else { return }
            adjustZoom(by: -0.1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserZoomReset)) { _ in
            guard isFocusedPane else { return }
            browserManager.setPageZoom(1.0, in: paneID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserPreviousTab)) { _ in
            guard isFocusedPane else { return }
            selectAdjacentTab(step: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserNextTab)) { _ in
            guard isFocusedPane else { return }
            selectAdjacentTab(step: 1)
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

    private var chromeBar: some View {
        VStack(spacing: 0) {
            // Compact tab bar — tabs fill the row, active tab shows URL inline
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
                        .focused($omnibarFocused)
                        .onSubmit {
                            submitOmnibar(omnibarText)
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(omnibarFocused ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                )

                browserActionMenu
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

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
        .background(Color.fallbackTabBarBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.fallbackChromeBorder)
                .frame(height: 1)
        }
    }

    private func compactTab(_ tab: BrowserTabState) -> some View {
        let isSelected = session.selectedTabID == tab.id
        let isHovered = hoveredTabID == tab.id

        return HStack(spacing: 6) {
            // Favicon dot
            Circle()
                .fill(tabColor(for: tab))
                .frame(width: 6, height: 6)
                .padding(.leading, 8)

            if isSelected {
                // Active tab: show editable URL field inline
                TextField("Search or enter URL", text: $omnibarText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($omnibarFocused)
                    .onSubmit {
                        submitOmnibar(omnibarText)
                    }
            } else {
                // Inactive tab: show title
                Button {
                    session.selectTab(tab.id)
                } label: {
                    Text(tab.displayTitle)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            // Close button on hover
            if isHovered && session.tabs.count > 1 {
                Button {
                    session.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .transition(.opacity)
            } else {
                Spacer()
                    .frame(width: 8)
            }
        }
        .frame(height: 28)
        .frame(maxWidth: isSelected ? .infinity : 160)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.primary.opacity(0.06) : (isHovered ? Color.primary.opacity(0.03) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID)
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

            Button("Clean Tabs") {
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
                    browserManager.setPageZoom(1.0, in: paneID)
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
        if let activeTab, !activeTab.urlString.isEmpty {
            if let webView = browserManager.activeWebView(for: paneID) {
                BrowserWebViewContainer(webView: webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.fallbackEditorBg
                    .onAppear {
                        _ = browserManager.ensureWebView(for: paneID, tabID: activeTab.id)
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


            if chrome.showsNewTabRecentVisits, !session.recentVisits.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(session.recentVisits.prefix(8)) { visit in
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
            Text("Clean Tabs")
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
        _ = session.openNewTab()
        newTabSearchText = ""
        omnibarText = ""
        omnibarFocused = true
    }

    private func syncDisplayedText() {
        omnibarText = activeTab?.displayURL ?? ""
        if activeTab?.urlString.isEmpty != false {
            newTabSearchText = ""
        }
    }

    private func submitOmnibar(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch resolveDestination(for: trimmed) {
        case .directURL(let url), .webSearch(let url):
            browserManager.openURL(url, in: paneID, newTab: false)
            omnibarText = url.absoluteString
        case .bugbookEntry(let entry):
            onOpenBugbookEntry(entry)
        }
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
        return flattenedEntries(from: fileTree).first { entry in
            let displayName = entry.name.hasSuffix(".md") ? String(entry.name.dropLast(3)) : entry.name
            return displayName.lowercased() == normalized || entry.path.lowercased() == normalized
        }
    }

    private func flattenedEntries(from entries: [FileEntry]) -> [FileEntry] {
        entries.flatMap { entry in
            let children = flattenedEntries(from: entry.children ?? [])
            return [entry] + children
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
              let tabID = session.selectedTabID else { return }

        if let result = try? await agentService.saveTab(
            from: paneID,
            tabID: tabID,
            browserManager: browserManager,
            fileSystem: fileSystem,
            workspacePath: workspacePath,
            settings: appState.settings,
            aiService: aiService
        ) {
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
        saveMessage = nextStatus == .read ? "Marked read" : "Marked unread"
    }

    private func unsave(_ record: SavedWebPageRecord) {
        guard let workspacePath = appState.workspacePath else { return }
        savedPageStore.remove(recordID: record.id, in: workspacePath)
        if let tabID = session.selectedTabID {
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

    private func selectAdjacentTab(step: Int) {
        guard !session.tabs.isEmpty else { return }
        let currentIndex = session.tabs.firstIndex(where: { $0.id == session.selectedTabID }) ?? 0
        let nextIndex = (currentIndex + step + session.tabs.count) % session.tabs.count
        session.selectTab(session.tabs[nextIndex].id)
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
        saveMessage = summary
        showCleanupSheet = false
    }
}

private struct BrowserWebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> BrowserWebContainerView {
        let view = BrowserWebContainerView()
        view.host(webView: webView)
        return view
    }

    func updateNSView(_ nsView: BrowserWebContainerView, context: Context) {
        nsView.host(webView: webView)
    }
}

private final class BrowserWebContainerView: NSView {
    private weak var hostedWebView: WKWebView?

    func host(webView: WKWebView) {
        guard hostedWebView !== webView else { return }
        hostedWebView?.removeFromSuperview()
        hostedWebView = webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

private struct FlowLayout<Content: View>: View {
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
