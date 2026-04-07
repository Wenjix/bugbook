import SwiftUI

struct BrowserSettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Search") {
                Picker("Search Engine", selection: $appState.settings.browserSearchEngine) {
                    ForEach(BrowserSearchEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Default Save Folder")
                        .font(.system(size: 13))
                    Spacer()
                    TextField("Web Clippings", text: $appState.settings.browserDefaultSaveFolder)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
            }

            SettingsSection("Browser Chrome") {
                Toggle("Show back/forward buttons", isOn: $appState.settings.browserChrome.showsBackForwardButtons)
                Toggle("Show bookmarks bar", isOn: $appState.settings.browserChrome.showsBookmarksBar)
                Toggle("Auto-hide tab pills when only one tab exists", isOn: $appState.settings.browserChrome.autoHidesTabPills)
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
}
