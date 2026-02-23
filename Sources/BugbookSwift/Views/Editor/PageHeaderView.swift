import SwiftUI

struct PageHeaderView: View {
    @Binding var title: String
    @Binding var icon: String?
    @Binding var coverUrl: String?
    var fullWidth: Bool
    var onTitleCommit: () -> Void

    @State private var showIconPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image (if set)
            if let cover = coverUrl, let url = URL(string: cover) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
                .frame(height: 200)
                .clipped()
            }

            HStack(alignment: .top, spacing: 8) {
                // Icon
                Button(action: { showIconPicker.toggle() }) {
                    if let icon = icon, !icon.isEmpty {
                        Text(icon).font(.system(size: 40))
                    } else {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showIconPicker) {
                    EmojiPickerView(selectedEmoji: $icon)
                }

                // Title
                TextField("Untitled", text: $title, onCommit: onTitleCommit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 32, weight: .bold))
            }
            .padding(.horizontal, fullWidth ? 40 : 80)
            .padding(.top, coverUrl != nil ? 12 : 40)
        }
    }
}

// Simple emoji picker grid
struct EmojiPickerView: View {
    @Binding var selectedEmoji: String?
    @Environment(\.dismiss) private var dismiss

    private let commonEmojis = [
        "\u{1F4DD}", "\u{1F4D6}", "\u{1F4DA}", "\u{1F4D3}", "\u{1F4D2}", "\u{1F4D5}", "\u{1F4D7}", "\u{1F4D8}", "\u{1F4D9}",
        "\u{1F5C2}\u{FE0F}", "\u{1F4C1}", "\u{1F4C2}", "\u{1F5C3}\u{FE0F}", "\u{1F4CB}", "\u{1F4CC}", "\u{1F4CE}", "\u{1F517}",
        "\u{1F4A1}", "\u{2B50}", "\u{1F525}", "\u{1F48E}", "\u{1F3AF}", "\u{1F680}", "\u{26A1}", "\u{1F527}",
        "\u{1F41B}", "\u{1F41E}", "\u{1F98B}", "\u{1F31F}", "\u{1F308}", "\u{1F3A8}", "\u{1F3B5}", "\u{1F3AE}",
        "\u{2764}\u{FE0F}", "\u{1F49A}", "\u{1F499}", "\u{1F49C}", "\u{1F9E1}", "\u{1F49B}", "\u{1F90D}", "\u{1F5A4}",
        "\u{2705}", "\u{274C}", "\u{26A0}\u{FE0F}", "\u{1F4AC}", "\u{1F514}", "\u{1F4CA}", "\u{1F4C8}", "\u{1F5D3}\u{FE0F}"
    ]

    var body: some View {
        VStack(spacing: 8) {
            Text("Choose Icon").font(.headline).padding(.top, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8), spacing: 4) {
                ForEach(commonEmojis, id: \.self) { emoji in
                    Button(action: {
                        selectedEmoji = emoji
                        dismiss()
                    }) {
                        Text(emoji).font(.system(size: 24))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .background(selectedEmoji == emoji ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal, 8)

            Button("Remove Icon") {
                selectedEmoji = nil
                dismiss()
            }
            .padding(.bottom, 8)
        }
        .frame(width: 320)
        .padding(8)
    }
}
