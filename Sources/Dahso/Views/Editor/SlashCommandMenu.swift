import SwiftUI

/// Slash command popup menu for block type conversion.
struct SlashCommandMenu: View {
    var document: BlockDocument
    @State private var hoverActive = false

    private var sections: [(name: String, commands: [(index: Int, command: BlockDocument.SlashCommand)])] {
        let commands = document.filteredSlashCommands
        var sectionOrder: [String] = []
        var grouped: [String: [(index: Int, command: BlockDocument.SlashCommand)]] = [:]
        for (index, command) in commands.enumerated() {
            if grouped[command.section] == nil {
                sectionOrder.append(command.section)
            }
            grouped[command.section, default: []].append((index, command))
        }
        return sectionOrder.compactMap { name in
            guard let items = grouped[name] else { return nil }
            return (name, items)
        }
    }

    var body: some View {
        let commands = document.filteredSlashCommands

        if commands.isEmpty {
            Text("No results")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: 220)
                .popoverSurface()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sections, id: \.name) { section in
                            Text(section.name)
                                .font(.system(size: Typography.caption2, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.top, section.name == sections.first?.name ? 6 : 10)
                                .padding(.bottom, 4)

                            ForEach(section.commands, id: \.index) { item in
                                SlashCommandRow(
                                    command: item.command,
                                    isSelected: item.index == document.slashMenuSelectedIndex
                                ) {
                                    document.slashMenuSelectedIndex = item.index
                                    document.executeSlashCommand()
                                } onHover: {
                                    hoverActive = true
                                    document.slashMenuSelectedIndex = item.index
                                }
                                .id(item.index)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.automatic)
                .onChange(of: document.slashMenuSelectedIndex) { _, newIndex in
                    if !hoverActive {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                    hoverActive = false
                }
            }
            .frame(width: 220, height: min(CGFloat(commands.count) * 30 + CGFloat(sections.count) * 24, 320))
            .popoverSurface()
        }
    }
}

private struct SlashCommandRow: View {
    let command: BlockDocument.SlashCommand
    let isSelected: Bool
    let action: () -> Void
    let onHover: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: command.icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(command.name)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected || isHovered
                    ? Color.accentColor.opacity(0.1)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
    }
}
