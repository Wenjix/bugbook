import SwiftUI
import AppKit

struct TerminalSettingsView: View {
    @Bindable var appState: AppState
    @State private var themes: [String] = []
    @State private var editingMode: TerminalColorSchemeMode = .light
    @State private var search = ""
    @State private var highlightedTheme: String?

    private var editingBinding: Binding<String> {
        switch editingMode {
        case .light: return $appState.settings.terminalLightTheme
        case .dark: return $appState.settings.terminalDarkTheme
        case .system: return $appState.settings.terminalLightTheme
        }
    }

    private var currentSelection: String {
        editingBinding.wrappedValue
    }

    /// Theme shown in preview: highlighted (arrow key) takes priority, then current selection.
    private var previewTheme: String {
        highlightedTheme ?? currentSelection
    }

    private var filtered: [String] {
        if search.isEmpty { return themes }
        return themes.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Color Scheme") {
                HStack(spacing: 16) {
                    TerminalSchemeCard(label: "Light", isSelected: appState.settings.terminalColorScheme == .light, isDark: false) {
                        appState.settings.terminalColorScheme = .light
                    }
                    TerminalSchemeCard(label: "Dark", isSelected: appState.settings.terminalColorScheme == .dark, isDark: true) {
                        appState.settings.terminalColorScheme = .dark
                    }
                    TerminalSchemeCard(label: "System", isSelected: appState.settings.terminalColorScheme == .system, isDark: nil) {
                        appState.settings.terminalColorScheme = .system
                    }
                }
            }

