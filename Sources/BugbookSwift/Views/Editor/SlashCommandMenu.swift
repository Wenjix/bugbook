import SwiftUI

/// Slash command popup menu for block type conversion.
struct SlashCommandMenu: View {
    @ObservedObject var document: BlockDocument

    var body: some View {
        let commands = document.filteredSlashCommands

        VStack(alignment: .leading, spacing: 0) {
            if commands.isEmpty {
                Text("No results")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(commands.enumerated()), id: \.offset) { index, command in
                    Button {
                        document.slashMenuSelectedIndex = index
                        document.executeSlashCommand()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: command.icon)
                                .frame(width: 20)
                                .foregroundColor(.secondary)
                            Text(command.name)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            index == document.slashMenuSelectedIndex
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 200)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
