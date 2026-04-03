import SwiftUI

/// Full-screen overlay showing keyboard shortcuts, triggered by Cmd+/.
/// Tap anywhere or press Escape/Cmd+/ to dismiss.
struct KeyboardShortcutOverlay: View {
    var onDismiss: () -> Void

    private let primarySections: [(title: String, shortcuts: [(keys: String, label: String)])] = [
        ("Panes", [
            ("\u{2318}\u{2325}\u{2190}/\u{2192}/\u{2191}/\u{2193}", "Move focus between panes"),
            ("\u{2318}D", "Split pane right"),
            ("\u{2318}\u{21E7}E", "Split pane down"),
            ("\u{2318}\u{21E7}W", "Close workspace"),
        ]),
        ("Navigation", [
            ("\u{2318}K", "Quick open"),
            ("\u{2318}1\u{2013}9", "Switch workspace"),
            ("\u{2318}T", "New tab"),
            ("\u{2318}W", "Close tab"),
            ("\u{2318}B", "Toggle sidebar"),
            ("\u{2318}[  \u{2318}]", "Back / Forward"),
        ]),
    ]

    private let secondarySections: [(title: String, shortcuts: [(keys: String, label: String)])] = [
        ("Views", [
            ("\u{2318}\u{21E7}0", "Home"),
            ("\u{2318}\u{21E7}M", "Mail"),
            ("\u{2318}\u{21E7}Y", "Calendar"),
            ("\u{2318}I", "Ask AI"),
            ("\u{2318}\u{21E7}D", "Today's note"),
        ]),
        ("Editor", [
            ("\u{2318}N", "New note"),
            ("\u{2318}\u{21E7}L", "Toggle theme"),
            ("\u{2318}+/\u{2318}-", "Zoom in/out"),
        ]),
    ]

    private let workflows: [(keys: String, label: String)] = [
        ("\u{2318}D \u{2192} \u{2318}\u{21E7}Y", "Open Calendar beside current pane"),
        ("\u{2318}D \u{2192} \u{2318}\u{21E7}M", "Open Mail beside current pane"),
        ("\u{2318}\u{2325}\u{2192} \u{2192} \u{2318}D", "Focus right pane, then split it"),
        ("\u{2318}T \u{2192} \u{2318}\u{21E7}0", "New workspace tab with Home"),
    ]

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

    private func shortcutSection(_ title: String, shortcuts: [(keys: String, label: String)], isPrimary: Bool) -> some View {
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
