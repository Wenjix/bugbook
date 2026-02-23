import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        GroupBox("Editor") {
            VStack(alignment: .leading, spacing: 4) {
                shortcutRow("Save", "Cmd + S")
                shortcutRow("New Note", "Cmd + N")
                shortcutRow("Slash Command", "/")
            }
            .padding(8)
        }

        GroupBox("Navigation") {
            VStack(alignment: .leading, spacing: 4) {
                shortcutRow("Quick Open", "Cmd + K")
                shortcutRow("Toggle Sidebar", "Cmd + .")
                shortcutRow("New Tab", "Cmd + T")
                shortcutRow("Close Tab", "Cmd + W")
            }
            .padding(8)
        }

        GroupBox("General") {
            VStack(alignment: .leading, spacing: 4) {
                shortcutRow("Settings", "Cmd + ,")
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func shortcutRow(_ label: String, _ shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
    }
}
