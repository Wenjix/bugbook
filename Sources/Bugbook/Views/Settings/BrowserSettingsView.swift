import SwiftUI

struct BrowserSettingsView: View {
    @Bindable var appState: AppState
    @Bindable var browserManager: BrowserManager
    @State private var dataMessage: String?
    @State private var isClearingCookies = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Search") {
                Picker("Search Engine", selection: $appState.settings.browserSearchEngine) {
                    ForEach(BrowserSearchEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Enable search suggestions", isOn: $appState.settings.browserSuggestionsEnabled)
                Toggle("Suggest Bugbook pages", isOn: $appState.settings.browserSuggestsBugbookPages)
                    .disabled(!appState.settings.browserSuggestionsEnabled)

                HStack {
                    Text("Suggestion Count")
                        .font(.system(size: 13))
                    Spacer()
                    Stepper(value: $appState.settings.browserSuggestionLimit, in: 3...12) {
                        Text("\(appState.settings.browserSuggestionLimit)")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                    }
                    .frame(width: 140)
                    .disabled(!appState.settings.browserSuggestionsEnabled)
                }

                HStack {
                    Text("Default Save Folder")
                        .font(.system(size: 13))
                    Spacer()
                    TextField("Web Clippings", text: $appState.settings.browserDefaultSaveFolder)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
            }

            SettingsSection("History & Privacy") {
                Toggle("Save browsing history", isOn: $appState.settings.browserHistoryEnabled)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("History")
                            .font(.system(size: 13, weight: .medium))
                        Text(historySummary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear History") {
                        browserManager.clearHistory()
                        dataMessage = "Browsing history cleared."
                    }
                    .disabled(browserManager.browsingHistory.isEmpty)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cookies")
                            .font(.system(size: 13, weight: .medium))
                        Text("Clear stored site cookies for the embedded browser.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isClearingCookies ? "Clearing…" : "Clear Cookies") {
                        Task { await clearCookies() }
                    }
                    .disabled(isClearingCookies)
                }

                if let dataMessage, !dataMessage.isEmpty {
                    Text(dataMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if browserManager.browsingHistory.isEmpty {
                    Text("No browsing history yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(browserManager.browsingHistory.prefix(6))) { visit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(visit.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Text(visit.urlString)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
            }

            SettingsSection("Browser Chrome") {
                Toggle("Show back/forward buttons", isOn: $appState.settings.browserChrome.showsBackForwardButtons)
                Toggle("Show bookmarks bar", isOn: $appState.settings.browserChrome.showsBookmarksBar)
                Toggle("Auto-hide tab pills when only one tab exists", isOn: $appState.settings.browserChrome.autoHidesTabPills)
                Toggle("Show save button", isOn: $appState.settings.browserChrome.showsSaveButton)
                Toggle("Show status bar on link hover", isOn: $appState.settings.browserChrome.showsStatusBar)
            }

            SettingsSection("New Tab Page") {
                Toggle("Show greeting", isOn: $appState.settings.browserChrome.showsNewTabGreeting)
                Toggle("Show quick launch", isOn: $appState.settings.browserChrome.showsNewTabQuickLaunch)
                Toggle("Show recent visits", isOn: $appState.settings.browserChrome.showsNewTabRecentVisits)
            }

            SettingsSection("Quick Launch") {
                ForEach($appState.settings.browserQuickLaunchItems) { $item in
                    HStack(spacing: 10) {
                        TextField("Title", text: $item.title)
                            .textFieldStyle(.roundedBorder)
                        TextField("URL", text: $item.url)
                            .textFieldStyle(.roundedBorder)
                        TextField("Icon", text: $item.icon)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        Button {
                            removeQuickLaunch(item.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Shortcut") {
                    appState.settings.browserQuickLaunchItems.append(
                        BrowserQuickLaunchItem(title: "New Shortcut", url: "https://", icon: "globe")
                    )
                }
            }
        }
    }

    private func removeQuickLaunch(_ id: UUID) {
        appState.settings.browserQuickLaunchItems.removeAll { $0.id == id }
    }

    private var historySummary: String {
        let count = browserManager.browsingHistory.count
        if count == 0 {
            return "Your browser history is empty."
        }
        return "\(count) saved visit\(count == 1 ? "" : "s")"
    }

    private func clearCookies() async {
        isClearingCookies = true
        defer { isClearingCookies = false }

        do {
            try await browserManager.clearCookies()
            dataMessage = "Cookies cleared."
        } catch {
            dataMessage = "Failed to clear cookies: \(error.localizedDescription)"
        }
    }
}
