import SwiftUI

enum ShortcutsSettingsCatalog {
    static var sections: [KeyboardShortcutSection] {
        var navigation = [
            KeyboardShortcutEntry(keys: "Cmd + K / Cmd + Shift + P", label: "Quick Open"),
            KeyboardShortcutEntry(keys: "Cmd + .", label: "Toggle Sidebar"),
            KeyboardShortcutEntry(keys: "Cmd + Shift + D", label: "Today's Note"),
            KeyboardShortcutEntry(keys: "Cmd + T", label: "New Workspace"),
            KeyboardShortcutEntry(keys: "Cmd + Opt + T", label: "New Pane Item"),
            KeyboardShortcutEntry(keys: "Cmd + W", label: "Close Item / Pane"),
        ]

        let panes = [
            KeyboardShortcutEntry(keys: "Cmd + Opt + Arrows", label: "Move focus between panes"),
            KeyboardShortcutEntry(keys: "Cmd + D", label: "Split Pane Right"),
            KeyboardShortcutEntry(keys: "Cmd + Ctrl + D", label: "Split Pane Down"),
            KeyboardShortcutEntry(keys: "Cmd + Shift + W", label: "Close Workspace"),
        ]

        if BugbookFeatureGate.legacyPanesEnabled {
            navigation.insert(
                KeyboardShortcutEntry(keys: "Cmd + Shift + C", label: "Toggle Chat Drawer"),
                at: 2
            )
        }

        return [
            KeyboardShortcutSection(title: "Editor", shortcuts: [
                KeyboardShortcutEntry(keys: "Cmd + N", label: "New Note"),
                KeyboardShortcutEntry(keys: "/", label: "Slash Command"),
                KeyboardShortcutEntry(keys: "Cmd + A", label: "Select All (block -> page)"),
                KeyboardShortcutEntry(keys: "Cmd + S", label: "Save Note"),
                KeyboardShortcutEntry(keys: "Cmd + Plus", label: "Zoom in"),
                KeyboardShortcutEntry(keys: "Cmd + Minus", label: "Zoom out"),
                KeyboardShortcutEntry(keys: "Cmd + 0", label: "Reset zoom"),
            ]),
            KeyboardShortcutSection(title: "Block Type", shortcuts: [
                KeyboardShortcutEntry(keys: "Cmd + Opt + 0", label: "Text"),
                KeyboardShortcutEntry(keys: "Cmd + Opt + 1", label: "Heading 1"),
                KeyboardShortcutEntry(keys: "Cmd + Opt + 2", label: "Heading 2"),
                KeyboardShortcutEntry(keys: "Cmd + Opt + 3", label: "Heading 3"),
                KeyboardShortcutEntry(keys: "Cmd + Opt + 4", label: "To-do"),
                KeyboardShortcutEntry(keys: "Cmd + Opt + 5", label: "Bullet List"),
                KeyboardShortcutEntry(keys: "Cmd + Opt + 6", label: "Numbered List"),
                KeyboardShortcutEntry(keys: "Cmd + Opt + 7", label: "Toggle"),
                KeyboardShortcutEntry(keys: "Cmd + Opt + 8", label: "Code Block"),
                KeyboardShortcutEntry(keys: "Cmd + Opt + 9", label: "Create Page"),
            ]),
            KeyboardShortcutSection(title: "Panes", shortcuts: panes),
            KeyboardShortcutSection(title: "Navigation", shortcuts: navigation),
            KeyboardShortcutSection(title: "General", shortcuts: [
                KeyboardShortcutEntry(keys: "Cmd + ,", label: "Settings"),
            ]),
        ]
    }
}

struct ShortcutsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(ShortcutsSettingsCatalog.sections, id: \.title) { section in
                SettingsSection(section.title) {
                    ForEach(section.shortcuts, id: \.label) { shortcut in
                        shortcutRow(shortcut.label, shortcut.keys)
                    }
                }
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
