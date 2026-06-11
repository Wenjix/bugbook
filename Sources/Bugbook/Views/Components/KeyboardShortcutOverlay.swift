import SwiftUI

struct KeyboardShortcutEntry: Equatable {
    let keys: String
    let label: String
}

struct KeyboardShortcutSection: Equatable {
    let title: String
    let shortcuts: [KeyboardShortcutEntry]
}

enum KeyboardShortcutCatalog {
    static var primarySections: [KeyboardShortcutSection] {
        [
            KeyboardShortcutSection(title: "Tabs", shortcuts: [
                KeyboardShortcutEntry(keys: "\u{2318}T", label: "New tab"),
                KeyboardShortcutEntry(keys: "\u{2318}W", label: "Close tab"),
                KeyboardShortcutEntry(keys: "\u{2318}1\u{2013}9", label: "Switch tab"),
                KeyboardShortcutEntry(keys: "\u{2318}\u{21E7}[  \u{2318}\u{21E7}]", label: "Previous / Next tab"),
            ]),
            KeyboardShortcutSection(title: "Navigation", shortcuts: [
                KeyboardShortcutEntry(keys: "\u{2318}K / \u{2318}\u{21E7}P", label: "Quick open"),
                KeyboardShortcutEntry(keys: "\u{2318}.", label: "Toggle sidebar"),
                KeyboardShortcutEntry(keys: "\u{2318}[  \u{2318}]", label: "Back / Forward"),
            ]),
        ]
    }

    static var secondarySections: [KeyboardShortcutSection] {
        let viewShortcuts = BugbookFeatureGate.legacyPanesEnabled
            ? [
                KeyboardShortcutEntry(keys: "\u{2318}\u{21E7}0", label: "Home"),
                KeyboardShortcutEntry(keys: "\u{2318}\u{21E7}M", label: "Mail"),
                KeyboardShortcutEntry(keys: "\u{2318}\u{21E7}Y", label: "Calendar"),
                KeyboardShortcutEntry(keys: "\u{2318}\u{21E7}C", label: "Chat drawer"),
                KeyboardShortcutEntry(keys: "\u{2318}\u{21E7}D", label: "Today's note"),
            ]
            : [
                KeyboardShortcutEntry(keys: "\u{2318}\u{21E7}D", label: "Today's note"),
            ]

        let editorShortcuts = [
            KeyboardShortcutEntry(keys: "\u{2318}N", label: "New note"),
            KeyboardShortcutEntry(keys: "\u{2318}S", label: "Save note"),
            KeyboardShortcutEntry(keys: "\u{2318}\u{21E7}L", label: "Toggle theme"),
            KeyboardShortcutEntry(keys: "\u{2318}F", label: "Find in page"),
        ]

        return [
            KeyboardShortcutSection(title: "Views", shortcuts: viewShortcuts),
            KeyboardShortcutSection(title: "Editor", shortcuts: editorShortcuts),
        ]
    }

    static var workflows: [KeyboardShortcutEntry] {
        guard BugbookFeatureGate.legacyPanesEnabled else { return [] }
        return [
            KeyboardShortcutEntry(keys: "\u{2318}T \u{2192} \u{2318}\u{21E7}0", label: "New workspace tab with Home"),
        ]
    }
}

/// Full-screen overlay showing keyboard shortcuts, triggered by Cmd+/.
/// Tap anywhere or press Escape/Cmd+/ to dismiss.
struct KeyboardShortcutOverlay: View {
    var onDismiss: () -> Void

    private var primarySections: [KeyboardShortcutSection] { KeyboardShortcutCatalog.primarySections }
    private var secondarySections: [KeyboardShortcutSection] { KeyboardShortcutCatalog.secondarySections }
    private var workflows: [KeyboardShortcutEntry] { KeyboardShortcutCatalog.workflows }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Keyboard Shortcuts")
                        .font(.system(size: Typography.title3, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\u{2318}/")
                        .font(.system(size: Typography.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(Opacity.subtle))
                        .clipShape(.rect(cornerRadius: Radius.xs))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Primary sections — full visual weight
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
                            alignment: .leading,
                            spacing: 16
                        ) {
                            ForEach(primarySections, id: \.title) { section in
                                shortcutSection(section.title, shortcuts: section.shortcuts, isPrimary: true)
                            }
                        }

                        Divider()
                            .padding(.vertical, 2)

                        // Secondary sections — dimmer
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
                            alignment: .leading,
                            spacing: 16
                        ) {
                            ForEach(secondarySections, id: \.title) { section in
                                shortcutSection(section.title, shortcuts: section.shortcuts, isPrimary: false)
                            }
                        }

                        if !workflows.isEmpty {
                            Divider()
                                .padding(.vertical, 2)

                            // Workflows — composed shortcuts
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Workflows")
                                    .font(.system(size: Typography.caption2, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                ForEach(workflows, id: \.label) { wf in
                                    HStack(spacing: 10) {
                                        Text(wf.keys)
                                            .font(.system(size: Typography.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 160, alignment: .trailing)

                                        Text(wf.label)
                                            .font(.system(size: Typography.bodySmall))
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
            .frame(width: 540)
            .frame(maxHeight: 520)
            .background(Color.fallbackEditorBg)
            .clipShape(.rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.fallbackBorderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        }
        .onExitCommand { onDismiss() }
    }

    private func shortcutSection(_ title: String, shortcuts: [KeyboardShortcutEntry], isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: Typography.caption2, weight: .semibold))
                .foregroundStyle(isPrimary ? .secondary : .tertiary)
                .textCase(.uppercase)

            ForEach(shortcuts, id: \.label) { shortcut in
                HStack(spacing: 10) {
                    Text(shortcut.keys)
                        .font(.system(size: Typography.caption, design: .monospaced))
                        .foregroundStyle(isPrimary ? .secondary : .quaternary)
                        .frame(width: 100, alignment: .trailing)

                    Text(shortcut.label)
                        .font(.system(size: Typography.bodySmall))
                        .foregroundStyle(isPrimary ? .primary : .secondary)
                }
            }
        }
    }
}
