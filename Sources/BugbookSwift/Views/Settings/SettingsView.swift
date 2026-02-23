import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab = "general"

    private let tabs = [
        ("general", "General"),
        ("appearance", "Appearance"),
        ("ai", "AI"),
        ("agents", "Agents"),
        ("shortcuts", "Shortcuts"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(tabs, id: \.0) { tag, label in
                    Text(label).tag(tag)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case "general":
                        GeneralSettingsView(appState: appState)
                    case "appearance":
                        AppearanceSettingsView(appState: appState)
                    case "ai":
                        AISettingsView(appState: appState)
                    case "agents":
                        AgentsSettingsView(appState: appState)
                    case "shortcuts":
                        ShortcutsSettingsView()
                    default:
                        EmptyView()
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .keyboardShortcut(for: "1") { selectedTab = "general" }
        .keyboardShortcut(for: "2") { selectedTab = "appearance" }
        .keyboardShortcut(for: "3") { selectedTab = "ai" }
        .keyboardShortcut(for: "4") { selectedTab = "agents" }
        .keyboardShortcut(for: "5") { selectedTab = "shortcuts" }
    }
}

// MARK: - Keyboard shortcut helper

private struct TabShortcutModifier: ViewModifier {
    let key: KeyEquivalent
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .background(
                Button("") { action() }
                    .keyboardShortcut(key, modifiers: .command)
                    .hidden()
            )
    }
}

private extension View {
    func keyboardShortcut(for key: String, action: @escaping () -> Void) -> some View {
        modifier(TabShortcutModifier(key: KeyEquivalent(key.first!), action: action))
    }
}
