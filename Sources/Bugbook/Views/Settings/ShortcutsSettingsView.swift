import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Editor") {
                shortcutRow("New Note", "Cmd + N")
                shortcutRow("Slash Command", "/")
                shortcutRow("Select All (block → page)", "Cmd + A")
            }

            SettingsSection("Navigation") {
                shortcutRow("Quick Open", "Cmd + K / Cmd + P")
                shortcutRow("Toggle Sidebar", "Cmd + .")
                shortcutRow("New Tab", "Cmd + T")
                shortcutRow("Close Tab", "Cmd + W")
            }

            SettingsSection("General") {
                shortcutRow("Settings", "Cmd + ,")
            }
        }
    }

    @ViewBuilder
    private func shortcutRow(_ label: String, _ shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
            Spacer()
            Text(shortcut)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .clipShape(.rect(cornerRadius: 5))
        }
    }
}
