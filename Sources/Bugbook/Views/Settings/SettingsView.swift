import SwiftUI

struct SettingsView: View {
    var appState: AppState

    private var tabTitle: String {
        switch appState.selectedSettingsTab {
        case "general": return "General"
        case "appearance": return "Appearance"
        case "ai": return "AI"
        case "google", "calendar": return "Google"
        case "terminal": return "Terminal"
        case "agents": return "Agents"
        case "search": return "Search"
        case "shortcuts": return "Shortcuts"
        default: return "Settings"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Page title
                Text(tabTitle)
                    .font(.system(size: 28, weight: .bold))
                    .padding(.bottom, 32)

                // Content
                switch appState.selectedSettingsTab {
                case "general":
                    GeneralSettingsView(appState: appState)
                case "appearance":
                    AppearanceSettingsView(appState: appState)
                case "ai":
                    AISettingsView(appState: appState)
                case "google", "calendar":
                    GoogleSettingsView(appState: appState)
                case "terminal":
                    TerminalSettingsView(appState: appState)
                case "agents":
                    AgentsSettingsView(appState: appState)
                case "search":
                    SearchSettingsView(appState: appState)
                case "shortcuts":
                    ShortcutsSettingsView()
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.top, 40)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fallbackEditorBg)
    }
}

// MARK: - Shared settings section style

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(.rect(cornerRadius: 10))
        }
    }
}