            SettingsSection("Themes") {
                // Mode tabs + current theme indicator
                HStack(spacing: 0) {
                    modeTab("Light Theme", mode: .light)
                    modeTab("Dark Theme", mode: .dark)
                    Spacer()
                }

                // Active theme badge
                HStack(spacing: 6) {
                    if !currentSelection.isEmpty,
                       let colors = TerminalManager.themeColors(for: currentSelection) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: colors.background))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                            .frame(width: 14, height: 14)
                    }
                    Text("Active:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(currentSelection.isEmpty ? "Default (Ghostty config)" : currentSelection)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.06))
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.15), lineWidth: 1))

                // Side-by-side: list + preview
                HStack(alignment: .top, spacing: 12) {
                    // Theme list
                    VStack(spacing: 0) {
                        // Search
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            TextField("Search...", text: $search)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        Divider()

                        // Scrollable list
                        ThemeListView(
                            themes: filtered,
                            selection: editingBinding,
                            highlighted: $highlightedTheme,
                            search: $search
                        )
                    }
                    .frame(width: 200)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                    // Preview
                    TerminalPreview(themeName: previewTheme)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 260)
            }
        }
        .task {
            themes = TerminalManager.availableThemes()
            editingMode = appState.settings.terminalColorScheme == .dark ? .dark : .light
        }
    }

    private func modeTab(_ label: String, mode: TerminalColorSchemeMode) -> some View {
        Button {
            editingMode = mode
            highlightedTheme = nil
        } label: {
            Text(label)
                .font(.system(size: 12, weight: editingMode == mode ? .semibold : .regular))
                .foregroundStyle(editingMode == mode ? Color.accentColor : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(editingMode == mode ? Color.accentColor.opacity(0.1) : Color.clear)
                .clipShape(.rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme List with keyboard navigation

private struct ThemeListView: NSViewRepresentable {
    let themes: [String]
    @Binding var selection: String
    @Binding var highlighted: String?
    @Binding var search: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("theme"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.rowHeight = 28
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = false
        tableView.intercellSpacing = NSSize(width: 0, height: 0)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        let oldThemes = coord.themes
        coord.parent = self
        coord.themes = themes

        guard let tableView = coord.tableView else { return }

        if oldThemes != themes {
            tableView.reloadData()
        }

        // Scroll to and highlight current selection
        let targetName = selection
        if let idx = themes.firstIndex(of: targetName) {
            let row = idx + 1 // +1 for Default row
            if tableView.selectedRow != row {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                tableView.scrollRowToVisible(row)
            }
        } else if selection.isEmpty {
            if tableView.selectedRow != 0 {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
        }
    }

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: ThemeListView
        var themes: [String] = []
        weak var tableView: NSTableView?

        init(_ parent: ThemeListView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            themes.count + 1
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            ThemeRowView()
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let name = row == 0 ? "" : themes[row - 1]
            let displayName = row == 0 ? "Default" : name
            let isActive = name == parent.selection

            let cell = NSTextField(labelWithString: "")
            cell.lineBreakMode = .byTruncatingTail

            let attributed = NSMutableAttributedString()

            // Color bullet
            if !name.isEmpty, let colors = TerminalManager.themeColors(for: name) {
                let bullet = NSAttributedString(string: "● ", attributes: [
                    .foregroundColor: NSColor(Color(hex: colors.ansi(2) ?? colors.foreground)),
                    .font: NSFont.systemFont(ofSize: 8)
                ])
                attributed.append(bullet)
            }

            // Theme name
            let textColor: NSColor = isActive ? .controlAccentColor : .labelColor
            let weight: NSFont.Weight = isActive ? .semibold : .regular
            let text = NSAttributedString(string: displayName, attributes: [
                .foregroundColor: textColor,
                .font: NSFont.systemFont(ofSize: 12, weight: weight)
            ])
            attributed.append(text)

            cell.attributedStringValue = attributed

            // Build row: [text ... checkmark]
            let container = NSView()
            container.addSubview(cell)
            cell.translatesAutoresizingMaskIntoConstraints = false

            if isActive {
                let check = NSTextField(labelWithString: "✓")
                check.font = NSFont.systemFont(ofSize: 11, weight: .bold)
                check.textColor = .controlAccentColor
                check.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(check)
                NSLayoutConstraint.activate([
                    cell.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                    cell.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    check.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                    check.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    cell.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -4)
                ])
            } else {
                NSLayoutConstraint.activate([
                    cell.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                    cell.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                    cell.centerYAnchor.constraint(equalTo: container.centerYAnchor)
                ])
            }

            return container
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            guard row >= 0 else { return }
            let name = row == 0 ? "" : (row - 1 < themes.count ? themes[row - 1] : "")
            parent.highlighted = name.isEmpty ? nil : name
            parent.selection = name
        }
    }

    /// Custom row view with a subtle selection highlight instead of the default dark one.
    private class ThemeRowView: NSTableRowView {
        override func drawSelection(in dirtyRect: NSRect) {
            let accent = NSColor.controlAccentColor.withAlphaComponent(0.12)
            accent.setFill()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4)
            path.fill()
        }
    }
}

// MARK: - Terminal Preview

private struct TerminalPreview: View {
    let themeName: String

    private var colors: TerminalManager.ThemeColors? {
        guard !themeName.isEmpty else { return nil }
        return TerminalManager.themeColors(for: themeName)
    }

    private var bg: Color { Color(hex: colors?.background ?? "#1e1e2e") }
    private var fg: Color { Color(hex: colors?.foreground ?? "#cdd6f4") }
    private var green: Color { Color(hex: colors?.ansi(2) ?? "#a6e3a1") }
    private var blue: Color { Color(hex: colors?.ansi(4) ?? "#89b4fa") }
    private var yellow: Color { Color(hex: colors?.ansi(3) ?? "#f9e2af") }
    private var red: Color { Color(hex: colors?.ansi(1) ?? "#f38ba8") }
    private var cyan: Color { Color(hex: colors?.ansi(6) ?? "#94e2d5") }
    private var dim: Color { fg.opacity(0.5) }
    private var cursorCol: Color { Color(hex: colors?.cursorColor ?? colors?.foreground ?? "#cdd6f4") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                promptLine("ls -la src/")
                outLine("drwxr-xr-x  5 max  staff  160 ", hl: "components/", c: blue)
                outLine("drwxr-xr-x  3 max  staff   96 ", hl: "utils/", c: blue)
                outLine("-rw-r--r--  1 max  staff  842 ", hl: "index.ts", c: fg)
                outLine("-rw-r--r--  1 max  staff  234 ", hl: "config.json", c: yellow)

                Spacer().frame(height: 6)

                promptLine("git status")
                mono { Text("On branch ").foregroundColor(fg) + Text("dev").foregroundColor(cyan) }
                mono { Text("Changes not staged:").foregroundColor(fg) }
                mono { Text("  modified:   ").foregroundColor(red) + Text("src/index.ts").foregroundColor(red) }

                Spacer().frame(height: 6)

                HStack(spacing: 0) {
                    Text("~ ").foregroundColor(green)
                    Text("❯ ").foregroundColor(blue)
                    Rectangle().fill(cursorCol).frame(width: 7, height: 13)
                }
                .font(.system(size: 11, design: .monospaced))
            }
            .padding(10)

            Spacer(minLength: 0)

            // Theme name footer
            if !themeName.isEmpty {
                HStack {
                    Spacer()
                    Text(themeName)
                        .font(.system(size: 10))
                        .foregroundStyle(fg.opacity(0.4))
                        .padding(.trailing, 10)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: themeName)
    }

    private func promptLine(_ cmd: String) -> some View {
        HStack(spacing: 0) {
            Text("~ ").foregroundColor(green)
            Text("❯ ").foregroundColor(blue)
            Text(cmd).foregroundColor(fg)
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func outLine(_ prefix: String, hl: String, c: Color) -> some View {
        HStack(spacing: 0) {
            Text(prefix).foregroundColor(dim)
            Text(hl).foregroundColor(c)
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func mono(@ViewBuilder content: () -> Text) -> some View {
        content()
            .font(.system(size: 11, design: .monospaced))
    }
}

// MARK: - Color Scheme Cards

private struct TerminalSchemeCard: View {
    let label: String
    let isSelected: Bool
    let isDark: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                if let isDark {
                    miniTerminal(dark: isDark)
                } else {
                    splitMini
                }
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func miniTerminal(dark: Bool) -> some View {
        let bg = dark ? Color(hex: "1e1e2e") : Color(hex: "f5f5f5")
        let p = dark ? Color(hex: "a6e3a1") : Color(hex: "40a02b")
        let t = dark ? Color(hex: "cdd6f4") : Color(hex: "4c4f69")
        let d = dark ? Color(hex: "6c7086") : Color(hex: "9ca0b0")
        return miniLines(bg: bg, p: p, t: t, d: d).frame(width: 120, height: 64)
    }

    private var splitMini: some View {
        HStack(spacing: 0) {
            miniLines(bg: Color(hex: "f5f5f5"), p: Color(hex: "40a02b"), t: Color(hex: "4c4f69"), d: Color(hex: "9ca0b0"))
                .frame(width: 60, height: 64).clipped()
            miniLines(bg: Color(hex: "1e1e2e"), p: Color(hex: "a6e3a1"), t: Color(hex: "cdd6f4"), d: Color(hex: "6c7086"))
                .frame(width: 60, height: 64).clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .frame(width: 120, height: 64)
    }

    private func miniLines(bg: Color, p: Color, t: Color, d: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) { pill(p, 8); pill(t, 20) }
            pill(d, 32)
            HStack(spacing: 3) { pill(p, 8); pill(t, 14) }
            HStack(spacing: 3) { pill(p, 8); RoundedRectangle(cornerRadius: 0.5).fill(t).frame(width: 4, height: 4) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private func pill(_ color: Color, _ w: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(color).frame(width: w, height: 3)
    }
}
